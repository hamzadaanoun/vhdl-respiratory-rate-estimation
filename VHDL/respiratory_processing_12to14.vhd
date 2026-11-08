library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Adaptateur PCA -> filtre passe-bande -> FFT -> BPM.
-- Fenetres de 512 projections. RAM 512x32 pour absorber le flux PCA,
-- puisque pca_rgb n'a pas de signal ready.
-- Une seule fenetre peut etre traitée a la fois; input_ready indique
-- si la prochaine fenetre peut etre recue. Les arrivees pendant le
-- traitement provoquent un pulse input_overflow.
entity respiratory_processing_12to14 is
    port (
        clk, rst         : in  std_logic;
        pca_sample_in   : in  signed(31 downto 0);
        pca_valid_in    : in  std_logic;
        pca_last_in     : in  std_logic;
        input_ready     : out std_logic;
        input_overflow  : out std_logic;
        bpm_out         : out unsigned(7 downto 0);
        bpm_valid       : out std_logic;
        peak_found      : out std_logic;
        peak_bin_out    : out unsigned(8 downto 0);
        peak_mag_out    : out unsigned(31 downto 0);
        done            : out std_logic;
        active          : out std_logic
    );
end entity;

architecture rtl of respiratory_processing_12to14 is
    constant N : integer := 512;
    type ram_t is array(0 to N-1) of signed(31 downto 0);
    signal ram : ram_t;
    attribute ramstyle : string;
    attribute ramstyle of ram : signal is "M10K";

    signal wr_en, rd_en : std_logic := '0';
    signal wr_addr, rd_addr : integer range 0 to N-1 := 0;
    signal wr_data, rd_data : signed(31 downto 0) := (others => '0');

    type state_t is (CAPTURE, READ_REQ, READ_WAIT, SEND_BP,
                     WAIT_BP, WAIT_FFT, WAIT_BPM);
    signal st : state_t := CAPTURE;
    signal capture_idx : integer range 0 to N-1 := 0;
    signal feed_idx : integer range 0 to N-1 := 0;
    signal overflow_reg : std_logic := '0';
    signal bp_in_valid, bp_in_last, bp_in_ready : std_logic := '0';
    signal bp_sample_in : signed(31 downto 0) := (others => '0');
    signal bp_sample_out : signed(31 downto 0);
    signal bp_out_valid, bp_out_last : std_logic;
    signal fft_in_ready, fft_out_valid, fft_out_last : std_logic;
    signal fft_sample_idx : unsigned(8 downto 0);
    signal fft_mag : unsigned(31 downto 0);
    signal fft_done : std_logic;
    signal bpm_done : std_logic;
begin
    input_ready <= '1' when st = CAPTURE else '0';
    active <= '0' when st = CAPTURE else '1';
    input_overflow <= overflow_reg;
    done <= bpm_done;

    -- RAM de stockage de la fenetre PCA, lecture synchrone.
    mem_p : process(clk)
    begin
        if rising_edge(clk) then
            if wr_en = '1' then
                ram(wr_addr) <= wr_data;
            end if;
            if rd_en = '1' then
                rd_data <= ram(rd_addr);
            end if;
        end if;
    end process;

    u_filter : entity work.bandpass_filter
        port map (
            clk => clk, rst => rst,
            sample_in => bp_sample_in,
            in_valid => bp_in_valid, in_last => bp_in_last,
            in_ready => bp_in_ready,
            sample_out => bp_sample_out,
            out_valid => bp_out_valid, out_last => bp_out_last,
            busy => open
        );

    u_fft : entity work.fft_512
        port map (
            clk => clk, rst => rst,
            sample_in => bp_sample_out,
            in_valid => bp_out_valid,
            in_last => bp_out_last,
            in_ready => fft_in_ready,
            bin_index => fft_sample_idx,
            magnitude_out => fft_mag,
            out_valid => fft_out_valid,
            out_last => fft_out_last,
            busy => open,
            done => fft_done
        );

    u_bpm : entity work.bpm_calculator
        port map (
            clk => clk, rst => rst,
            magnitude_in => fft_mag,
            bin_index_in => fft_sample_idx,
            in_valid => fft_out_valid,
            in_last => fft_out_last,
            bpm_out => bpm_out,
            peak_bin_out => peak_bin_out,
            peak_mag_out => peak_mag_out,
            bpm_valid => bpm_valid,
            peak_found => peak_found,
            done => bpm_done
        );

    control_p : process(clk)
    begin
        if rising_edge(clk) then
            wr_en <= '0';
            rd_en <= '0';
            bp_in_valid <= '0';
            bp_in_last <= '0';
            overflow_reg <= '0';
            if rst = '1' then
                st <= CAPTURE;
                capture_idx <= 0;
                feed_idx <= 0;
                bp_sample_in <= (others => '0');
            else
                if pca_valid_in = '1' and st /= CAPTURE then
                    overflow_reg <= '1';
                end if;
                case st is
                    when CAPTURE =>
                        if pca_valid_in = '1' then
                            wr_en <= '1';
                            wr_addr <= capture_idx;
                            wr_data <= pca_sample_in;
                            if capture_idx = N-1 then
                                -- Verification en simulation : la fenetre
                                -- PCA doit finir sur son 512e echantillon.
                                assert pca_last_in = '1'
                                    report "PCA: out_last absent au 512e echantillon"
                                    severity warning;
                                capture_idx <= 0;
                                feed_idx <= 0;
                                st <= READ_REQ;
                            else
                                assert pca_last_in = '0'
                                    report "PCA: out_last premature"
                                    severity warning;
                                capture_idx <= capture_idx + 1;
                            end if;
                        end if;

                    when READ_REQ =>
                        rd_addr <= feed_idx;
                        rd_en <= '1';
                        st <= READ_WAIT;

                    when READ_WAIT =>
                        -- Au prochain front le controle peut lire rd_data
                        -- en toute securite dans SEND_BP.
                        st <= SEND_BP;

                    when SEND_BP =>
                        if bp_in_ready = '1' then
                            bp_sample_in <= rd_data;
                            bp_in_valid <= '1';
                            if feed_idx = N-1 then
                                bp_in_last <= '1';
                            end if;
                            st <= WAIT_BP;
                        end if;

                    when WAIT_BP =>
                        if bp_out_valid = '1' then
                            -- Le filtre produit un echantillon par entree.
                            -- La FFT doit etre encore en acquisition.
                            assert fft_in_ready = '1'
                                report "FFT non prete: echantillon filtre perdu"
                                severity warning;
                            if feed_idx = N-1 then
                                st <= WAIT_FFT;
                            else
                                feed_idx <= feed_idx + 1;
                                st <= READ_REQ;
                            end if;
                        end if;

                    when WAIT_FFT =>
                        -- Attendre la fin de la lecture de la FFT.
                        if fft_done = '1' then
                            st <= WAIT_BPM;
                        end if;

                    when WAIT_BPM =>
                        -- Le BPM peut etre produit au meme cycle que le
                        -- dernier bin FFT; attendre que done ne soit plus haut.
                        if bpm_done = '0' then
                            capture_idx <= 0;
                            st <= CAPTURE;
                        end if;
                end case;
            end if;
        end if;
    end process;
end architecture;

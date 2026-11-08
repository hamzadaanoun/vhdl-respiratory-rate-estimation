library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_textio.all;
use std.textio.all;

entity tb_respiratory_pipeline_14blocks is
end entity;

architecture sim of tb_respiratory_pipeline_14blocks is
    constant CLK_PERIOD : time := 20 ns;
    constant W : positive := 64;
    constant H : positive := 64;
    constant FRAME_COUNT : positive := 515;

    signal clk : std_logic := '0';
    signal rst : std_logic := '1';
    signal rgb_in : std_logic_vector(23 downto 0) := (others => '0');
    signal valid_in, frame_start : std_logic := '0';
    signal mean_r_out, mean_g_out, mean_b_out : std_logic_vector(7 downto 0);
    signal mean_valid_out, buffer_full_out : std_logic;
    signal sample_count_out : unsigned(9 downto 0);
    signal pca_sample_out : signed(31 downto 0);
    signal pca_valid, pca_last, pca_done, transfer_busy : std_logic;
    signal input_ready, input_overflow, processing_active : std_logic;
    signal bpm_out : unsigned(7 downto 0);
    signal bpm_valid, peak_found, processing_done : std_logic;
    signal peak_bin_out : unsigned(8 downto 0);
    signal peak_mag_out : unsigned(31 downto 0);
    signal finished : boolean := false;
    signal mean_events, pca_events, pca_last_events : natural := 0;
    signal overflow_events, bpm_events, done_events : natural := 0;
begin
    clk <= not clk after CLK_PERIOD/2;

    dut : entity work.respiratory_pipeline_14blocks
        generic map (IMG_WIDTH => W, IMG_HEIGHT => H, COORD_BITS => 10,
                     THRESHOLD_VALUE => 100)
        port map (
            clk => clk, rst => rst, rgb_in => rgb_in,
            valid_in => valid_in, frame_start => frame_start,
            mean_r_out => mean_r_out, mean_g_out => mean_g_out,
            mean_b_out => mean_b_out, mean_valid_out => mean_valid_out,
            sample_count_out => sample_count_out,
            buffer_full_out => buffer_full_out,
            pca_sample_out => pca_sample_out, pca_valid => pca_valid,
            pca_last => pca_last, pca_done => pca_done,
            transfer_busy => transfer_busy,
            input_ready => input_ready, input_overflow => input_overflow,
            processing_active => processing_active,
            bpm_out => bpm_out, bpm_valid => bpm_valid,
            peak_found => peak_found, peak_bin_out => peak_bin_out,
            peak_mag_out => peak_mag_out,
            processing_done => processing_done
        );

    counters : process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                mean_events <= 0;
                pca_events <= 0;
                pca_last_events <= 0;
                overflow_events <= 0;
                bpm_events <= 0;
                done_events <= 0;
            else
                if mean_valid_out = '1' then mean_events <= mean_events + 1; end if;
                if pca_valid = '1' then pca_events <= pca_events + 1; end if;
                if pca_last = '1' and pca_valid = '1' then
                    pca_last_events <= pca_last_events + 1;
                end if;
                if input_overflow = '1' then overflow_events <= overflow_events + 1; end if;
                if bpm_valid = '1' then
                    bpm_events <= bpm_events + 1;
                    report "BPM = " & integer'image(to_integer(bpm_out)) &
                           ", pic = " & integer'image(to_integer(peak_bin_out)) &
                           ", peak_found = " & std_logic'image(peak_found);
                end if;
                if processing_done = '1' then done_events <= done_events + 1; end if;
            end if;
        end if;
    end process;

    -- Export numerique des sorties accessibles au top-level.
    export_numerique : process(clk)
        file fmean : text open write_mode is "10_mean_rgb.csv";
        file fpca  : text open write_mode is "11_pca_samples.csv";
        file fbpm  : text open write_mode is "13_bpm_result.txt";
        variable ln : line;
        variable initialized : boolean := false;
        variable nmean : natural := 0;
        variable npca : natural := 0;
    begin
        if rising_edge(clk) then
            if not initialized then
                write(ln, string'("index;R;G;B")); writeline(fmean, ln);
                write(ln, string'("index;pca_signed_32")); writeline(fpca, ln);
                initialized := true;
            end if;
            if rst = '0' then
                if mean_valid_out = '1' then
                    write(ln, nmean); write(ln, string'(";"));
                    write(ln, to_integer(unsigned(mean_r_out))); write(ln, string'(";"));
                    write(ln, to_integer(unsigned(mean_g_out))); write(ln, string'(";"));
                    write(ln, to_integer(unsigned(mean_b_out))); writeline(fmean, ln);
                    nmean := nmean + 1;
                end if;
                if pca_valid = '1' then
                    write(ln, npca); write(ln, string'(";"));
                    write(ln, to_integer(pca_sample_out)); writeline(fpca, ln);
                    npca := npca + 1;
                end if;
                if bpm_valid = '1' then
                    write(ln, string'("BPM=")); write(ln, to_integer(bpm_out));
                    write(ln, string'(";BIN=")); write(ln, to_integer(peak_bin_out));
                    write(ln, string'(";PEAK_FOUND=")); write(ln, std_logic'image(peak_found));
                    writeline(fbpm, ln);
                end if;
            end if;
        end if;
    end process;

    stimulus : process
        file rgb_file : text;
        file fppm : text open write_mode is "01_rgb_original.ppm";
        variable ppm_line : line;
        variable status : file_open_status;
        variable ln : line;
        variable rgb_value : std_logic_vector(23 downto 0);
    begin
        wait for 100 ns;
        wait until falling_edge(clk);
        rst <= '0';
        report "DEBUT VIDEO REELLE : 515 trames; 515 trames du fichier RGB (origine a confirmer)";
        -- PPM ASCII P3 de la premiere trame RGB lue par ModelSim.
        write(ppm_line, string'("P3")); writeline(fppm, ppm_line);
        write(ppm_line, string'("# Premiere trame RGB injectee dans le DUT")); writeline(fppm, ppm_line);
        write(ppm_line, string'("64 64")); writeline(fppm, ppm_line);
        write(ppm_line, string'("255")); writeline(fppm, ppm_line);
        file_open(status, rgb_file, "video_rgb_515frames.txt", read_mode);
        assert status = open_ok report "Fichier video_rgb_515frames.txt introuvable" severity failure;
        for frame in 0 to FRAME_COUNT - 1 loop
            assert status = open_ok report "Fichier RGB introuvable (dossier ModelSim incorrect)" severity failure;
            for pix in 0 to W*H-1 loop
                assert not endfile(rgb_file) report "Image RGB incomplete" severity failure;
                readline(rgb_file, ln);
                hread(ln, rgb_value);
                if frame = 0 then
                    write(ppm_line, to_integer(unsigned(rgb_value(23 downto 16))));
                    write(ppm_line, string'(" "));
                    write(ppm_line, to_integer(unsigned(rgb_value(15 downto 8))));
                    write(ppm_line, string'(" "));
                    write(ppm_line, to_integer(unsigned(rgb_value(7 downto 0))));
                    writeline(fppm, ppm_line);
                end if;
                wait until falling_edge(clk);
                rgb_in <= rgb_value;
                valid_in <= '1';
                if pix = 0 then frame_start <= '1';
                else frame_start <= '0'; end if;
            end loop;
            wait until falling_edge(clk);
            valid_in <= '0';
            frame_start <= '0';
            -- Une marge entre les trames pour vider le pipeline d'image.
            for j in 1 to 10 loop wait until falling_edge(clk); end loop;
        end loop;
        file_close(rgb_file);
        report "FIN ENVOI RGB : moyennes=" & integer'image(mean_events) &
               ", PCA=" & integer'image(pca_events);
        valid_in <= '0';
        frame_start <= '0';
        -- Laisser terminer PCA, IIR, FFT et BPM.
        for t in 0 to 1500000 loop
            wait until rising_edge(clk);
            if processing_done = '1' then
                wait until falling_edge(clk);
                exit;
            end if;
        end loop;
        wait for 1 ns;
        report "BILAN moyennes=" & integer'image(mean_events) &
               ", PCA=" & integer'image(pca_events) &
               ", PCA_last=" & integer'image(pca_last_events) &
               ", overflow=" & integer'image(overflow_events) &
               ", BPM_valid=" & integer'image(bpm_events) &
               ", done=" & integer'image(done_events);
        assert mean_events >= 512 report "Moins de 512 moyennes RGB" severity failure;
        assert pca_events = 512 report "Nombre de projections PCA incorrect" severity failure;
        assert pca_last_events = 1 report "Signal PCA last incorrect" severity failure;
        assert overflow_events = 0 report "Des echantillons PCA ont ete perdus" severity failure;
        assert done_events = 1 report "processing_done absent ou duplique" severity failure;

        -- Le calculateur BPM produit done meme lorsque le spectre ne
        -- contient aucun pic non nul dans les indices 3 a 10.
        -- Selon la video, l'absence de bpm_valid est normale.
        if peak_found = '1' then
            assert bpm_events = 1
                report "Pic present mais BPM_valid absent ou duplique"
                severity failure;
            report "RESULTAT : pic spectral detecte, BPM=" &
                   integer'image(to_integer(bpm_out)) &
                   ", indice=" & integer'image(to_integer(peak_bin_out))
                   severity note;
        else
            assert bpm_events = 0
                report "BPM_valid emis sans pic spectral valide"
                severity failure;
            report "RESULTAT : aucun pic valide sur la video"
                severity note;
        end if;

        report "SUCCES FONCTIONNEL : 14 BLOCS, 512 PCA, FIN BPM, ZERO OVERFLOW (DONNEES RGB FOURNIES)"
            severity note;
        finished <= true;
        wait;
    end process;
end architecture;

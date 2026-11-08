library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Top-level du traitement RGB -> PCA -> passe-bande -> FFT -> BPM.
-- Cible : Cyclone V SoC 5CSXFC6D6F31C6.
-- Le protocole ne garantit pas la prise en charge de fenetres PCA
-- consecutives pendant le traitement; surveiller input_overflow.
entity respiratory_pipeline_14blocks is
    generic (
        IMG_WIDTH       : positive := 640;
        IMG_HEIGHT      : positive := 480;
        COORD_BITS      : positive := 10;
        THRESHOLD_VALUE : integer := 100
    );
    port (
        clk             : in std_logic;
        rst             : in std_logic;
        rgb_in          : in std_logic_vector(23 downto 0);
        valid_in        : in std_logic;
        frame_start     : in std_logic;

        mean_r_out      : out std_logic_vector(7 downto 0);
        mean_g_out      : out std_logic_vector(7 downto 0);
        mean_b_out      : out std_logic_vector(7 downto 0);
        mean_valid_out  : out std_logic;
        sample_count_out : out unsigned(9 downto 0);
        buffer_full_out : out std_logic;

        pca_sample_out  : out signed(31 downto 0);
        pca_valid       : out std_logic;
        pca_last        : out std_logic;
        pca_done        : out std_logic;
        transfer_busy   : out std_logic;

        input_ready     : out std_logic;
        input_overflow  : out std_logic;
        processing_active : out std_logic;
        bpm_out         : out unsigned(7 downto 0);
        bpm_valid       : out std_logic;
        peak_found      : out std_logic;
        peak_bin_out    : out unsigned(8 downto 0);
        peak_mag_out    : out unsigned(31 downto 0);
        processing_done : out std_logic
    );
end entity;

architecture rtl of respiratory_pipeline_14blocks is
    signal s_pca_sample : signed(31 downto 0);
    signal s_pca_valid  : std_logic;
    signal s_pca_last   : std_logic;
    signal s_pca_done   : std_logic;
begin

    u_pipeline_11 : entity work.respiratory_pipeline_11blocks
        generic map (
            IMG_WIDTH       => IMG_WIDTH,
            IMG_HEIGHT      => IMG_HEIGHT,
            COORD_BITS      => COORD_BITS,
            THRESHOLD_VALUE => THRESHOLD_VALUE
        )
        port map (
            clk              => clk,
            rst              => rst,
            rgb_in           => rgb_in,
            valid_in         => valid_in,
            frame_start      => frame_start,
            mean_r_out       => mean_r_out,
            mean_g_out       => mean_g_out,
            mean_b_out       => mean_b_out,
            mean_valid_out   => mean_valid_out,
            sample_count_out => sample_count_out,
            buffer_full_out  => buffer_full_out,
            pca_sample_out   => s_pca_sample,
            pca_valid        => s_pca_valid,
            pca_last         => s_pca_last,
            pca_done         => s_pca_done,
            transfer_busy    => transfer_busy
        );

    pca_sample_out <= s_pca_sample;
    pca_valid      <= s_pca_valid;
    pca_last       <= s_pca_last;
    pca_done       <= s_pca_done;

    u_processing_12to14 : entity work.respiratory_processing_12to14
        port map (
            clk            => clk,
            rst            => rst,
            pca_sample_in  => s_pca_sample,
            pca_valid_in   => s_pca_valid,
            pca_last_in    => s_pca_last,
            input_ready    => input_ready,
            input_overflow => input_overflow,
            bpm_out        => bpm_out,
            bpm_valid      => bpm_valid,
            peak_found     => peak_found,
            peak_bin_out   => peak_bin_out,
            peak_mag_out   => peak_mag_out,
            done           => processing_done,
            active         => processing_active
        );
end architecture;

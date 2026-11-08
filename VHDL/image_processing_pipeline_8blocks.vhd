
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity image_processing_pipeline_8blocks is
    generic (
        IMG_WIDTH       : positive := 640;
        IMG_HEIGHT      : positive := 480;
        COORD_BITS      : positive := 10;
        THRESHOLD_VALUE : integer := 100
    );
    port (
        -- Horloge et reset
        clk : in std_logic;
        rst : in std_logic;

        -- Flux RGB original
        rgb_in      : in std_logic_vector(23 downto 0);
        valid_in    : in std_logic;
        frame_start : in std_logic;

        -- Sortie de traitement binaire
        binary_out : out std_logic_vector(7 downto 0);
        valid_out  : out std_logic;

        -- Coordonnees Region Detector
        xmin : out unsigned(COORD_BITS-1 downto 0);
        xmax : out unsigned(COORD_BITS-1 downto 0);
        ymin : out unsigned(COORD_BITS-1 downto 0);
        ymax : out unsigned(COORD_BITS-1 downto 0);

        region_valid : out std_logic;
        region_found : out std_logic;

        -- Coordonnees ROI Generator
        roi_xmin : out unsigned(COORD_BITS-1 downto 0);
        roi_xmax : out unsigned(COORD_BITS-1 downto 0);
        roi_ymin : out unsigned(COORD_BITS-1 downto 0);
        roi_ymax : out unsigned(COORD_BITS-1 downto 0);

        roi_valid : out std_logic;
        roi_found : out std_logic;

        -- Nouvelles sorties du bloc 8
        roi_rgb_out : out std_logic_vector(23 downto 0);
        roi_pixel_valid : out std_logic
    );
end entity;

architecture rtl of image_processing_pipeline_8blocks is

    -- Coordonnees internes de la region
    signal s_xmin : unsigned(COORD_BITS-1 downto 0);
    signal s_xmax : unsigned(COORD_BITS-1 downto 0);
    signal s_ymin : unsigned(COORD_BITS-1 downto 0);
    signal s_ymax : unsigned(COORD_BITS-1 downto 0);

    signal s_region_valid : std_logic;
    signal s_region_found : std_logic;

    -- Coordonnees internes de la ROI
    signal s_roi_xmin : unsigned(COORD_BITS-1 downto 0);
    signal s_roi_xmax : unsigned(COORD_BITS-1 downto 0);
    signal s_roi_ymin : unsigned(COORD_BITS-1 downto 0);
    signal s_roi_ymax : unsigned(COORD_BITS-1 downto 0);

    signal s_roi_valid : std_logic;
    signal s_roi_found : std_logic;

begin

    ------------------------------------------------
    -- BLOC GLOBAL 1 A 7
    -- Traitement RGB vers ROI
    ------------------------------------------------

    U_PIPELINE_7 : entity work.image_processing_pipeline
        generic map (
            IMG_WIDTH       => IMG_WIDTH,
            IMG_HEIGHT      => IMG_HEIGHT,
            THRESHOLD_VALUE => THRESHOLD_VALUE,
            COORD_BITS      => COORD_BITS
        )
        port map (
            clk      => clk,
            rst      => rst,
            valid_in => valid_in,
            rgb_in   => rgb_in,

            binary_out => binary_out,
            valid_out  => valid_out,

            xmin => s_xmin,
            xmax => s_xmax,
            ymin => s_ymin,
            ymax => s_ymax,

            region_valid => s_region_valid,
            region_found => s_region_found,

            roi_xmin => s_roi_xmin,
            roi_xmax => s_roi_xmax,
            roi_ymin => s_roi_ymin,
            roi_ymax => s_roi_ymax,

            roi_valid => s_roi_valid,
            roi_found => s_roi_found
        );

    ------------------------------------------------
    -- BLOC 8 : RGB ROI EXTRACTOR
    -- Utilise les RGB originaux
    ------------------------------------------------

    U_RGB_ROI : entity work.rgb_roi_extractor
        generic map (
            IMG_WIDTH  => IMG_WIDTH,
            IMG_HEIGHT => IMG_HEIGHT,
            COORD_BITS => COORD_BITS,
            OFFSET_X   => 3,
            OFFSET_Y   => 3
        )
        port map (
            clk => clk,
            rst => rst,

            rgb_in      => rgb_in,
            valid_in    => valid_in,
            frame_start => frame_start,

            roi_xmin => s_roi_xmin,
            roi_xmax => s_roi_xmax,
            roi_ymin => s_roi_ymin,
            roi_ymax => s_roi_ymax,

            roi_update => s_roi_valid,
            roi_found  => s_roi_found,

            rgb_out         => roi_rgb_out,
            roi_pixel_valid => roi_pixel_valid
        );

    ------------------------------------------------
    -- TRANSMISSION DES RESULTATS
    ------------------------------------------------

    xmin <= s_xmin;
    xmax <= s_xmax;
    ymin <= s_ymin;
    ymax <= s_ymax;

    region_valid <= s_region_valid;
    region_found <= s_region_found;

    roi_xmin <= s_roi_xmin;
    roi_xmax <= s_roi_xmax;
    roi_ymin <= s_roi_ymin;
    roi_ymax <= s_roi_ymax;

    roi_valid <= s_roi_valid;
    roi_found <= s_roi_found;

end architecture rtl;

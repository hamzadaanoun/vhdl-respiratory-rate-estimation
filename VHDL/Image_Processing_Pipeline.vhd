
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity image_processing_pipeline is
    generic (
        IMG_WIDTH       : positive := 640;
        IMG_HEIGHT      : positive := 480;
        THRESHOLD_VALUE : integer := 100;
        COORD_BITS      : positive := 10
    );
    port (
        clk      : in std_logic;
        rst      : in std_logic;
        valid_in : in std_logic;
        rgb_in   : in std_logic_vector(23 downto 0);

        binary_out : out std_logic_vector(7 downto 0);
        valid_out  : out std_logic;

        xmin : out unsigned(COORD_BITS-1 downto 0);
        xmax : out unsigned(COORD_BITS-1 downto 0);
        ymin : out unsigned(COORD_BITS-1 downto 0);
        ymax : out unsigned(COORD_BITS-1 downto 0);

        region_valid : out std_logic;
        region_found : out std_logic;

        roi_xmin : out unsigned(COORD_BITS-1 downto 0);
        roi_xmax : out unsigned(COORD_BITS-1 downto 0);
        roi_ymin : out unsigned(COORD_BITS-1 downto 0);
        roi_ymax : out unsigned(COORD_BITS-1 downto 0);

        roi_valid : out std_logic;
        roi_found : out std_logic
    );
end entity;

architecture rtl of image_processing_pipeline is

    constant REGION_W : positive := IMG_WIDTH - 6;
    constant REGION_H : positive := IMG_HEIGHT - 6;

    signal gray_data  : std_logic_vector(7 downto 0);
    signal gray_valid : std_logic;

    signal blur_data  : std_logic_vector(7 downto 0);
    signal blur_valid : std_logic;

    signal sobel_data  : std_logic_vector(7 downto 0);
    signal sobel_valid : std_logic;

    signal thresh_data  : std_logic_vector(7 downto 0);
    signal thresh_valid : std_logic;

    signal morph_data  : std_logic_vector(7 downto 0);
    signal morph_valid : std_logic;

    signal reg_xmin : unsigned(COORD_BITS-1 downto 0);
    signal reg_xmax : unsigned(COORD_BITS-1 downto 0);
    signal reg_ymin : unsigned(COORD_BITS-1 downto 0);
    signal reg_ymax : unsigned(COORD_BITS-1 downto 0);

    signal reg_valid : std_logic;
    signal reg_found : std_logic;

    signal roi_xmin_int : unsigned(COORD_BITS-1 downto 0);
    signal roi_xmax_int : unsigned(COORD_BITS-1 downto 0);
    signal roi_ymin_int : unsigned(COORD_BITS-1 downto 0);
    signal roi_ymax_int : unsigned(COORD_BITS-1 downto 0);

    signal skin_xmin, skin_xmax, skin_ymin, skin_ymax : unsigned(COORD_BITS-1 downto 0);
    signal skin_valid, skin_found : std_logic;
    signal roi_valid_int : std_logic;
    signal roi_found_int : std_logic;

    signal pixel_count : integer
        range 0 to REGION_W*REGION_H-1 := 0;

    signal morph_frame_start : std_logic;

begin

    --------------------------------------------------
    -- BLOC 1 : GRAYSCALE
    --------------------------------------------------

    U_GRAY : entity work.grayscale_pipeline
        port map (
            clk       => clk,
            rst       => rst,
            valid_in  => valid_in,
            r_in      => rgb_in(23 downto 16),
            g_in      => rgb_in(15 downto 8),
            b_in      => rgb_in(7 downto 0),
            gray_out  => gray_data,
            valid_out => gray_valid
        );

    --------------------------------------------------
    -- BLOC 2 : BOX BLUR
    --------------------------------------------------

    U_BLUR : entity work.box_blur_pipeline
        generic map (
            IMG_WIDTH  => IMG_WIDTH,
            IMG_HEIGHT => IMG_HEIGHT
        )
        port map (
            clk       => clk,
            rst       => rst,
            valid_in  => gray_valid,
            gray_in   => gray_data,
            blur_out  => blur_data,
            valid_out => blur_valid
        );

    --------------------------------------------------
    -- BLOC 3 : SOBEL
    --------------------------------------------------

    U_SOBEL : entity work.sobel_pipeline
        generic map (
            IMG_WIDTH  => IMG_WIDTH-2,
            IMG_HEIGHT => IMG_HEIGHT-2
        )
        port map (
            clk       => clk,
            rst       => rst,
            valid_in  => blur_valid,
            gray_in   => blur_data,
            edge_out  => sobel_data,
            valid_out => sobel_valid
        );

    --------------------------------------------------
    -- BLOC 4 : THRESHOLD
    --------------------------------------------------

    U_THRESHOLD : entity work.threshold_pipeline
        generic map (
            THRESHOLD_VALUE => THRESHOLD_VALUE
        )
        port map (
            clk        => clk,
            rst        => rst,
            valid_in   => sobel_valid,
            edge_in    => sobel_data,
            binary_out => thresh_data,
            valid_out  => thresh_valid
        );

    --------------------------------------------------
    -- BLOC 5 : MORPHOLOGY
    --------------------------------------------------

    U_MORPH : entity work.morphology_pipeline
        generic map (
            IMG_WIDTH  => IMG_WIDTH-4,
            IMG_HEIGHT => IMG_HEIGHT-4
        )
        port map (
            clk        => clk,
            rst        => rst,
            valid_in   => thresh_valid,
            binary_in  => thresh_data,
            binary_out => morph_data,
            valid_out  => morph_valid
        );

    --------------------------------------------------
    -- COMPTEUR DE PIXELS
    -- Generation de frame_start pour Region Detector
    --------------------------------------------------

    morph_frame_start <= '1'
        when pixel_count = 0 and morph_valid = '1'
        else '0';

    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                pixel_count <= 0;

            elsif morph_valid = '1' then

                if pixel_count = REGION_W*REGION_H-1 then
                    pixel_count <= 0;
                else
                    pixel_count <= pixel_count + 1;
                end if;

            end if;
        end if;
    end process;

    --------------------------------------------------
    -- BLOC 6 : REGION DETECTOR
    --------------------------------------------------

    U_REGION : entity work.region_detector
        generic map (
            IMG_WIDTH  => REGION_W,
            IMG_HEIGHT => REGION_H,
            COORD_BITS => COORD_BITS
        )
        port map (
            clk          => clk,
            rst          => rst,
            valid_in     => morph_valid,
            frame_start  => morph_frame_start,
            binary_in    => morph_data,

            xmin         => reg_xmin,
            xmax         => reg_xmax,
            ymin         => reg_ymin,
            ymax         => reg_ymax,

            region_valid => reg_valid,
            region_found => reg_found
        );

    --------------------------------------------------
    -- BLOC 7 : ROI GENERATOR
    --------------------------------------------------

    U_ROI : entity work.roi_generator
        generic map (
            COORD_BITS => COORD_BITS
        )
        port map (
            clk          => clk,
            rst          => rst,
            region_valid => reg_valid,
            region_found => reg_found,

            xmin         => reg_xmin,
            xmax         => reg_xmax,
            ymin         => reg_ymin,
            ymax         => reg_ymax,

            roi_xmin     => roi_xmin_int,
            roi_xmax     => roi_xmax_int,
            roi_ymin     => roi_ymin_int,
            roi_ymax     => roi_ymax_int,

            roi_valid    => roi_valid_int,
            roi_found    => roi_found_int
        );

    -- Branche de localisation RGB dynamique (experimentale).
    -- U_REGION et U_ROI historiques restent instancies pour comparaison.
    U_SKIN_TRACKER : entity work.skin_roi_tracker
      generic map (IMG_WIDTH => IMG_WIDTH, IMG_HEIGHT => IMG_HEIGHT,
                   COORD_BITS => COORD_BITS, OFFSET_X => 3, OFFSET_Y => 3)
      port map (clk => clk, rst => rst, valid_in => valid_in,
                rgb_in => rgb_in,
                xmin => skin_xmin, xmax => skin_xmax,
                ymin => skin_ymin, ymax => skin_ymax,
                roi_valid => skin_valid, roi_found => skin_found);

    --------------------------------------------------
    -- SORTIES DU PIPELINE
    --------------------------------------------------

    binary_out <= morph_data;
    valid_out  <= morph_valid;

    xmin <= reg_xmin;
    xmax <= reg_xmax;
    ymin <= reg_ymin;
    ymax <= reg_ymax;

    region_valid <= reg_valid;
    region_found <= reg_found;

    roi_xmin <= skin_xmin;
    roi_xmax <= skin_xmax;
    roi_ymin <= skin_ymin;
    roi_ymax <= skin_ymax;

    roi_valid <= skin_valid;
    roi_found <= skin_found;


    -- ===================================================================
    -- EXPORT ROI VHDL - SIMULATION SEULEMENT (ModelSim)
    -- Ne modifie ni le calcul ROI, ni les signaux de sortie.
    -- synthesis translate_off
    export_roi_csv : process(clk)
        file froi : text open write_mode is "07_roi_coordinates.csv";
        variable l : line;
        variable initialized : boolean := false;
        variable event_idx : natural := 0;
    begin
        if rising_edge(clk) then
            if not initialized then
                write(l, string'("event;time_ns;xmin;xmax;ymin;ymax;found"));
                writeline(froi, l);
                initialized := true;
            end if;
            if rst = '0' and skin_valid = '1' then
                write(l, event_idx);
                write(l, string'(";"));
                write(l, integer(now / 1 ns));
                write(l, string'(";"));
                write(l, to_integer(skin_xmin));
                write(l, string'(";"));
                write(l, to_integer(skin_xmax));
                write(l, string'(";"));
                write(l, to_integer(skin_ymin));
                write(l, string'(";"));
                write(l, to_integer(skin_ymax));
                write(l, string'(";"));
                write(l, std_logic'image(skin_found));
                writeline(froi, l);
                event_idx := event_idx + 1;
            end if;
        end if;
    end process;
    -- synthesis translate_on
    -- ===================================================================


    -- =====================================================================
    -- IMAGES INTERMEDIAIRES : export direct des signaux VHDL (1ere trame)
    -- PGM ASCII P2, lisibles et convertibles avec FFmpeg.
    -- synthesis translate_off
    export_images_pipeline : process(clk)
        file fgray   : text open write_mode is "02_grayscale.pgm";
        file fblur   : text open write_mode is "03_box_blur.pgm";
        file fsobel  : text open write_mode is "04_sobel.pgm";
        file fthresh : text open write_mode is "05_threshold.pgm";
        file fmorph  : text open write_mode is "06_morphology.pgm";
        variable ln : line;
        variable initialized : boolean := false;
        variable ng, nb, ns, nt, nm : natural := 0;
    begin
        if rising_edge(clk) then
            if not initialized then
                write(ln, string'("P2")); writeline(fgray,ln);
                write(ln, IMG_WIDTH); write(ln,string'(" ")); write(ln,IMG_HEIGHT); writeline(fgray,ln);
                write(ln,255); writeline(fgray,ln);
                write(ln, string'("P2")); writeline(fblur,ln);
                write(ln, IMG_WIDTH-2); write(ln,string'(" ")); write(ln,IMG_HEIGHT-2); writeline(fblur,ln);
                write(ln,255); writeline(fblur,ln);
                write(ln, string'("P2")); writeline(fsobel,ln);
                write(ln, IMG_WIDTH-4); write(ln,string'(" ")); write(ln,IMG_HEIGHT-4); writeline(fsobel,ln);
                write(ln,255); writeline(fsobel,ln);
                write(ln, string'("P2")); writeline(fthresh,ln);
                write(ln, IMG_WIDTH-4); write(ln,string'(" ")); write(ln,IMG_HEIGHT-4); writeline(fthresh,ln);
                write(ln,255); writeline(fthresh,ln);
                write(ln, string'("P2")); writeline(fmorph,ln);
                write(ln, IMG_WIDTH-6); write(ln,string'(" ")); write(ln,IMG_HEIGHT-6); writeline(fmorph,ln);
                write(ln,255); writeline(fmorph,ln);
                initialized := true;
            end if;
            if rst = '0' then
                if gray_valid = '1' and ng < IMG_WIDTH*IMG_HEIGHT then
                    write(ln,to_integer(unsigned(gray_data))); writeline(fgray,ln); ng := ng+1;
                end if;
                if blur_valid = '1' and nb < (IMG_WIDTH-2)*(IMG_HEIGHT-2) then
                    write(ln,to_integer(unsigned(blur_data))); writeline(fblur,ln); nb := nb+1;
                end if;
                if sobel_valid = '1' and ns < (IMG_WIDTH-4)*(IMG_HEIGHT-4) then
                    write(ln,to_integer(unsigned(sobel_data))); writeline(fsobel,ln); ns := ns+1;
                end if;
                if thresh_valid = '1' and nt < (IMG_WIDTH-4)*(IMG_HEIGHT-4) then
                    write(ln,to_integer(unsigned(thresh_data))); writeline(fthresh,ln); nt := nt+1;
                end if;
                if morph_valid = '1' and nm < (IMG_WIDTH-6)*(IMG_HEIGHT-6) then
                    write(ln,to_integer(unsigned(morph_data))); writeline(fmorph,ln); nm := nm+1;
                end if;
            end if;
        end if;
    end process;
    -- synthesis translate_on
    -- =====================================================================

end architecture rtl;

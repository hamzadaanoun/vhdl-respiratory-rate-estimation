
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity image_processing_pipeline_9blocks is
    generic (
        IMG_WIDTH       : positive := 640;
        IMG_HEIGHT      : positive := 480;
        COORD_BITS      : positive := 10;
        THRESHOLD_VALUE : integer := 100
    );
    port (
        clk : in std_logic;
        rst : in std_logic;

        -- Flux RGB d'origine
        rgb_in      : in std_logic_vector(23 downto 0);
        valid_in    : in std_logic;
        frame_start : in std_logic;

        -- Sortie binaire des blocs 1 a 7
        binary_out : out std_logic_vector(7 downto 0);
        valid_out  : out std_logic;

        -- Region Detector
        xmin, xmax : out unsigned(COORD_BITS-1 downto 0);
        ymin, ymax : out unsigned(COORD_BITS-1 downto 0);
        region_valid : out std_logic;
        region_found : out std_logic;

        -- ROI Generator
        roi_xmin, roi_xmax : out unsigned(COORD_BITS-1 downto 0);
        roi_ymin, roi_ymax : out unsigned(COORD_BITS-1 downto 0);
        roi_valid : out std_logic;
        roi_found : out std_logic;

        -- Bloc 8 : pixels du front
        roi_rgb_out : out std_logic_vector(23 downto 0);
        roi_pixel_valid : out std_logic;

        -- Bloc 9 : moyennes RGB
        mean_r : out std_logic_vector(7 downto 0);
        mean_g : out std_logic_vector(7 downto 0);
        mean_b : out std_logic_vector(7 downto 0);

        mean_pixel_count : out unsigned(31 downto 0);
        mean_valid : out std_logic;
        roi_has_pixels : out std_logic;
        mean_busy : out std_logic
    );
end entity;

architecture rtl of image_processing_pipeline_9blocks is

    constant FRAME_PIXELS : positive :=
        IMG_WIDTH * IMG_HEIGHT;

    signal s_roi_rgb : std_logic_vector(23 downto 0);
    signal s_roi_pixel_valid : std_logic;

    signal pixel_position : integer range
        0 to FRAME_PIXELS-1 := 0;

    -- Fin de trame retardee d'un cycle
    -- pour s'aligner avec la sortie du bloc 8.
    signal frame_end_delayed : std_logic := '0';

begin

    --------------------------------------------------
    -- BLOCS 1 A 8
    --------------------------------------------------

    U_PIPELINE_8 :
        entity work.image_processing_pipeline_8blocks

        generic map (
            IMG_WIDTH       => IMG_WIDTH,
            IMG_HEIGHT      => IMG_HEIGHT,
            COORD_BITS      => COORD_BITS,
            THRESHOLD_VALUE => THRESHOLD_VALUE
        )

        port map (
            clk => clk,
            rst => rst,

            rgb_in      => rgb_in,
            valid_in    => valid_in,
            frame_start => frame_start,

            binary_out => binary_out,
            valid_out  => valid_out,

            xmin => xmin,
            xmax => xmax,
            ymin => ymin,
            ymax => ymax,

            region_valid => region_valid,
            region_found => region_found,

            roi_xmin => roi_xmin,
            roi_xmax => roi_xmax,
            roi_ymin => roi_ymin,
            roi_ymax => roi_ymax,

            roi_valid => roi_valid,
            roi_found => roi_found,

            roi_rgb_out => s_roi_rgb,
            roi_pixel_valid => s_roi_pixel_valid
        );

    roi_rgb_out <= s_roi_rgb;
    roi_pixel_valid <= s_roi_pixel_valid;

    --------------------------------------------------
    -- DETECTION DE LA FIN DE TRAME RGB
    --------------------------------------------------

    process(clk)
        variable current_position : integer;
    begin
        if rising_edge(clk) then

            if rst = '1' then
                pixel_position <= 0;
                frame_end_delayed <= '0';

            else
                frame_end_delayed <= '0';

                if valid_in = '1' then

                    if frame_start = '1' then
                        current_position := 0;
                    else
                        current_position := pixel_position;
                    end if;

                    if current_position = FRAME_PIXELS-1 then

                        -- Dernier pixel d'entree.
                        -- Le bloc 8 enregistre sa sortie
                        -- sur ce meme front montant.
                        frame_end_delayed <= '1';

                        pixel_position <= 0;

                    else
                        pixel_position <= current_position + 1;
                    end if;

                end if;
            end if;
        end if;
    end process;

    --------------------------------------------------
    -- BLOC 9 : RGB MEAN CALCULATOR
    --------------------------------------------------

    U_RGB_MEAN :
        entity work.rgb_mean_calculator

        port map (
            clk => clk,
            rst => rst,

            rgb_in => s_roi_rgb,
            roi_pixel_valid => s_roi_pixel_valid,

            frame_end => frame_end_delayed,

            mean_r => mean_r,
            mean_g => mean_g,
            mean_b => mean_b,

            pixel_count => mean_pixel_count,
            mean_valid => mean_valid,
            roi_has_pixels => roi_has_pixels,
            busy => mean_busy
        );

end architecture rtl;


library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity rgb_roi_extractor is
    generic (
        IMG_WIDTH  : positive := 640;
        IMG_HEIGHT : positive := 480;
        COORD_BITS : positive := 10;

        -- Compensation spatiale des 3 filtres 3x3.
        -- A confirmer selon l'alignement du pipeline.
        OFFSET_X : natural := 3;
        OFFSET_Y : natural := 3
    );
    port (
        clk : in std_logic;
        rst : in std_logic;

        -- Pixels RGB originaux
        rgb_in      : in std_logic_vector(23 downto 0);
        valid_in    : in std_logic;
        frame_start : in std_logic;

        -- ROI fournie par le bloc 7
        roi_xmin : in unsigned(COORD_BITS-1 downto 0);
        roi_xmax : in unsigned(COORD_BITS-1 downto 0);
        roi_ymin : in unsigned(COORD_BITS-1 downto 0);
        roi_ymax : in unsigned(COORD_BITS-1 downto 0);

        roi_update : in std_logic;
        roi_found  : in std_logic;

        -- Sorties
        rgb_out : out std_logic_vector(23 downto 0);
        roi_pixel_valid : out std_logic
    );
end entity rgb_roi_extractor;

architecture rtl of rgb_roi_extractor is

    -- Compteurs de position dans l'image RGB
    signal x_count : integer range 0 to IMG_WIDTH-1 := 0;
    signal y_count : integer range 0 to IMG_HEIGHT-1 := 0;

    -- Coordonnees ROI memorisees
    signal pending_xmin : unsigned(COORD_BITS-1 downto 0)
        := (others => '0');
    signal pending_xmax : unsigned(COORD_BITS-1 downto 0)
        := (others => '0');
    signal pending_ymin : unsigned(COORD_BITS-1 downto 0)
        := (others => '0');
    signal pending_ymax : unsigned(COORD_BITS-1 downto 0)
        := (others => '0');

    signal pending_found : std_logic := '0';

    -- ROI active pour la trame courante
    signal active_xmin : unsigned(COORD_BITS-1 downto 0)
        := (others => '0');
    signal active_xmax : unsigned(COORD_BITS-1 downto 0)
        := (others => '0');
    signal active_ymin : unsigned(COORD_BITS-1 downto 0)
        := (others => '0');
    signal active_ymax : unsigned(COORD_BITS-1 downto 0)
        := (others => '0');

    signal active_found : std_logic := '0';

begin

    process(clk)

        variable px : integer;
        variable py : integer;

        variable xmin_v : integer;
        variable xmax_v : integer;
        variable ymin_v : integer;
        variable ymax_v : integer;

        variable use_roi : std_logic;

    begin
        if rising_edge(clk) then

            if rst = '1' then

                x_count <= 0;
                y_count <= 0;

                pending_xmin <= (others => '0');
                pending_xmax <= (others => '0');
                pending_ymin <= (others => '0');
                pending_ymax <= (others => '0');
                pending_found <= '0';

                active_xmin <= (others => '0');
                active_xmax <= (others => '0');
                active_ymin <= (others => '0');
                active_ymax <= (others => '0');
                active_ymax <= (others => '0');
                active_found <= '0';

                rgb_out <= (others => '0');
                roi_pixel_valid <= '0';

            else

                -- Sorties inactives par defaut
                rgb_out <= (others => '0');
                roi_pixel_valid <= '0';

                --------------------------------------
                -- Memorisation de la derniere ROI
                --------------------------------------
                if roi_update = '1' then

                    pending_xmin <= roi_xmin;
                    pending_xmax <= roi_xmax;
                    pending_ymin <= roi_ymin;
                    pending_ymax <= roi_ymax;
                    pending_found <= roi_found;

                end if;

                --------------------------------------
                -- Lecture du flux RGB
                --------------------------------------
                if valid_in = '1' then

                    -- Debut de nouvelle image
                    if frame_start = '1' then
                        px := 0;
                        py := 0;
                    else
                        px := x_count;
                        py := y_count;
                    end if;

                    ----------------------------------
                    -- Charger la ROI active
                    ----------------------------------
                    if frame_start = '1' then

                        -- Gestion d'une ROI mise a jour
                        -- au meme cycle que frame_start
                        if roi_update = '1' then

                            xmin_v := to_integer(roi_xmin);
                            xmax_v := to_integer(roi_xmax);
                            ymin_v := to_integer(roi_ymin);
                            ymax_v := to_integer(roi_ymax);
                            use_roi := roi_found;

                            active_xmin <= roi_xmin;
                            active_xmax <= roi_xmax;
                            active_ymin <= roi_ymin;
                            active_ymax <= roi_ymax;
                            active_found <= roi_found;

                        else

                            xmin_v := to_integer(pending_xmin);
                            xmax_v := to_integer(pending_xmax);
                            ymin_v := to_integer(pending_ymin);
                            ymax_v := to_integer(pending_ymax);
                            use_roi := pending_found;

                            active_xmin <= pending_xmin;
                            active_xmax <= pending_xmax;
                            active_ymin <= pending_ymin;
                            active_ymax <= pending_ymax;
                            active_found <= pending_found;

                        end if;

                    else

                        xmin_v := to_integer(active_xmin);
                        xmax_v := to_integer(active_xmax);
                        ymin_v := to_integer(active_ymin);
                        ymax_v := to_integer(active_ymax);
                        use_roi := active_found;

                    end if;

                    ----------------------------------
                    -- Selection des pixels de la ROI
                    ----------------------------------
                    if use_roi = '1' then

                        if (xmin_v <= xmax_v) and
                           (ymin_v <= ymax_v) then

                            if (px >= xmin_v + OFFSET_X) and
                               (px <= xmax_v + OFFSET_X) and
                               (py >= ymin_v + OFFSET_Y) and
                               (py <= ymax_v + OFFSET_Y) then

                                rgb_out <= rgb_in;
                                roi_pixel_valid <= '1';

                            end if;

                        end if;
                    end if;

                    ----------------------------------
                    -- Mise a jour des compteurs
                    ----------------------------------
                    if px = IMG_WIDTH - 1 then

                        x_count <= 0;

                        if py = IMG_HEIGHT - 1 then
                            y_count <= 0;
                        else
                            y_count <= py + 1;
                        end if;

                    else

                        x_count <= px + 1;
                        y_count <= py;

                    end if;

                end if;

            end if;
        end if;
    end process;

end architecture rtl;

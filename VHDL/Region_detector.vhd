
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity region_detector is
    generic (
        IMG_WIDTH  : positive := 634;
        IMG_HEIGHT : positive := 474;
        COORD_BITS : positive := 10
    );
    port (
        clk          : in  std_logic;
        rst          : in  std_logic;

        valid_in     : in  std_logic;
        frame_start  : in  std_logic;
        binary_in    : in  std_logic_vector(7 downto 0);

        xmin         : out unsigned(COORD_BITS-1 downto 0);
        xmax         : out unsigned(COORD_BITS-1 downto 0);
        ymin         : out unsigned(COORD_BITS-1 downto 0);
        ymax         : out unsigned(COORD_BITS-1 downto 0);

        region_valid : out std_logic;
        region_found : out std_logic
    );
end entity;

architecture rtl of region_detector is

    signal x_count : integer range 0 to IMG_WIDTH-1 := 0;
    signal y_count : integer range 0 to IMG_HEIGHT-1 := 0;

    signal min_x : integer range 0 to IMG_WIDTH-1 := 0;
    signal max_x : integer range 0 to IMG_WIDTH-1 := 0;
    signal min_y : integer range 0 to IMG_HEIGHT-1 := 0;
    signal max_y : integer range 0 to IMG_HEIGHT-1 := 0;

    signal found : std_logic := '0';

    signal xmin_reg : unsigned(COORD_BITS-1 downto 0)
                      := (others => '0');
    signal xmax_reg : unsigned(COORD_BITS-1 downto 0)
                      := (others => '0');
    signal ymin_reg : unsigned(COORD_BITS-1 downto 0)
                      := (others => '0');
    signal ymax_reg : unsigned(COORD_BITS-1 downto 0)
                      := (others => '0');

    signal output_valid : std_logic := '0';
    signal output_found : std_logic := '0';

begin

    xmin <= xmin_reg;
    xmax <= xmax_reg;
    ymin <= ymin_reg;
    ymax <= ymax_reg;

    region_valid <= output_valid;
    region_found <= output_found;

    process(clk)
        variable x_pos : integer;
        variable y_pos : integer;
        variable vxmin : integer;
        variable vxmax : integer;
        variable vymin : integer;
        variable vymax : integer;
        variable vfound : std_logic;
    begin
        if rising_edge(clk) then

            if rst = '1' then
                x_count <= 0;
                y_count <= 0;

                min_x <= 0;
                max_x <= 0;
                min_y <= 0;
                max_y <= 0;
                found <= '0';

                xmin_reg <= (others => '0');
                xmax_reg <= (others => '0');
                ymin_reg <= (others => '0');
                ymax_reg <= (others => '0');

                output_valid <= '0';
                output_found <= '0';

            else
                output_valid <= '0';

                if valid_in = '1' then

                    -- Le premier pixel porte frame_start.
                    if frame_start = '1' then
                        x_pos := 0;
                        y_pos := 0;
                        vxmin := 0;
                        vxmax := 0;
                        vymin := 0;
                        vymax := 0;
                        vfound := '0';
                    else
                        x_pos := x_count;
                        y_pos := y_count;
                        vxmin := min_x;
                        vxmax := max_x;
                        vymin := min_y;
                        vymax := max_y;
                        vfound := found;
                    end if;

                    -- Detection des pixels blancs.
                    if binary_in /= x"00" then

                        if vfound = '0' then
                            vxmin := x_pos;
                            vxmax := x_pos;
                            vymin := y_pos;
                            vymax := y_pos;
                            vfound := '1';
                        else
                            if x_pos < vxmin then
                                vxmin := x_pos;
                            end if;

                            if x_pos > vxmax then
                                vxmax := x_pos;
                            end if;

                            if y_pos < vymin then
                                vymin := y_pos;
                            end if;

                            if y_pos > vymax then
                                vymax := y_pos;
                            end if;
                        end if;
                    end if;

                    -- Memorisation des limites courantes.
                    min_x <= vxmin;
                    max_x <= vxmax;
                    min_y <= vymin;
                    max_y <= vymax;
                    found <= vfound;

                    -- Dernier pixel de l'image.
                    if x_pos = IMG_WIDTH-1 and
                       y_pos = IMG_HEIGHT-1 then

                        xmin_reg <= to_unsigned(vxmin, COORD_BITS);
                        xmax_reg <= to_unsigned(vxmax, COORD_BITS);
                        ymin_reg <= to_unsigned(vymin, COORD_BITS);
                        ymax_reg <= to_unsigned(vymax, COORD_BITS);

                        output_found <= vfound;
                        output_valid <= '1';

                        x_count <= 0;
                        y_count <= 0;

                        found <= '0';

                    elsif x_pos = IMG_WIDTH-1 then

                        x_count <= 0;
                        y_count <= y_pos + 1;

                    else

                        x_count <= x_pos + 1;
                        y_count <= y_pos;

                    end if;

                end if;
            end if;
        end if;
    end process;

end architecture rtl;

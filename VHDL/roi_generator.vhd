
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity roi_generator is
    generic (
        COORD_BITS : positive := 10
    );
    port (
        clk : in std_logic;
        rst : in std_logic;

        region_valid : in std_logic;
        region_found : in std_logic;

        xmin : in unsigned(COORD_BITS-1 downto 0);
        xmax : in unsigned(COORD_BITS-1 downto 0);
        ymin : in unsigned(COORD_BITS-1 downto 0);
        ymax : in unsigned(COORD_BITS-1 downto 0);

        roi_xmin : out unsigned(COORD_BITS-1 downto 0);
        roi_xmax : out unsigned(COORD_BITS-1 downto 0);
        roi_ymin : out unsigned(COORD_BITS-1 downto 0);
        roi_ymax : out unsigned(COORD_BITS-1 downto 0);

        roi_valid : out std_logic;
        roi_found : out std_logic
    );
end entity;

architecture rtl of roi_generator is

    -- Cette version est dimensionnee pour
    -- COORD_BITS = 10, configuration actuelle.

    constant MAX_COORD : integer := 2**COORD_BITS - 1;

    function div5_fast(
        n : unsigned(10 downto 0)
    ) return unsigned is
        variable a : unsigned(25 downto 0);
        variable p : unsigned(25 downto 0);
    begin
        a := resize(n, 26);

        p := shift_left(a, 11)
           + shift_left(a, 10)
           + shift_left(a, 7)
           + shift_left(a, 6)
           + shift_left(a, 3)
           + shift_left(a, 2)
           + a;

        return p(24 downto 14);
    end function;

    --------------------------------------------------
    -- ETAGE 1 : COORDONNEES ET DIMENSIONS
    --------------------------------------------------

    signal s1_valid : std_logic := '0';
    signal s1_found : std_logic := '0';

    signal s1_x0, s1_y0 : integer range 0 to MAX_COORD := 0;
    signal s1_x1, s1_y1 : integer range 0 to MAX_COORD := 0;

    signal s1_width  : integer range 0 to MAX_COORD+1 := 0;
    signal s1_height : integer range 0 to MAX_COORD+1 := 0;

    --------------------------------------------------
    -- ETAGE 2 : COORDONNEES CANDIDATES
    --------------------------------------------------

    signal s2_valid : std_logic := '0';
    signal s2_found : std_logic := '0';

    signal s2_x1, s2_y1 : integer range 0 to MAX_COORD := 0;

    signal s2_rx0 : integer range 0 to 2*MAX_COORD+2 := 0;
    signal s2_rx1 : integer range 0 to 2*MAX_COORD+2 := 0;
    signal s2_ry0 : integer range 0 to 2*MAX_COORD+2 := 0;
    signal s2_ry1 : integer range 0 to 2*MAX_COORD+2 := 0;

    --------------------------------------------------
    -- ETAGE 3 : SORTIES
    --------------------------------------------------

    signal rxmin_reg : unsigned(COORD_BITS-1 downto 0)
                       := (others => '0');
    signal rxmax_reg : unsigned(COORD_BITS-1 downto 0)
                       := (others => '0');
    signal rymin_reg : unsigned(COORD_BITS-1 downto 0)
                       := (others => '0');
    signal rymax_reg : unsigned(COORD_BITS-1 downto 0)
                       := (others => '0');

    signal valid_reg : std_logic := '0';
    signal found_reg : std_logic := '0';

begin

    assert COORD_BITS = 10
        report "Cette version exige COORD_BITS=10"
        severity failure;

    roi_xmin <= rxmin_reg;
    roi_xmax <= rxmax_reg;
    roi_ymin <= rymin_reg;
    roi_ymax <= rymax_reg;

    roi_valid <= valid_reg;
    roi_found <= found_reg;

    --------------------------------------------------
    -- ETAGE 1
    --------------------------------------------------

    process(clk)
        variable x0, x1 : integer;
        variable y0, y1 : integer;
    begin
        if rising_edge(clk) then

            if rst = '1' then
                s1_valid <= '0';
                s1_found <= '0';
                s1_x0 <= 0;
                s1_x1 <= 0;
                s1_y0 <= 0;
                s1_y1 <= 0;
                s1_width <= 0;
                s1_height <= 0;

            else
                s1_valid <= region_valid;
                s1_found <= '0';

                if region_valid = '1' then

                    x0 := to_integer(xmin);
                    x1 := to_integer(xmax);
                    y0 := to_integer(ymin);
                    y1 := to_integer(ymax);

                    s1_x0 <= x0;
                    s1_x1 <= x1;
                    s1_y0 <= y0;
                    s1_y1 <= y1;

                    if region_found = '1' and
                       x1 >= x0 and y1 >= y0 then

                        s1_width <= x1 - x0 + 1;
                        s1_height <= y1 - y0 + 1;
                        s1_found <= '1';

                    else
                        s1_width <= 0;
                        s1_height <= 0;
                    end if;

                end if;
            end if;
        end if;
    end process;

    --------------------------------------------------
    -- ETAGE 2
    --------------------------------------------------

    process(clk)
        variable scaled3 : integer;
        variable scaled7 : integer;
        variable q3 : integer;
        variable q7 : integer;
    begin
        if rising_edge(clk) then

            if rst = '1' then
                s2_valid <= '0';
                s2_found <= '0';

                s2_x1 <= 0;
                s2_y1 <= 0;
                s2_rx0 <= 0;
                s2_rx1 <= 0;
                s2_ry0 <= 0;
                s2_ry1 <= 0;

            else

                s2_valid <= s1_valid;
                s2_found <= '0';

                if s1_valid = '1' then

                    s2_x1 <= s1_x1;
                    s2_y1 <= s1_y1;

                    s2_rx0 <= 0;
                    s2_rx1 <= 0;
                    s2_ry0 <= 0;
                    s2_ry1 <= 0;

                    if s1_found = '1' and
                       s1_width >= 8 and
                       s1_height >= 10 then

                        s2_found <= '1';

                        -- Coordonnees horizontales
                        s2_rx0 <= s1_x0 +
                                  s1_width / 4;

                        s2_rx1 <= s1_x0 +
                                  (3*s1_width)/4 - 1;

                        -- Coordonnees verticales
                        scaled3 := (3*s1_height)/4;
                        scaled7 := (7*s1_height)/4;

                        q3 := to_integer(
                            div5_fast(
                                to_unsigned(scaled3, 11)
                            )
                        );

                        q7 := to_integer(
                            div5_fast(
                                to_unsigned(scaled7, 11)
                            )
                        );

                        s2_ry0 <= s1_y0 + q3;
                        s2_ry1 <= s1_y0 + q7 - 1;

                    end if;
                end if;
            end if;
        end if;
    end process;

    --------------------------------------------------
    -- ETAGE 3
    --------------------------------------------------

    process(clk)
    begin
        if rising_edge(clk) then

            if rst = '1' then

                valid_reg <= '0';
                found_reg <= '0';

                rxmin_reg <= (others => '0');
                rxmax_reg <= (others => '0');
                rymin_reg <= (others => '0');
                rymax_reg <= (others => '0');

            else

                valid_reg <= s2_valid;

                if s2_valid = '1' then

                    found_reg <= '0';

                    rxmin_reg <= (others => '0');
                    rxmax_reg <= (others => '0');
                    rymin_reg <= (others => '0');
                    rymax_reg <= (others => '0');

                    if s2_found = '1' and
                       s2_rx0 <= s2_rx1 and
                       s2_ry0 <= s2_ry1 and
                       s2_rx1 <= s2_x1 and
                       s2_ry1 <= s2_y1 then

                        rxmin_reg <= to_unsigned(
                            s2_rx0, COORD_BITS);

                        rxmax_reg <= to_unsigned(
                            s2_rx1, COORD_BITS);

                        rymin_reg <= to_unsigned(
                            s2_ry0, COORD_BITS);

                        rymax_reg <= to_unsigned(
                            s2_ry1, COORD_BITS);

                        found_reg <= '1';

                    end if;
                end if;
            end if;
        end if;
    end process;

end architecture rtl;

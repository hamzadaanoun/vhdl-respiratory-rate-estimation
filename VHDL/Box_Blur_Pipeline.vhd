
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity box_blur_pipeline is
    generic (
        IMG_WIDTH  : positive := 640;
        IMG_HEIGHT : positive := 480
    );
    port (
        clk       : in  std_logic;
        rst       : in  std_logic;
        valid_in  : in  std_logic;

        gray_in   : in  std_logic_vector(7 downto 0);

        blur_out  : out std_logic_vector(7 downto 0);
        valid_out : out std_logic
    );
end entity;

architecture rtl of box_blur_pipeline is

    -- Memoire de deux lignes
    type line_type is array (0 to IMG_WIDTH-1)
        of unsigned(7 downto 0);

    signal line1 : line_type :=
        (others => (others => '0'));

    signal line2 : line_type :=
        (others => (others => '0'));

    -- Fenetre 3x3
    signal p00, p01, p02 : unsigned(7 downto 0)
        := (others => '0');

    signal p10, p11, p12 : unsigned(7 downto 0)
        := (others => '0');

    signal p20, p21, p22 : unsigned(7 downto 0)
        := (others => '0');

    -- Position du pixel
    signal col : integer range 0 to IMG_WIDTH-1 := 0;
    signal row : integer range 0 to IMG_HEIGHT-1 := 0;

    -- Etage de somme
    signal sum_reg : unsigned(11 downto 0)
        := (others => '0');

    -- Sortie
    signal blur_reg : unsigned(7 downto 0)
        := (others => '0');

    signal window_valid : std_logic := '0';
    signal sum_valid : std_logic := '0';
    signal out_valid : std_logic := '0';

begin

    blur_out <= std_logic_vector(blur_reg);
    valid_out <= out_valid;

    -- =======================================
    -- ETAGE 1 : LINE BUFFERS ET FENETRE
    -- =======================================

    process(clk)
    begin
        if rising_edge(clk) then

            if rst = '1' then

                col <= 0;
                row <= 0;
                window_valid <= '0';

                p00 <= (others => '0');
                p01 <= (others => '0');
                p02 <= (others => '0');

                p10 <= (others => '0');
                p11 <= (others => '0');
                p12 <= (others => '0');

                p20 <= (others => '0');
                p21 <= (others => '0');
                p22 <= (others => '0');

            else
                window_valid <= '0';

                if valid_in = '1' then

                    -- Ligne la plus ancienne
                    p00 <= p01;
                    p01 <= p02;
                    p02 <= line2(col);

                    -- Ligne precedente
                    p10 <= p11;
                    p11 <= p12;
                    p12 <= line1(col);

                    -- Ligne courante
                    p20 <= p21;
                    p21 <= p22;
                    p22 <= unsigned(gray_in);

                    -- Decalage des lignes
                    line2(col) <= line1(col);
                    line1(col) <= unsigned(gray_in);

                    -- Fenetre complete
                    if row >= 2 and col >= 2 then
                        window_valid <= '1';
                    end if;

                    -- Compteurs image
                    if col = IMG_WIDTH-1 then
                        col <= 0;

                        if row = IMG_HEIGHT-1 then
                            row <= 0;
                        else
                            row <= row + 1;
                        end if;
                    else
                        col <= col + 1;
                    end if;

                end if;
            end if;
        end if;
    end process;

    -- =======================================
    -- ETAGE 2 : SOMME DES 9 PIXELS
    -- =======================================

    process(clk)
    begin
        if rising_edge(clk) then

            if rst = '1' then
                sum_reg <= (others => '0');
                sum_valid <= '0';

            else
                sum_reg <=
                    resize(p00, 12) +
                    resize(p01, 12) +
                    resize(p02, 12) +
                    resize(p10, 12) +
                    resize(p11, 12) +
                    resize(p12, 12) +
                    resize(p20, 12) +
                    resize(p21, 12) +
                    resize(p22, 12);

                sum_valid <= window_valid;
            end if;
        end if;
    end process;

    -- =======================================
    -- ETAGE 3 : MOYENNE / 9
    -- =======================================

    process(clk)
        variable moyenne : integer;
    begin
        if rising_edge(clk) then

            if rst = '1' then
                blur_reg <= (others => '0');
                out_valid <= '0';

            else

                moyenne := to_integer(sum_reg) / 9;

                blur_reg <= to_unsigned(moyenne, 8);
                out_valid <= sum_valid;

            end if;
        end if;
    end process;

end architecture;

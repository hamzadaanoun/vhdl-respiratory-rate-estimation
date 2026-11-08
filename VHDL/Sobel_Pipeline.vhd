
-- ====================================================
-- PFE : Surveillance respiratoire sans contact
-- FPGA : DE10-Standard / Cyclone V SoC
-- MODULE : sobel_pipeline
-- DESCRIPTION :
--   Filtre Sobel 3x3 en flux de pixels
--   Deux Line Buffers et trois etages pipeline
--
-- Entree  : pixel 8 bits, valid_in
-- Sortie  : contour 8 bits, valid_out
-- ====================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sobel_pipeline is
    generic (
        IMG_WIDTH  : positive := 640;
        IMG_HEIGHT : positive := 480
    );
    port (
        clk       : in  std_logic;
        rst       : in  std_logic;
        valid_in  : in  std_logic;

        gray_in   : in  std_logic_vector(7 downto 0);

        edge_out  : out std_logic_vector(7 downto 0);
        valid_out : out std_logic
    );
end entity sobel_pipeline;

architecture rtl of sobel_pipeline is

    -- Deux lignes stockees en memoire
    type line_type is array (0 to IMG_WIDTH-1)
        of unsigned(7 downto 0);

    signal line1 : line_type :=
        (others => (others => '0'));

    signal line2 : line_type :=
        (others => (others => '0'));

    -- Registres de la fenetre 3x3
    signal p00, p01, p02 : unsigned(7 downto 0)
        := (others => '0');

    signal p10, p11, p12 : unsigned(7 downto 0)
        := (others => '0');

    signal p20, p21, p22 : unsigned(7 downto 0)
        := (others => '0');

    -- Compteurs de position
    signal col : integer range 0 to IMG_WIDTH-1 := 0;
    signal row : integer range 0 to IMG_HEIGHT-1 := 0;

    -- Gradients signes sur 12 bits
    -- Plage theorique : -1020 a +1020
    signal gx_reg : signed(11 downto 0)
        := (others => '0');

    signal gy_reg : signed(11 downto 0)
        := (others => '0');

    -- Resultat final
    signal edge_reg : unsigned(7 downto 0)
        := (others => '0');

    -- Validite du pipeline
    signal window_valid : std_logic := '0';
    signal gradient_valid : std_logic := '0';
    signal output_valid : std_logic := '0';

begin

    edge_out  <= std_logic_vector(edge_reg);
    valid_out <= output_valid;

    -- =================================================
    -- ETAGE 1 : LINE BUFFERS ET FENETRE 3x3
    -- =================================================

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

                    -- Ligne precedente de deux lignes
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

                    -- Mise a jour des buffers
                    line2(col) <= line1(col);
                    line1(col) <= unsigned(gray_in);

                    -- Activation pour une fenetre complete
                    if row >= 2 and col >= 2 then
                        window_valid <= '1';
                    end if;

                    -- Balayage de l'image
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

    -- =================================================
    -- ETAGE 2 : CALCUL PARALLELE DES GRADIENTS
    -- =================================================

    process(clk)
        variable gx_tmp : integer;
        variable gy_tmp : integer;
    begin
        if rising_edge(clk) then

            if rst = '1' then

                gx_reg <= (others => '0');
                gy_reg <= (others => '0');
                gradient_valid <= '0';

            else

                -- Gradient horizontal :
                -- (p02+2*p12+p22)
                -- - (p00+2*p10+p20)

                gx_tmp :=
                    to_integer(p02)
                    + 2 * to_integer(p12)
                    + to_integer(p22)
                    - to_integer(p00)
                    - 2 * to_integer(p10)
                    - to_integer(p20);

                -- Gradient vertical :
                -- (p20+2*p21+p22)
                -- - (p00+2*p01+p02)

                gy_tmp :=
                    to_integer(p20)
                    + 2 * to_integer(p21)
                    + to_integer(p22)
                    - to_integer(p00)
                    - 2 * to_integer(p01)
                    - to_integer(p02);

                gx_reg <= to_signed(gx_tmp, 12);
                gy_reg <= to_signed(gy_tmp, 12);

                gradient_valid <= window_valid;

            end if;
        end if;
    end process;

    -- =================================================
    -- ETAGE 3 : AMPLITUDE ET SATURATION
    -- =================================================

    process(clk)
        variable amplitude : integer;
    begin
        if rising_edge(clk) then

            if rst = '1' then

                edge_reg <= (others => '0');
                output_valid <= '0';

            else

                -- Approximation de la magnitude Sobel
                amplitude :=
                    abs(to_integer(gx_reg))
                    + abs(to_integer(gy_reg));

                -- Saturation sur 8 bits
                if amplitude > 255 then
                    edge_reg <= to_unsigned(255, 8);
                else
                    edge_reg <= to_unsigned(amplitude, 8);
                end if;

                output_valid <= gradient_valid;

            end if;
        end if;
    end process;

end architecture rtl;

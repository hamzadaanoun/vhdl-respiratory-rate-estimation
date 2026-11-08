
-- ================================================
-- PROJET PFE : Surveillance respiratoire sans contact
-- CARTE      : DE10-Standard - Cyclone V SoC
-- MODULE     : grayscale_pipeline
-- FONCTION   : Conversion RGB888 vers Gray8
-- ARCHITECTURE : Pipeline sur 3 etages
-- ================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity grayscale_pipeline is
    port (
        -- Horloge et reset synchrone actif a 1
        clk       : in std_logic;
        rst       : in std_logic;

        -- Indique qu'un pixel RGB est valide
        valid_in  : in std_logic;

        -- Entrees RGB : 8 bits chacune
        r_in      : in std_logic_vector(7 downto 0);
        g_in      : in std_logic_vector(7 downto 0);
        b_in      : in std_logic_vector(7 downto 0);

        -- Sortie niveau de gris : 8 bits
        gray_out  : out std_logic_vector(7 downto 0);

        -- Indique que le resultat est valide
        valid_out : out std_logic
    );
end entity grayscale_pipeline;


architecture rtl of grayscale_pipeline is

    -- ============================================
    -- ETAGE 1 : Multiplications
    -- ============================================

    signal pr1 : unsigned(15 downto 0)
        := (others => '0');

    signal pg1 : unsigned(15 downto 0)
        := (others => '0');

    signal pb1 : unsigned(15 downto 0)
        := (others => '0');

    -- ============================================
    -- ETAGE 2 : Addition des produits
    -- ============================================

    signal sum2 : unsigned(15 downto 0)
        := (others => '0');

    -- ============================================
    -- ETAGE 3 : Extraction Gray
    -- ============================================

    signal gray3 : unsigned(7 downto 0)
        := (others => '0');

    -- ============================================
    -- Signaux de validite du pipeline
    -- ============================================

    signal v1 : std_logic := '0';
    signal v2 : std_logic := '0';
    signal v3 : std_logic := '0';

begin

    -- Affectation des sorties
    gray_out  <= std_logic_vector(gray3);
    valid_out <= v3;

    -- ============================================
    -- PROCESSUS SYNCHRONE
    -- ============================================

    process(clk)
    begin

        if rising_edge(clk) then

            if rst = '1' then

                -- Remise a zero des registres
                pr1 <= (others => '0');
                pg1 <= (others => '0');
                pb1 <= (others => '0');

                sum2 <= (others => '0');
                gray3 <= (others => '0');

                v1 <= '0';
                v2 <= '0';
                v3 <= '0';

            else

                -- =================================
                -- STAGE 1 : PRODUITS RGB
                -- =================================

                -- R * 77
                pr1 <= unsigned(r_in)
                       * to_unsigned(77, 8);

                -- G * 150
                pg1 <= unsigned(g_in)
                       * to_unsigned(150, 8);

                -- B * 29
                pb1 <= unsigned(b_in)
                       * to_unsigned(29, 8);

                -- Validation du premier etage
                v1 <= valid_in;

                -- =================================
                -- STAGE 2 : SOMME PONDEREE
                -- =================================

                sum2 <= pr1 + pg1 + pb1
                        + to_unsigned(128, 16);

                -- Validation du deuxieme etage
                v2 <= v1;

                -- =================================
                -- STAGE 3 : NIVEAU DE GRIS
                -- =================================

                -- Division entiere par 256
                gray3 <= sum2(15 downto 8);

                -- Validation de la sortie
                v3 <= v2;

            end if;

        end if;

    end process;

end architecture rtl;

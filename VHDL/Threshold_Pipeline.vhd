
-- =====================================================
-- PFE : Traitement d'image sur FPGA DE10-Standard
-- MODULE : threshold_pipeline
-- FPGA : Cyclone V SoC 5CSXFC6D6F31C6
--
-- Fonction :
--   Seuillage binaire des contours Sobel
--   Un pixel traite par cycle
--   Latence : un cycle d'horloge
-- =====================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity threshold_pipeline is

    generic (
        THRESHOLD_VALUE : integer range 0 to 255 := 100
    );

    port (
        clk       : in  std_logic;
        rst       : in  std_logic;
        valid_in  : in  std_logic;

        edge_in   : in  std_logic_vector(7 downto 0);

        binary_out : out std_logic_vector(7 downto 0);
        valid_out  : out std_logic
    );

end entity threshold_pipeline;

architecture rtl of threshold_pipeline is

    signal binary_reg : std_logic_vector(7 downto 0)
        := (others => '0');

    signal valid_reg : std_logic := '0';

begin

    binary_out <= binary_reg;
    valid_out  <= valid_reg;

    process(clk)
    begin
        if rising_edge(clk) then

            if rst = '1' then

                binary_reg <= (others => '0');
                valid_reg  <= '0';

            else

                -- Transmission du signal de validite
                valid_reg <= valid_in;

                if valid_in = '1' then

                    -- Comparaison avec le seuil
                    if unsigned(edge_in) >=
                       to_unsigned(THRESHOLD_VALUE, 8) then

                        binary_reg <= (others => '1');

                    else

                        binary_reg <= (others => '0');

                    end if;

                end if;

            end if;
        end if;
    end process;

end architecture rtl;

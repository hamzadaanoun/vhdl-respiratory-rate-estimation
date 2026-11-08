
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity rgb_mean_calculator is
    port (
        clk : in std_logic;
        rst : in std_logic;

        -- Pixels RGB venant du bloc 8
        rgb_in : in std_logic_vector(23 downto 0);
        roi_pixel_valid : in std_logic;

        -- Fin de la trame RGB
        frame_end : in std_logic;

        -- Moyennes RGB, entieres sur 8 bits
        mean_r : out std_logic_vector(7 downto 0);
        mean_g : out std_logic_vector(7 downto 0);
        mean_b : out std_logic_vector(7 downto 0);

        -- Informations de sortie
        pixel_count : out unsigned(31 downto 0);
        mean_valid : out std_logic;
        roi_has_pixels : out std_logic;
        busy : out std_logic
    );
end entity rgb_mean_calculator;

architecture rtl of rgb_mean_calculator is

    type state_type is (ACCUMULATE, DIVIDE);
    signal state : state_type := ACCUMULATE;

    -- Sommes RGB : 32 bits
    signal sum_r : unsigned(31 downto 0)
        := (others => '0');
    signal sum_g : unsigned(31 downto 0)
        := (others => '0');
    signal sum_b : unsigned(31 downto 0)
        := (others => '0');

    signal count_reg : unsigned(31 downto 0)
        := (others => '0');

    -- Valeurs conservees pendant la division
    signal saved_g : unsigned(31 downto 0)
        := (others => '0');
    signal saved_b : unsigned(31 downto 0)
        := (others => '0');

    -- Diviseur sequentiel partage entre R, G et B
    signal numerator : unsigned(31 downto 0)
        := (others => '0');

    signal denominator : unsigned(31 downto 0)
        := (others => '0');

    signal remainder_reg : unsigned(32 downto 0)
        := (others => '0');

    signal quotient_reg : unsigned(31 downto 0)
        := (others => '0');

    signal bits_remaining : integer range 0 to 32 := 0;
    signal channel : integer range 0 to 2 := 0;

    signal mean_r_reg : std_logic_vector(7 downto 0)
        := (others => '0');
    signal mean_g_reg : std_logic_vector(7 downto 0)
        := (others => '0');
    signal mean_b_reg : std_logic_vector(7 downto 0)
        := (others => '0');

    signal pixel_count_reg : unsigned(31 downto 0)
        := (others => '0');

    signal mean_valid_reg : std_logic := '0';
    signal has_pixels_reg : std_logic := '0';

begin

    mean_r <= mean_r_reg;
    mean_g <= mean_g_reg;
    mean_b <= mean_b_reg;

    pixel_count <= pixel_count_reg;
    mean_valid <= mean_valid_reg;
    roi_has_pixels <= has_pixels_reg;

    busy <= '1' when state = DIVIDE else '0';

    process(clk)

        variable next_r : unsigned(31 downto 0);
        variable next_g : unsigned(31 downto 0);
        variable next_b : unsigned(31 downto 0);
        variable next_count : unsigned(31 downto 0);

        variable temp_rem : unsigned(32 downto 0);
        variable temp_quot : unsigned(31 downto 0);
        variable den_ext : unsigned(32 downto 0);

    begin

        if rising_edge(clk) then

            if rst = '1' then

                state <= ACCUMULATE;

                sum_r <= (others => '0');
                sum_g <= (others => '0');
                sum_b <= (others => '0');
                count_reg <= (others => '0');

                saved_g <= (others => '0');
                saved_b <= (others => '0');

                numerator <= (others => '0');
                denominator <= (others => '0');
                remainder_reg <= (others => '0');
                quotient_reg <= (others => '0');

                bits_remaining <= 0;
                channel <= 0;

                mean_r_reg <= (others => '0');
                mean_g_reg <= (others => '0');
                mean_b_reg <= (others => '0');

                pixel_count_reg <= (others => '0');
                mean_valid_reg <= '0';
                has_pixels_reg <= '0';

            else

                -- Impulsion d'un cycle
                mean_valid_reg <= '0';

                case state is

                    ----------------------------------------
                    -- ETAPE 1 : ACCUMULATION DES PIXELS
                    ----------------------------------------

                    when ACCUMULATE =>

                        next_r := sum_r;
                        next_g := sum_g;
                        next_b := sum_b;
                        next_count := count_reg;

                        if roi_pixel_valid = '1' then

                            next_r := next_r +
                                resize(unsigned(
                                    rgb_in(23 downto 16)), 32);

                            next_g := next_g +
                                resize(unsigned(
                                    rgb_in(15 downto 8)), 32);

                            next_b := next_b +
                                resize(unsigned(
                                    rgb_in(7 downto 0)), 32);

                            next_count := next_count + 1;

                        end if;

                        if frame_end = '1' then

                            -- Enregistrer le nombre de pixels
                            pixel_count_reg <= next_count;

                            -- Preparer la trame suivante
                            sum_r <= (others => '0');
                            sum_g <= (others => '0');
                            sum_b <= (others => '0');
                            count_reg <= (others => '0');

                            if next_count = to_unsigned(0, 32) then

                                -- Aucun pixel ROI : resultat vide
                                mean_r_reg <= (others => '0');
                                mean_g_reg <= (others => '0');
                                mean_b_reg <= (others => '0');

                                has_pixels_reg <= '0';
                                mean_valid_reg <= '1';

                            else

                                -- Conserver les autres sommes
                                saved_g <= next_g;
                                saved_b <= next_b;

                                denominator <= next_count;

                                -- Commencer par la moyenne R
                                numerator <= next_r;
                                remainder_reg <= (others => '0');
                                quotient_reg <= (others => '0');

                                bits_remaining <= 32;
                                channel <= 0;

                                has_pixels_reg <= '1';
                                state <= DIVIDE;

                            end if;

                        else

                            sum_r <= next_r;
                            sum_g <= next_g;
                            sum_b <= next_b;
                            count_reg <= next_count;

                        end if;

                    ----------------------------------------
                    -- ETAPE 2 : DIVISION SEQUENTIELLE
                    ----------------------------------------

                    when DIVIDE =>

                        -- Division binaire sans signe :
                        -- un bit du quotient par cycle

                        temp_rem :=
                            remainder_reg(31 downto 0) &
                            numerator(31);

                        den_ext := resize(denominator, 33);

                        temp_quot :=
                            quotient_reg(30 downto 0) & '0';

                        if temp_rem >= den_ext then

                            temp_rem := temp_rem - den_ext;
                            temp_quot(0) := '1';

                        end if;

                        remainder_reg <= temp_rem;
                        quotient_reg <= temp_quot;

                        numerator <=
                            numerator(30 downto 0) & '0';

                        if bits_remaining > 1 then

                            bits_remaining <= bits_remaining - 1;

                        else

                            -- Quotient complet apres 32 cycles
                            case channel is

                                when 0 =>

                                    mean_r_reg <=
                                        std_logic_vector(
                                            temp_quot(7 downto 0));

                                    numerator <= saved_g;
                                    remainder_reg <= (others => '0');
                                    quotient_reg <= (others => '0');

                                    bits_remaining <= 32;
                                    channel <= 1;

                                when 1 =>

                                    mean_g_reg <=
                                        std_logic_vector(
                                            temp_quot(7 downto 0));

                                    numerator <= saved_b;
                                    remainder_reg <= (others => '0');
                                    quotient_reg <= (others => '0');

                                    bits_remaining <= 32;
                                    channel <= 2;

                                when others =>

                                    mean_b_reg <=
                                        std_logic_vector(
                                            temp_quot(7 downto 0));

                                    bits_remaining <= 0;
                                    channel <= 0;

                                    mean_valid_reg <= '1';
                                    state <= ACCUMULATE;

                            end case;

                        end if;

                end case;

            end if;

        end if;

    end process;

end architecture rtl;

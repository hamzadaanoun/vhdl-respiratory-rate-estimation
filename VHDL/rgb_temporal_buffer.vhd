
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity rgb_temporal_buffer is
    port (
        clk : in std_logic;
        rst : in std_logic;

        -- Entrees du bloc 9
        mean_r : in std_logic_vector(7 downto 0);
        mean_g : in std_logic_vector(7 downto 0);
        mean_b : in std_logic_vector(7 downto 0);
        mean_valid : in std_logic;

        -- Interface de lecture vers la PCA
        read_enable : in std_logic;
        read_address : in unsigned(8 downto 0);

        read_r : out std_logic_vector(7 downto 0);
        read_g : out std_logic_vector(7 downto 0);
        read_b : out std_logic_vector(7 downto 0);
        read_valid : out std_logic;

        -- Etat du tampon
        write_index : out unsigned(8 downto 0);
        sample_count : out unsigned(9 downto 0);
        buffer_full : out std_logic
    );
end entity;

architecture rtl of rgb_temporal_buffer is

    constant BUFFER_SIZE : integer := 512;

    --------------------------------------------------
    -- MEMOIRE RGB : 512 x 24 bits
    --------------------------------------------------

    type ram_type is array (0 to BUFFER_SIZE-1)
        of std_logic_vector(23 downto 0);

    signal ram : ram_type;

    -- Preferer les memoires M10K du Cyclone V
    attribute ramstyle : string;
    attribute ramstyle of ram : signal is "M10K";

    --------------------------------------------------
    -- REGISTRES DE CONTROLE
    --------------------------------------------------

    signal wr_ptr : unsigned(8 downto 0)
        := (others => '0');

    signal count_reg : unsigned(9 downto 0)
        := (others => '0');

    signal full_reg : std_logic := '0';

    signal read_data_reg : std_logic_vector(23 downto 0)
        := (others => '0');

    signal read_valid_reg : std_logic := '0';

begin

    --------------------------------------------------
    -- ECRITURE SYNCHRONE EN MEMOIRE
    --------------------------------------------------

    process(clk)
    begin
        if rising_edge(clk) then

            -- Ne pas reinitialiser le contenu RAM
            -- pour permettre l'inference M10K.
            if rst = '0' and mean_valid = '1' then

                ram(to_integer(wr_ptr)) <=
                    mean_r & mean_g & mean_b;

            end if;

        end if;
    end process;

    --------------------------------------------------
    -- POINTEUR D'ECRITURE ET COMPTEUR
    --------------------------------------------------

    process(clk)
    begin
        if rising_edge(clk) then

            if rst = '1' then

                wr_ptr <= (others => '0');
                count_reg <= (others => '0');
                full_reg <= '0';

            else

                if mean_valid = '1' then

                    -- Debordement naturel sur 9 bits :
                    -- 511 + 1 -> 0
                    wr_ptr <= wr_ptr + 1;

                    -- Saturation du compteur a 512
                    if count_reg <
                        to_unsigned(BUFFER_SIZE, 10) then

                        count_reg <= count_reg + 1;

                        if count_reg =
                            to_unsigned(BUFFER_SIZE-1, 10) then

                            full_reg <= '1';

                        end if;
                    end if;

                end if;

            end if;

        end if;
    end process;

    --------------------------------------------------
    -- LECTURE SYNCHRONE
    --------------------------------------------------

    process(clk)
    begin
        if rising_edge(clk) then

            -- Registre des donnees lu directement
            -- depuis la RAM : structure compatible
            -- avec l'inference de Block RAM.
            if read_enable = '1' then

                read_data_reg <=
                    ram(to_integer(read_address));

            end if;

        end if;
    end process;

    --------------------------------------------------
    -- VALIDITE DE LA LECTURE
    --------------------------------------------------

    process(clk)
    begin
        if rising_edge(clk) then

            if rst = '1' then
                read_valid_reg <= '0';
            else
                read_valid_reg <= read_enable;
            end if;

        end if;
    end process;

    --------------------------------------------------
    -- SORTIES RGB
    --------------------------------------------------

    read_r <= read_data_reg(23 downto 16);
    read_g <= read_data_reg(15 downto 8);
    read_b <= read_data_reg(7 downto 0);

    read_valid <= read_valid_reg;

    --------------------------------------------------
    -- SORTIES DE CONTROLE
    --------------------------------------------------

    write_index <= wr_ptr;
    sample_count <= count_reg;
    buffer_full <= full_reg;

end architecture rtl;

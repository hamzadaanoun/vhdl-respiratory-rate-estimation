
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity morphology_pipeline is
    generic (
        IMG_WIDTH  : positive := 640;
        IMG_HEIGHT : positive := 480
    );
    port (
        clk        : in  std_logic;
        rst        : in  std_logic;
        valid_in   : in  std_logic;
        binary_in  : in  std_logic_vector(7 downto 0);
        binary_out : out std_logic_vector(7 downto 0);
        valid_out  : out std_logic
    );
end entity;

architecture rtl of morphology_pipeline is

    --------------------------------------------------
    -- MEMOIRES DE LIGNES
    --------------------------------------------------

    type ram_type is array (0 to IMG_WIDTH-1)
        of std_logic_vector(0 downto 0);

    signal line1 : ram_type;
    signal line2 : ram_type;

    attribute ramstyle : string;
    attribute ramstyle of line1 : signal is "M10K";
    attribute ramstyle of line2 : signal is "M10K";

    signal read1 : std_logic_vector(0 downto 0);
    signal read2 : std_logic_vector(0 downto 0);

    --------------------------------------------------
    -- POSITION ET SYNCHRONISATION
    --------------------------------------------------

    signal col : integer range 0 to IMG_WIDTH-1 := 0;
    signal row : integer range 0 to IMG_HEIGHT-1 := 0;

    signal col_d : integer range 0 to IMG_WIDTH-1 := 0;
    signal row_d : integer range 0 to IMG_HEIGHT-1 := 0;

    signal valid_d : std_logic := '0';
    signal pixel_d : std_logic := '0';

    --------------------------------------------------
    -- FENETRE MORPHOLOGIQUE 3x3
    --------------------------------------------------

    signal p00, p01, p02 : std_logic := '0';
    signal p10, p11, p12 : std_logic := '0';
    signal p20, p21, p22 : std_logic := '0';

    signal window_valid : std_logic := '0';

    signal result_reg   : std_logic := '0';
    signal result_valid : std_logic := '0';

begin

    binary_out <= (others => result_reg);
    valid_out  <= result_valid;

    --------------------------------------------------
    -- RAM 1 : PREMIERE LIGNE RETARDEE
    --
    -- Lecture synchrone.
    -- Ecriture du nouveau pixel.
    -- Aucun reset sur le contenu RAM.
    --------------------------------------------------

    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '0' and valid_in = '1' then
                read1 <= line1(col);
                line1(col) <=
                    (0 => binary_in(0));
            end if;
        end if;
    end process;

    --------------------------------------------------
    -- RAM 2 : DEUXIEME LIGNE RETARDEE
    --
    -- Lecture de la ligne precedente stockee.
    -- Ecriture avec une adresse retardee.
    --------------------------------------------------

    process(clk)
    begin
        if rising_edge(clk) then

            if rst = '0' then

                if valid_in = '1' then
                    read2 <= line2(col);
                end if;

                if valid_d = '1' then
                    line2(col_d) <= read1;
                end if;

            end if;
        end if;
    end process;

    --------------------------------------------------
    -- COMPTEURS ET RETARDS
    --------------------------------------------------

    process(clk)
    begin
        if rising_edge(clk) then

            if rst = '1' then
                col <= 0;
                row <= 0;

                col_d <= 0;
                row_d <= 0;

                pixel_d <= '0';
                valid_d <= '0';

            else

                valid_d <= '0';

                if valid_in = '1' then

                    pixel_d <= binary_in(0);

                    col_d <= col;
                    row_d <= row;

                    valid_d <= '1';

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

    --------------------------------------------------
    -- CONSTRUCTION DE LA FENETRE 3x3
    --------------------------------------------------

    process(clk)
    begin
        if rising_edge(clk) then

            if rst = '1' then

                p00 <= '0';
                p01 <= '0';
                p02 <= '0';

                p10 <= '0';
                p11 <= '0';
                p12 <= '0';

                p20 <= '0';
                p21 <= '0';
                p22 <= '0';

                window_valid <= '0';

            else

                window_valid <= '0';

                if valid_d = '1' then

                    -- Ligne y-2
                    p00 <= p01;
                    p01 <= p02;
                    p02 <= read2(0);

                    -- Ligne y-1
                    p10 <= p11;
                    p11 <= p12;
                    p12 <= read1(0);

                    -- Ligne actuelle
                    p20 <= p21;
                    p21 <= p22;
                    p22 <= pixel_d;

                    if row_d >= 2 and col_d >= 2 then
                        window_valid <= '1';
                    end if;

                end if;

            end if;
        end if;
    end process;

    --------------------------------------------------
    -- DILATATION BINAIRE 3x3
    --------------------------------------------------

    process(clk)
    begin
        if rising_edge(clk) then

            if rst = '1' then

                result_reg <= '0';
                result_valid <= '0';

            else

                result_reg <=
                    p00 or p01 or p02 or
                    p10 or p11 or p12 or
                    p20 or p21 or p22;

                result_valid <= window_valid;

            end if;
        end if;
    end process;

end architecture rtl;

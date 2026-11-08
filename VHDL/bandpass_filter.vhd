library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Bloc 12 : filtre passe-bande RGB-PCA, pour Fs = 25 Hz.
-- Passe-haut de premier ordre : alpha = exp(-2*pi*0.1/25), Q15.
-- Passe-bas de premier ordre : beta = 1-exp(-2*pi*0.5/25), Q15.
-- Enchainement : HP, puis LP. Traitement d'un echantillon en 4 cycles.
-- IMPORTANT : les frequences sont nominales (filtres de premier ordre),
-- et non des coupures ideales. Les entrees doivent suivre 25 Hz.
entity bandpass_filter is
    port (
        clk         : in  std_logic;
        rst         : in  std_logic;
        sample_in   : in  signed(31 downto 0);
        in_valid    : in  std_logic;
        in_last     : in  std_logic;
        in_ready    : out std_logic;
        sample_out  : out signed(31 downto 0);
        out_valid   : out std_logic;
        out_last    : out std_logic;
        busy        : out std_logic
    );
end entity;

architecture rtl of bandpass_filter is
    constant Q_BITS   : natural := 15;
    constant HP_ALPHA : integer := 31955; -- ~0.97518 * 32768
    constant LP_BETA  : integer := 3860;  -- ~0.11750 * 32768

    type state_t is (IDLE, HP_STEP, LP_STEP, OUTPUT_STEP);
    signal state : state_t := IDLE;

    signal x_reg, x_prev : signed(31 downto 0) := (others => '0');
    signal hp_q, lp_q : signed(63 downto 0) := (others => '0');
    signal x_last : std_logic := '0';
    signal result_reg : signed(31 downto 0) := (others => '0');
    signal valid_reg, last_reg : std_logic := '0';

    -- Conversion Q15 vers entier 32 bits avec saturation.
    function sat_q15(a : signed(63 downto 0)) return signed is
        variable v : signed(63 downto 0);
    begin
        v := shift_right(a, Q_BITS);
        if v > to_signed(2147483647, 64) then
            return to_signed(2147483647, 32);
        elsif v < shift_left(to_signed(-1, 64), 31) then
            return signed'(x"80000000");
        else
            return resize(v, 32);
        end if;
    end function;
begin
    in_ready <= '1' when state = IDLE else '0';
    busy <= '0' when state = IDLE else '1';
    sample_out <= result_reg;
    out_valid <= valid_reg;
    out_last <= last_reg;

    process(clk)
        variable dx : signed(63 downto 0);
        variable hp_arg : signed(63 downto 0);
        variable hp_prod : signed(79 downto 0);
        variable lp_delta : signed(63 downto 0);
        variable lp_prod : signed(79 downto 0);
    begin
        if rising_edge(clk) then
            valid_reg <= '0';
            last_reg <= '0';
            if rst = '1' then
                state <= IDLE;
                x_reg <= (others => '0');
                x_prev <= (others => '0');
                hp_q <= (others => '0');
                lp_q <= (others => '0');
                x_last <= '0';
                result_reg <= (others => '0');
            else
                case state is
                    when IDLE =>
                        if in_valid = '1' then
                            x_reg <= sample_in;
                            x_last <= in_last;
                            state <= HP_STEP;
                        end if;

                    when HP_STEP =>
                        dx := resize(x_reg, 64) - resize(x_prev, 64);
                        hp_arg := hp_q + shift_left(dx, Q_BITS);
                        hp_prod := hp_arg * to_signed(HP_ALPHA, 16);
                        hp_q <= resize(shift_right(hp_prod, Q_BITS), 64);
                        x_prev <= x_reg;
                        state <= LP_STEP;

                    when LP_STEP =>
                        -- lp[n] = lp[n-1] + beta*(hp[n]-lp[n-1])
                        lp_delta := hp_q - lp_q;
                        lp_prod := lp_delta * to_signed(LP_BETA, 16);
                        lp_q <= lp_q + resize(shift_right(lp_prod, Q_BITS),64);
                        state <= OUTPUT_STEP;

                    when OUTPUT_STEP =>
                        result_reg <= sat_q15(lp_q);
                        valid_reg <= '1';
                        last_reg <= x_last;
                        state <= IDLE;
                end case;
            end if;
        end if;
    end process;
end architecture;

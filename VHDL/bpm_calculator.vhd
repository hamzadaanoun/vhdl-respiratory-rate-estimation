library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Block 14: peak search within 0.1..0.5 Hz for a 512-point FFT at Fs=25 Hz.
-- Eligible positive-frequency FFT bins: k=3..10.
-- Input one bin per out_valid pulse (from fft_512), index 0..511.
-- in_last marks the final bin of the frame; it must coincide with in_valid.
-- A result is emitted on the same clock edge as the final accepted bin.
-- No division, clock enable or external RAM required.
entity bpm_calculator is
    port (
        clk           : in  std_logic;
        rst           : in  std_logic;
        magnitude_in  : in  unsigned(31 downto 0);
        bin_index_in  : in  unsigned(8 downto 0);
        in_valid      : in  std_logic;
        in_last       : in  std_logic;
        bpm_out       : out unsigned(7 downto 0);
        peak_bin_out  : out unsigned(8 downto 0);
        peak_mag_out  : out unsigned(31 downto 0);
        bpm_valid     : out std_logic;
        peak_found    : out std_logic;
        done          : out std_logic
    );
end entity;

architecture rtl of bpm_calculator is
    constant MIN_BIN : integer := 3;
    constant MAX_BIN : integer := 10;

    signal best_mag  : unsigned(31 downto 0) := (others => '0');
    signal best_bin  : unsigned(8 downto 0)  := (others => '0');
    signal best_seen : std_logic := '0';

    signal bpm_reg      : unsigned(7 downto 0)  := (others => '0');
    signal peak_bin_reg : unsigned(8 downto 0)  := (others => '0');
    signal peak_mag_reg : unsigned(31 downto 0) := (others => '0');
    signal valid_reg    : std_logic := '0';
    signal found_reg    : std_logic := '0';
    signal done_reg     : std_logic := '0';
begin
    bpm_out      <= bpm_reg;
    peak_bin_out <= peak_bin_reg;
    peak_mag_out <= peak_mag_reg;
    bpm_valid    <= valid_reg;
    peak_found   <= found_reg;
    done         <= done_reg;

    process(clk)
        variable candidate_mag  : unsigned(31 downto 0);
        variable candidate_bin  : unsigned(8 downto 0);
        variable candidate_seen : std_logic;
        variable k              : integer;
        variable bpm_i          : integer;
    begin
        if rising_edge(clk) then
            valid_reg <= '0';
            done_reg  <= '0';

            if rst = '1' then
                best_mag      <= (others => '0');
                best_bin      <= (others => '0');
                best_seen     <= '0';
                bpm_reg      <= (others => '0');
                peak_bin_reg <= (others => '0');
                peak_mag_reg <= (others => '0');
                valid_reg    <= '0';
                found_reg    <= '0';
                done_reg     <= '0';
            elsif in_valid = '1' then
                candidate_mag  := best_mag;
                candidate_bin  := best_bin;
                candidate_seen := best_seen;
                k := to_integer(bin_index_in);

                -- Exclude DC and all out-of-band bins. Ignore zero magnitude.
                if (k >= MIN_BIN) and (k <= MAX_BIN) and
                   (magnitude_in /= to_unsigned(0,32)) then
                    -- Strict > yields deterministic selection of the first
                    -- maximum when equal magnitudes appear in two bins.
                    if candidate_seen = '0' or magnitude_in > candidate_mag then
                        candidate_mag  := magnitude_in;
                        candidate_bin  := bin_index_in;
                        candidate_seen := '1';
                    end if;
                end if;

                if in_last = '1' then
                    done_reg <= '1';
                    found_reg <= candidate_seen;
                    if candidate_seen = '1' then
                        -- BPM = round(k*25*60/512) = round(k*1500/512)
                        bpm_i := (to_integer(candidate_bin)*1500 + 256)/512;
                        bpm_reg      <= to_unsigned(bpm_i,8);
                        peak_bin_reg <= candidate_bin;
                        peak_mag_reg <= candidate_mag;
                        valid_reg    <= '1';
                    else
                        bpm_reg      <= (others => '0');
                        peak_bin_reg <= (others => '0');
                        peak_mag_reg <= (others => '0');
                    end if;
                    -- Re-arm for a new FFT without an external reset.
                    best_mag  <= (others => '0');
                    best_bin  <= (others => '0');
                    best_seen <= '0';
                else
                    best_mag  <= candidate_mag;
                    best_bin  <= candidate_bin;
                    best_seen <= candidate_seen;
                end if;
            end if;
        end if;
    end process;
end architecture;

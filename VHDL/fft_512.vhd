library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- FFT complexe 512 points, radix-2 DIT, mise a l'echelle 1/2 a chaque etage.
-- Entree reelle signee sur 32 bits; sortie |Re|+|Im| en 32 bits.
-- Le resultat est un indicateur spectral (L1), PAS une magnitude euclidienne.
-- Le bloc accepte une fenetre de 512 echantillons, puis calcule avant de
-- pouvoir accepter la fenetre suivante (in_ready = 0 pendant le calcul).
entity fft_512 is
    port (
        clk, rst      : in std_logic;
        sample_in     : in signed(31 downto 0);
        in_valid      : in std_logic;
        in_last       : in std_logic;
        in_ready      : out std_logic;
        bin_index     : out unsigned(8 downto 0);
        magnitude_out : out unsigned(31 downto 0);
        out_valid     : out std_logic;
        out_last      : out std_logic;
        busy          : out std_logic;
        done          : out std_logic
    );
end entity;

architecture rtl of fft_512 is
    constant N : integer := 512;
    -- Une seule RAM synchrone lecture/ecriture : acces sequentiels.
    type ram_t is array (0 to N-1) of std_logic_vector(63 downto 0);
    signal ram : ram_t;
    attribute ramstyle : string;
    attribute ramstyle of ram : signal is "M10K";

    -- Table de sinus sur 1/4 periode en Q15 pour les twiddles.
    type sin_table_t is array (0 to 128) of signed(15 downto 0);
    constant SIN_Q15 : sin_table_t := (
        0 => to_signed(0, 16),
        1 => to_signed(402, 16),
        2 => to_signed(804, 16),
        3 => to_signed(1206, 16),
        4 => to_signed(1608, 16),
        5 => to_signed(2009, 16),
        6 => to_signed(2410, 16),
        7 => to_signed(2811, 16),
        8 => to_signed(3212, 16),
        9 => to_signed(3612, 16),
        10 => to_signed(4011, 16),
        11 => to_signed(4410, 16),
        12 => to_signed(4808, 16),
        13 => to_signed(5205, 16),
        14 => to_signed(5602, 16),
        15 => to_signed(5998, 16),
        16 => to_signed(6393, 16),
        17 => to_signed(6786, 16),
        18 => to_signed(7179, 16),
        19 => to_signed(7571, 16),
        20 => to_signed(7962, 16),
        21 => to_signed(8351, 16),
        22 => to_signed(8739, 16),
        23 => to_signed(9126, 16),
        24 => to_signed(9512, 16),
        25 => to_signed(9896, 16),
        26 => to_signed(10278, 16),
        27 => to_signed(10659, 16),
        28 => to_signed(11039, 16),
        29 => to_signed(11417, 16),
        30 => to_signed(11793, 16),
        31 => to_signed(12167, 16),
        32 => to_signed(12539, 16),
        33 => to_signed(12910, 16),
        34 => to_signed(13279, 16),
        35 => to_signed(13645, 16),
        36 => to_signed(14010, 16),
        37 => to_signed(14372, 16),
        38 => to_signed(14732, 16),
        39 => to_signed(15090, 16),
        40 => to_signed(15446, 16),
        41 => to_signed(15800, 16),
        42 => to_signed(16151, 16),
        43 => to_signed(16499, 16),
        44 => to_signed(16846, 16),
        45 => to_signed(17189, 16),
        46 => to_signed(17530, 16),
        47 => to_signed(17869, 16),
        48 => to_signed(18204, 16),
        49 => to_signed(18537, 16),
        50 => to_signed(18868, 16),
        51 => to_signed(19195, 16),
        52 => to_signed(19519, 16),
        53 => to_signed(19841, 16),
        54 => to_signed(20159, 16),
        55 => to_signed(20475, 16),
        56 => to_signed(20787, 16),
        57 => to_signed(21096, 16),
        58 => to_signed(21403, 16),
        59 => to_signed(21705, 16),
        60 => to_signed(22005, 16),
        61 => to_signed(22301, 16),
        62 => to_signed(22594, 16),
        63 => to_signed(22884, 16),
        64 => to_signed(23170, 16),
        65 => to_signed(23452, 16),
        66 => to_signed(23731, 16),
        67 => to_signed(24007, 16),
        68 => to_signed(24279, 16),
        69 => to_signed(24547, 16),
        70 => to_signed(24811, 16),
        71 => to_signed(25072, 16),
        72 => to_signed(25329, 16),
        73 => to_signed(25582, 16),
        74 => to_signed(25832, 16),
        75 => to_signed(26077, 16),
        76 => to_signed(26319, 16),
        77 => to_signed(26556, 16),
        78 => to_signed(26790, 16),
        79 => to_signed(27019, 16),
        80 => to_signed(27245, 16),
        81 => to_signed(27466, 16),
        82 => to_signed(27683, 16),
        83 => to_signed(27896, 16),
        84 => to_signed(28105, 16),
        85 => to_signed(28310, 16),
        86 => to_signed(28510, 16),
        87 => to_signed(28706, 16),
        88 => to_signed(28898, 16),
        89 => to_signed(29085, 16),
        90 => to_signed(29268, 16),
        91 => to_signed(29447, 16),
        92 => to_signed(29621, 16),
        93 => to_signed(29791, 16),
        94 => to_signed(29956, 16),
        95 => to_signed(30117, 16),
        96 => to_signed(30273, 16),
        97 => to_signed(30424, 16),
        98 => to_signed(30571, 16),
        99 => to_signed(30714, 16),
        100 => to_signed(30852, 16),
        101 => to_signed(30985, 16),
        102 => to_signed(31113, 16),
        103 => to_signed(31237, 16),
        104 => to_signed(31356, 16),
        105 => to_signed(31470, 16),
        106 => to_signed(31580, 16),
        107 => to_signed(31685, 16),
        108 => to_signed(31785, 16),
        109 => to_signed(31880, 16),
        110 => to_signed(31971, 16),
        111 => to_signed(32057, 16),
        112 => to_signed(32137, 16),
        113 => to_signed(32213, 16),
        114 => to_signed(32285, 16),
        115 => to_signed(32351, 16),
        116 => to_signed(32412, 16),
        117 => to_signed(32469, 16),
        118 => to_signed(32521, 16),
        119 => to_signed(32567, 16),
        120 => to_signed(32609, 16),
        121 => to_signed(32646, 16),
        122 => to_signed(32678, 16),
        123 => to_signed(32705, 16),
        124 => to_signed(32728, 16),
        125 => to_signed(32745, 16),
        126 => to_signed(32757, 16),
        127 => to_signed(32765, 16),
        128 => to_signed(32767, 16)
    );

    -- W(k)=cos(2*pi*k/512)-j*sin(2*pi*k/512), k dans [0,255].
    function tw_cos(k : integer) return signed is
    begin
        if k <= 128 then
            return SIN_Q15(128-k);
        else
            return -SIN_Q15(k-128);
        end if;
    end function;

    function tw_sin_neg(k : integer) return signed is
    begin
        if k <= 128 then
            return -SIN_Q15(k);
        else
            return -SIN_Q15(256-k);
        end if;
    end function;

    function bitreverse9(v : unsigned(8 downto 0)) return unsigned is
        variable r : unsigned(8 downto 0);
    begin
        for i in 0 to 8 loop
            r(i) := v(8-i);
        end loop;
        return r;
    end function;

    -- Evite le debordement avec la valeur signee minimale sur 32 bits.
    function mag_l1(r, i : signed(31 downto 0)) return unsigned is
        variable ar, ai : signed(32 downto 0);
        variable s : unsigned(33 downto 0);
    begin
        ar := resize(r,33);
        ai := resize(i,33);
        if ar < 0 then ar := -ar; end if;
        if ai < 0 then ai := -ai; end if;
        s := resize(unsigned(ar),34) + resize(unsigned(ai),34);
        if s(33 downto 32) /= "00" then
            return (31 downto 0 => '1');
        else
            return resize(s,32);
        end if;
    end function;

    type state_t is (
        COLLECT, PREPARE,
        A_ADDRESS, A_WAIT, A_CAPTURE,
        B_ADDRESS, B_WAIT, B_CAPTURE,
        BUTTERFLY, WRITE_A, WRITE_B, ADVANCE,
        OUT_ADDRESS, OUT_WAIT, OUT_CAPTURE, FINISH
    );
    signal st : state_t := COLLECT;
    signal received : integer range 0 to 511 := 0;
    signal stage : integer range 0 to 8 := 0;
    signal butterfly_idx : integer range 0 to 255 := 0;
    signal half_size : integer range 1 to 256 := 1;
    signal addr_a, addr_b : integer range 0 to 511 := 0;
    signal tw_idx : integer range 0 to 255 := 0;
    signal out_idx : integer range 0 to 511 := 0;

    signal wr_en : std_logic := '0';
    signal wr_addr : integer range 0 to 511 := 0;
    signal wr_data : std_logic_vector(63 downto 0) := (others=>'0');
    signal rd_en : std_logic := '0';
    signal rd_addr : integer range 0 to 511 := 0;
    signal rd_data : std_logic_vector(63 downto 0) := (others=>'0');

    signal a_re, a_im, b_re, b_im : signed(31 downto 0) := (others=>'0');
    signal new_a_re, new_a_im, new_b_re, new_b_im : signed(31 downto 0) := (others=>'0');
    signal out_mag : unsigned(31 downto 0) := (others=>'0');
    signal out_addr : unsigned(8 downto 0) := (others=>'0');
    signal ov, ol, dn : std_logic := '0';
begin
    memory_p : process(clk)
    begin
        if rising_edge(clk) then
            if wr_en = '1' then
                ram(wr_addr) <= wr_data;
            end if;
            if rd_en = '1' then
                rd_data <= ram(rd_addr);
            end if;
        end if;
    end process;

    in_ready <= '1' when st = COLLECT else '0';
    busy <= '0' when st = COLLECT else '1';
    bin_index <= out_addr;
    magnitude_out <= out_mag;
    out_valid <= ov;
    out_last <= ol;
    done <= dn;

    control : process(clk)
        variable j : integer;
        variable group_no : integer;
        variable size_now : integer;
        variable wre, wim : signed(15 downto 0);
        variable product_re, product_im : signed(63 downto 0);
        variable tr, ti : signed(63 downto 0);
        variable sum_re, sum_im, dif_re, dif_im : signed(63 downto 0);
    begin
        if rising_edge(clk) then
            ov <= '0'; ol <= '0'; dn <= '0';
            wr_en <= '0'; rd_en <= '0';
            if rst = '1' then
                st <= COLLECT;
                received <= 0;
                stage <= 0;
                butterfly_idx <= 0;
                half_size <= 1;
                out_idx <= 0;
                wr_en <= '0'; rd_en <= '0';
            else
                case st is
                    when COLLECT =>
                        if in_valid = '1' then
                            wr_en <= '1';
                            wr_addr <= to_integer(bitreverse9(to_unsigned(received,9)));
                            wr_data <= std_logic_vector(sample_in) & x"00000000";
                            if received = 511 then
                                received <= 0;
                                st <= PREPARE;
                            else
                                received <= received+1;
                            end if;
                        end if;
                    when PREPARE =>
                        stage <= 0;
                        half_size <= 1;
                        butterfly_idx <= 0;
                        st <= A_ADDRESS;
                    when A_ADDRESS =>
                        j := butterfly_idx mod half_size;
                        group_no := butterfly_idx / half_size;
                        size_now := 2*half_size;
                        addr_a <= group_no*size_now + j;
                        addr_b <= group_no*size_now + j + half_size;
                        tw_idx <= j*(256/half_size);
                        rd_addr <= group_no*size_now + j;
                        rd_en <= '1';
                        st <= A_WAIT;
                    when A_WAIT =>
                        st <= A_CAPTURE;
                    when A_CAPTURE =>
                        a_re <= signed(rd_data(63 downto 32));
                        a_im <= signed(rd_data(31 downto 0));
                        st <= B_ADDRESS;
                    when B_ADDRESS =>
                        rd_addr <= addr_b;
                        rd_en <= '1';
                        st <= B_WAIT;
                    when B_WAIT =>
                        st <= B_CAPTURE;
                    when B_CAPTURE =>
                        b_re <= signed(rd_data(63 downto 32));
                        b_im <= signed(rd_data(31 downto 0));
                        st <= BUTTERFLY;
                    when BUTTERFLY =>
                        wre := tw_cos(tw_idx);
                        wim := tw_sin_neg(tw_idx);
                        product_re := resize(b_re*wre,64) - resize(b_im*wim,64);
                        product_im := resize(b_re*wim,64) + resize(b_im*wre,64);
                        tr := shift_right(product_re,15);
                        ti := shift_right(product_im,15);
                        sum_re := shift_right(resize(a_re,64)+tr,1);
                        sum_im := shift_right(resize(a_im,64)+ti,1);
                        dif_re := shift_right(resize(a_re,64)-tr,1);
                        dif_im := shift_right(resize(a_im,64)-ti,1);
                        new_a_re <= resize(sum_re,32);
                        new_a_im <= resize(sum_im,32);
                        new_b_re <= resize(dif_re,32);
                        new_b_im <= resize(dif_im,32);
                        st <= WRITE_A;
                    when WRITE_A =>
                        wr_addr <= addr_a;
                        wr_data <= std_logic_vector(new_a_re) & std_logic_vector(new_a_im);
                        wr_en <= '1';
                        st <= WRITE_B;
                    when WRITE_B =>
                        wr_addr <= addr_b;
                        wr_data <= std_logic_vector(new_b_re) & std_logic_vector(new_b_im);
                        wr_en <= '1';
                        st <= ADVANCE;
                    when ADVANCE =>
                        if butterfly_idx = 255 then
                            if stage = 8 then
                                out_idx <= 0;
                                st <= OUT_ADDRESS;
                            else
                                butterfly_idx <= 0;
                                stage <= stage + 1;
                                half_size <= half_size * 2;
                                st <= A_ADDRESS;
                            end if;
                        else
                            butterfly_idx <= butterfly_idx+1;
                            st <= A_ADDRESS;
                        end if;
                    when OUT_ADDRESS =>
                        rd_addr <= out_idx;
                        rd_en <= '1';
                        st <= OUT_WAIT;
                    when OUT_WAIT =>
                        st <= OUT_CAPTURE;
                    when OUT_CAPTURE =>
                        out_addr <= to_unsigned(out_idx,9);
                        out_mag <= mag_l1(signed(rd_data(63 downto 32)),
                                          signed(rd_data(31 downto 0)));
                        ov <= '1';
                        if out_idx = 511 then
                            ol <= '1';
                            st <= FINISH;
                        else
                            out_idx <= out_idx + 1;
                            st <= OUT_ADDRESS;
                        end if;
                    when FINISH =>
                        dn <= '1';
                        received <= 0;
                        st <= COLLECT;
                end case;
            end if;
        end if;
    end process;
end architecture rtl;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Standalone fixed-point PCA for a window of 512 RGB samples.
-- Samples are written during acquisition. No new sample is accepted while busy.
entity pca_rgb is
  port (
    clk, rst      : in std_logic;
    rgb_r, rgb_g, rgb_b : in std_logic_vector(7 downto 0);
    sample_valid  : in std_logic;
    sample_out    : out signed(31 downto 0);
    out_valid     : out std_logic;
    out_last      : out std_logic;
    busy          : out std_logic;
    done          : out std_logic
  );
end entity;

architecture rtl of pca_rgb is
  constant N : integer := 512;
  type ram_t is array(0 to N-1) of std_logic_vector(23 downto 0);
  signal ram : ram_t;
  attribute ramstyle : string;
  attribute ramstyle of ram : signal is "M10K";

  type st_t is (COLLECT, MEAN_CALC, COV_ADDR, COV_WAIT, COV_USE,
                INIT_EIG, EIG_CALC, EIG_NORM,
                EMIT_ADDR, EMIT_WAIT, EMIT_USE, FINISH);
  signal st : st_t := COLLECT;
  signal wp : integer range 0 to N-1 := 0;
  signal pos : integer range 0 to N := 0;
  signal rd_addr : integer range 0 to N-1 := 0;
  signal rd_data : std_logic_vector(23 downto 0) := (others => '0');
  signal rd_en : std_logic := '0';
  signal wr_en : std_logic := '0';
  signal wr_addr : integer range 0 to N-1 := 0;
  signal wr_data : std_logic_vector(23 downto 0) := (others => '0');

  signal sr, sg, sb : integer range 0 to 131072 := 0;
  signal mr, mg, mb : integer range 0 to 255 := 0;
  -- |deviation| <=255, 512*255^2 fits signed(32 bits).
  signal c00,c01,c02,c11,c12,c22 : signed(31 downto 0) := (others=>'0');
  signal vr,vg,vb : signed(15 downto 0) := to_signed(4096,16);
  signal t0,t1,t2 : signed(63 downto 0) := (others=>'0');
  signal eig_round : integer range 0 to 7 := 0;
  signal ov, ol, dn : std_logic := '0';
  signal outreg : signed(31 downto 0) := (others=>'0');

  -- A signed 64-bit vector is rescaled by a shared power of two.
  -- This preserves its direction, without a hardware integer divider.
  function norm_shift(a,b,c : signed(63 downto 0)) return natural is
    variable m : signed(63 downto 0);
    variable av,bv,cv : signed(63 downto 0);
  begin
    if a(a'high)='1' then av := -a; else av := a; end if;
    if b(b'high)='1' then bv := -b; else bv := b; end if;
    if c(c'high)='1' then cv := -c; else cv := c; end if;
    m := av;
    if bv > m then m := bv; end if;
    if cv > m then m := cv; end if;
    for j in 0 to 50 loop
      if shift_right(m,j) <= to_signed(8191,64) then
        return j;
      end if;
    end loop;
    return 50;
  end function;

begin
  -- RAM: synchronous read and write, no array-wide reset.
  memory_p : process(clk)
  begin
    if rising_edge(clk) then
      if wr_en='1' then ram(wr_addr) <= wr_data; end if;
      if rd_en='1' then rd_data <= ram(rd_addr); end if;
    end if;
  end process;

  sample_out <= outreg;
  out_valid <= ov;
  out_last <= ol;
  done <= dn;
  busy <= '0' when st=COLLECT or st=FINISH else '1';

  process(clk)
    variable dr,dg,db : integer;
    variable q : natural;
    variable xx,yy,zz : signed(63 downto 0);
    variable dot : signed(63 downto 0);
  begin
    if rising_edge(clk) then
      ov <= '0'; ol <= '0'; dn <= '0';
      wr_en <= '0'; rd_en <= '0';
      if rst='1' then
        st <= COLLECT; wp <= 0; pos <= 0;
        sr<=0; sg<=0; sb<=0;
        mr<=0; mg<=0; mb<=0;
        c00<=(others=>'0'); c01<=(others=>'0'); c02<=(others=>'0');
        c11<=(others=>'0'); c12<=(others=>'0'); c22<=(others=>'0');
        eig_round<=0;
        vr<=to_signed(4096,16); vg<=to_signed(4096,16); vb<=to_signed(4096,16);
      else
        case st is
          when COLLECT =>
            if sample_valid='1' then
              wr_en <= '1'; wr_addr <= wp;
              wr_data <= rgb_r & rgb_g & rgb_b;
              sr <= sr + to_integer(unsigned(rgb_r));
              sg <= sg + to_integer(unsigned(rgb_g));
              sb <= sb + to_integer(unsigned(rgb_b));
              if wp=N-1 then
                wp <= 0; st <= MEAN_CALC;
              else wp <= wp+1;
              end if;
            end if;

          when MEAN_CALC =>
            mr <= sr/N; mg <= sg/N; mb <= sb/N;
            c00<=(others=>'0'); c01<=(others=>'0'); c02<=(others=>'0');
            c11<=(others=>'0'); c12<=(others=>'0'); c22<=(others=>'0');
            pos <= 0; st <= COV_ADDR;

          when COV_ADDR =>
            rd_addr <= pos; rd_en <= '1';
            st <= COV_WAIT;

          when COV_WAIT =>
            st <= COV_USE;

          when COV_USE =>
            dr := to_integer(unsigned(rd_data(23 downto 16))) - mr;
            dg := to_integer(unsigned(rd_data(15 downto 8))) - mg;
            db := to_integer(unsigned(rd_data(7 downto 0))) - mb;
            c00 <= c00 + to_signed(dr*dr,32);
            c01 <= c01 + to_signed(dr*dg,32);
            c02 <= c02 + to_signed(dr*db,32);
            c11 <= c11 + to_signed(dg*dg,32);
            c12 <= c12 + to_signed(dg*db,32);
            c22 <= c22 + to_signed(db*db,32);
            if pos=N-1 then st<=INIT_EIG;
            else pos<=pos+1; st<=COV_ADDR;
            end if;

          when INIT_EIG =>
            vr<=to_signed(4096,16); vg<=to_signed(4096,16); vb<=to_signed(4096,16);
            eig_round<=0; st<=EIG_CALC;

          when EIG_CALC =>
            xx := resize(c00*vr,64)+resize(c01*vg,64)+resize(c02*vb,64);
            yy := resize(c01*vr,64)+resize(c11*vg,64)+resize(c12*vb,64);
            zz := resize(c02*vr,64)+resize(c12*vg,64)+resize(c22*vb,64);
            t0<=xx; t1<=yy; t2<=zz;
            st<=EIG_NORM;

          when EIG_NORM =>
            if t0=to_signed(0,64) and t1=to_signed(0,64) and t2=to_signed(0,64) then
              -- No temporal RGB variation: use arbitrary axis but zero output.
              vr<=to_signed(4096,16); vg<=to_signed(0,16); vb<=to_signed(0,16);
            else
              q:=norm_shift(t0,t1,t2);
              vr<=resize(shift_right(t0,q),16);
              vg<=resize(shift_right(t1,q),16);
              vb<=resize(shift_right(t2,q),16);
            end if;
            if eig_round=7 then pos<=0; st<=EMIT_ADDR;
            else eig_round<=eig_round+1; st<=EIG_CALC;
            end if;

          when EMIT_ADDR =>
            rd_addr<=pos; rd_en<='1'; st<=EMIT_WAIT;

          when EMIT_WAIT =>
            st<=EMIT_USE;

          when EMIT_USE =>
            dr:=to_integer(unsigned(rd_data(23 downto 16)))-mr;
            dg:=to_integer(unsigned(rd_data(15 downto 8)))-mg;
            db:=to_integer(unsigned(rd_data(7 downto 0)))-mb;
            dot:=resize(to_signed(dr,16)*vr,64)
                +resize(to_signed(dg,16)*vg,64)
                +resize(to_signed(db,16)*vb,64);
            outreg<=resize(shift_right(dot,12),32);
            ov<='1';
            if pos=N-1 then ol<='1'; st<=FINISH;
            else pos<=pos+1; st<=EMIT_ADDR;
            end if;

          when FINISH =>
            dn<='1';
            -- Re-arm without extra reset for another independent window.
            st<=COLLECT; wp<=0;
            sr<=0; sg<=0; sb<=0;
        end case;
      end if;
    end if;
  end process;
end architecture;

-- Localisation experimentale ROI via statistiques RGB par trame.
-- Coordonnees en repere utile (RGB - OFFSET), pour extraction RGB ROI.
-- Aucun algorithme de reconnaissance faciale n'est garanti.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity skin_roi_tracker is
  generic (
    IMG_WIDTH : positive := 64;
    IMG_HEIGHT : positive := 64;
    COORD_BITS : positive := 10;
    OFFSET_X : natural := 3;
    OFFSET_Y : natural := 3;
    ROI_HALF_WIDTH : natural := 7;
    ROI_HEIGHT : positive := 9;
    MIN_SKIN : natural := 60
  );
  port (
    clk, rst, valid_in : in std_logic;
    rgb_in : in std_logic_vector(23 downto 0);
    xmin, xmax, ymin, ymax : out unsigned(COORD_BITS-1 downto 0);
    roi_valid, roi_found : out std_logic
  );
end entity;

architecture rtl of skin_roi_tracker is
  signal px : integer range 0 to IMG_WIDTH-1 := 0;
  signal py : integer range 0 to IMG_HEIGHT-1 := 0;
  signal skin_count : integer range 0 to IMG_WIDTH*IMG_HEIGHT := 0;
  signal min_x : integer range 0 to IMG_WIDTH-1 := IMG_WIDTH-1;
  signal max_x : integer range 0 to IMG_WIDTH-1 := 0;
  signal min_y : integer range 0 to IMG_HEIGHT-1 := IMG_HEIGHT-1;
  signal xmin_r, xmax_r, ymin_r, ymax_r : unsigned(COORD_BITS-1 downto 0) := (others=>'0');
  signal valid_r, found_r : std_logic := '0';
  function limit(v, lo, hi : integer) return integer is
  begin
    if v < lo then return lo;
    elsif v > hi then return hi;
    else return v;
    end if;
  end function;
begin
  xmin <= xmin_r; xmax <= xmax_r;
  ymin <= ymin_r; ymax <= ymax_r;
  roi_valid <= valid_r; roi_found <= found_r;
  process(clk)
    variable r,g,b : integer;
    variable candidate : boolean;
    variable n, l, h, t, cx, x0, x1, y0, y1 : integer;
  begin
    if rising_edge(clk) then
      if rst = '1' then
        px <= 0; py <= 0; skin_count <= 0;
        min_x <= IMG_WIDTH-1; max_x <= 0; min_y <= IMG_HEIGHT-1;
        valid_r <= '0'; found_r <= '0';
        xmin_r <= (others=>'0'); xmax_r <= (others=>'0');
        ymin_r <= (others=>'0'); ymax_r <= (others=>'0');
      else
        valid_r <= '0';
        if valid_in = '1' then
          r := to_integer(unsigned(rgb_in(23 downto 16)));
          g := to_integer(unsigned(rgb_in(15 downto 8)));
          b := to_integer(unsigned(rgb_in(7 downto 0)));
          -- Critere candidat peau, a calibrer pour l'eclairage du sujet.
          -- Fenetre de recherche limitee a la zone superieure centrale.
          candidate := (px >= IMG_WIDTH/6) and (px < 5*IMG_WIDTH/6) and
                       (py >= IMG_HEIGHT/8) and (py < 5*IMG_HEIGHT/8) and
                       (r > 60) and (g > 40) and (b > 25) and
                       (r > g + 2) and (g > b) and (r > b + 12);
          n := skin_count;
          l := min_x; h := max_x; t := min_y;
          if candidate then
            n := n + 1;
            if px < l then l := px; end if;
            if px > h then h := px; end if;
            if py < t then t := py; end if;
          end if;
          if px = IMG_WIDTH-1 and py = IMG_HEIGHT-1 then
            valid_r <= '1';
            if n >= integer(MIN_SKIN) and h > l + 8 then
              -- La ROI est centree autour du groupe de pixels candidats.
              cx := (l + h)/2 + 1;
              x0 := limit(cx - integer(ROI_HALF_WIDTH), integer(OFFSET_X), IMG_WIDTH-1);
              x1 := limit(cx + integer(ROI_HALF_WIDTH), integer(OFFSET_X), IMG_WIDTH-1);
              y0 := limit(t + 3, integer(OFFSET_Y), IMG_HEIGHT-1);
              y1 := limit(y0 + ROI_HEIGHT - 1, integer(OFFSET_Y), IMG_HEIGHT-1);
              xmin_r <= to_unsigned(x0 - integer(OFFSET_X), COORD_BITS);
              xmax_r <= to_unsigned(x1 - integer(OFFSET_X), COORD_BITS);
              ymin_r <= to_unsigned(y0 - integer(OFFSET_Y), COORD_BITS);
              ymax_r <= to_unsigned(y1 - integer(OFFSET_Y), COORD_BITS);
              found_r <= '1';
            else
              found_r <= '0';
            end if;
            px <= 0; py <= 0; skin_count <= 0;
            min_x <= IMG_WIDTH-1; max_x <= 0; min_y <= IMG_HEIGHT-1;
          else
            skin_count <= n;
            min_x <= l; max_x <= h; min_y <= t;
            if px = IMG_WIDTH-1 then px <= 0; py <= py+1;
            else px <= px+1; end if;
          end if;
        end if;
      end if;
    end if;
  end process;
end architecture;


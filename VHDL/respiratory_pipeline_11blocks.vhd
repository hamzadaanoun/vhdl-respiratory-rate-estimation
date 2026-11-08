library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity respiratory_pipeline_11blocks is
    generic (
        IMG_WIDTH       : positive := 640;
        IMG_HEIGHT      : positive := 480;
        COORD_BITS      : positive := 10;
        THRESHOLD_VALUE : integer := 100
    );
    port (
        clk         : in std_logic;
        rst         : in std_logic;
        rgb_in      : in std_logic_vector(23 downto 0);
        valid_in    : in std_logic;
        frame_start : in std_logic;

        mean_r_out : out std_logic_vector(7 downto 0);
        mean_g_out : out std_logic_vector(7 downto 0);
        mean_b_out : out std_logic_vector(7 downto 0);
        mean_valid_out : out std_logic;

        sample_count_out : out unsigned(9 downto 0);
        buffer_full_out : out std_logic;

        pca_sample_out : out signed(31 downto 0);
        pca_valid      : out std_logic;
        pca_last       : out std_logic;
        pca_done       : out std_logic;

        transfer_busy : out std_logic
    );
end entity;

architecture rtl of respiratory_pipeline_11blocks is

    signal s_mean_r, s_mean_g, s_mean_b :
        std_logic_vector(7 downto 0);

    signal s_mean_valid, s_has_pixels : std_logic;
    signal s_mean_busy : std_logic;

    signal s_count : unsigned(9 downto 0);
    signal s_full : std_logic;
    signal s_write_index : unsigned(8 downto 0);

    signal s_read_r, s_read_g, s_read_b :
        std_logic_vector(7 downto 0);

    signal s_read_valid : std_logic;

    signal s_read_enable : std_logic;
    signal s_read_address : unsigned(8 downto 0);

    signal s_buffer_rst : std_logic;
    signal s_buffer_input_valid : std_logic;

    signal s_pca_input_valid : std_logic;
    signal s_pca_busy : std_logic;
    signal s_pca_done : std_logic;

    type state_t is (
        WAIT_FILL,
        READ_REQUEST,
        READ_SEND,
        WAIT_PCA,
        RESET_BUFFER
    );

    signal state : state_t := WAIT_FILL;
    signal index_reg : unsigned(8 downto 0)
        := (others => '0');

    signal dummy_binary : std_logic_vector(7 downto 0);
    signal dummy_valid : std_logic;
    signal dummy_coord_min_x, dummy_coord_max_x :
        unsigned(COORD_BITS-1 downto 0);
    signal dummy_coord_min_y, dummy_coord_max_y :
        unsigned(COORD_BITS-1 downto 0);
    signal dummy_roi_min_x, dummy_roi_max_x :
        unsigned(COORD_BITS-1 downto 0);
    signal dummy_roi_min_y, dummy_roi_max_y :
        unsigned(COORD_BITS-1 downto 0);
    signal dummy_region_valid, dummy_region_found :
        std_logic;
    signal dummy_roi_valid, dummy_roi_found :
        std_logic;
    signal dummy_roi_rgb : std_logic_vector(23 downto 0);
    signal dummy_roi_pixel_valid : std_logic;
    signal dummy_pixel_count : unsigned(31 downto 0);

begin

    --------------------------------------------------
    -- BLOCS 1 A 9
    --------------------------------------------------

    U_PIPELINE_9 :
        entity work.image_processing_pipeline_9blocks
        generic map (
            IMG_WIDTH => IMG_WIDTH,
            IMG_HEIGHT => IMG_HEIGHT,
            COORD_BITS => COORD_BITS,
            THRESHOLD_VALUE => THRESHOLD_VALUE
        )
        port map (
            clk => clk,
            rst => rst,
            rgb_in => rgb_in,
            valid_in => valid_in,
            frame_start => frame_start,

            binary_out => dummy_binary,
            valid_out => dummy_valid,

            xmin => dummy_coord_min_x,
            xmax => dummy_coord_max_x,
            ymin => dummy_coord_min_y,
            ymax => dummy_coord_max_y,
            region_valid => dummy_region_valid,
            region_found => dummy_region_found,

            roi_xmin => dummy_roi_min_x,
            roi_xmax => dummy_roi_max_x,
            roi_ymin => dummy_roi_min_y,
            roi_ymax => dummy_roi_max_y,
            roi_valid => dummy_roi_valid,
            roi_found => dummy_roi_found,

            roi_rgb_out => dummy_roi_rgb,
            roi_pixel_valid => dummy_roi_pixel_valid,

            mean_r => s_mean_r,
            mean_g => s_mean_g,
            mean_b => s_mean_b,

            mean_pixel_count => dummy_pixel_count,
            mean_valid => s_mean_valid,
            roi_has_pixels => s_has_pixels,
            mean_busy => s_mean_busy
        );

    mean_r_out <= s_mean_r;
    mean_g_out <= s_mean_g;
    mean_b_out <= s_mean_b;
    mean_valid_out <= s_mean_valid;

    --------------------------------------------------
    -- CONTROLE DU TAMPON RGB
    --------------------------------------------------

    s_buffer_rst <= '1'
        when rst = '1' or state = RESET_BUFFER
        else '0';

    -- Ne pas stocker de trames vides.
    -- Geler les ecritures pendant la PCA.
    s_buffer_input_valid <=
        s_mean_valid and s_has_pixels
        when state = WAIT_FILL
        else '0';

    --------------------------------------------------
    -- BLOC 10 : TAMPON RGB
    --------------------------------------------------

    U_BUFFER :
        entity work.rgb_temporal_buffer
        port map (
            clk => clk,
            rst => s_buffer_rst,

            mean_r => s_mean_r,
            mean_g => s_mean_g,
            mean_b => s_mean_b,
            mean_valid => s_buffer_input_valid,

            read_enable => s_read_enable,
            read_address => s_read_address,

            read_r => s_read_r,
            read_g => s_read_g,
            read_b => s_read_b,
            read_valid => s_read_valid,

            write_index => s_write_index,
            sample_count => s_count,
            buffer_full => s_full
        );

    sample_count_out <= s_count;
    buffer_full_out <= s_full;

    --------------------------------------------------
    -- LECTURE SEQUENTIELLE DU TAMPON
    --------------------------------------------------

    s_read_address <= index_reg;

    s_read_enable <= '1'
        when state = READ_REQUEST
        else '0';

    -- READ_SEND dure jusqu'a read_valid.
    -- La PCA accepte la donnee au front suivant.
    s_pca_input_valid <= s_read_valid
        when state = READ_SEND
        else '0';

    --------------------------------------------------
    -- BLOC 11 : PCA
    --------------------------------------------------

    U_PCA :
        entity work.pca_rgb
        port map (
            clk => clk,
            rst => rst,

            rgb_r => s_read_r,
            rgb_g => s_read_g,
            rgb_b => s_read_b,
            sample_valid => s_pca_input_valid,

            sample_out => pca_sample_out,
            out_valid => pca_valid,
            out_last => pca_last,

            busy => s_pca_busy,
            done => s_pca_done
        );

    pca_done <= s_pca_done;

    transfer_busy <= '0'
        when state = WAIT_FILL
        else '1';

    --------------------------------------------------
    -- CONTROLEUR : BUFFER -> PCA
    --------------------------------------------------

    process(clk)
    begin
        if rising_edge(clk) then

            if rst = '1' then
                state <= WAIT_FILL;
                index_reg <= (others => '0');

            else
                case state is

                    when WAIT_FILL =>
                        if s_full = '1' then
                            index_reg <= (others => '0');
                            state <= READ_REQUEST;
                        end if;

                    when READ_REQUEST =>
                        state <= READ_SEND;

                    when READ_SEND =>
                        if s_read_valid = '1' then
                            if index_reg =
                                to_unsigned(511,9) then
                                state <= WAIT_PCA;
                            else
                                index_reg <= index_reg + 1;
                                state <= READ_REQUEST;
                            end if;
                        end if;

                    when WAIT_PCA =>
                        if s_pca_done = '1' then
                            state <= RESET_BUFFER;
                        end if;

                    when RESET_BUFFER =>
                        index_reg <= (others => '0');
                        state <= WAIT_FILL;

                end case;
            end if;
        end if;
    end process;

end architecture rtl;

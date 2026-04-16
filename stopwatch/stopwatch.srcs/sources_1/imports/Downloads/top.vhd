-- top.vhd
-- Top-level: Stopky na Nexys A7 (Artix-7 XC7A50T)
--
-- Port mapa:
--   CLK100MHZ  : 100 MHz systemovy hodinovy signal
--   CPU_RESETN : aktivni nizky reset (tlacitko)
--
--   BTNL  (leve)    = START
--   BTNC  (stred)   = PAUSE
--   BTNR  (prave)   = STOP (prvni stisk) / CLEAR + RESET LAP (druhy stisk)
--   BTND  (spodni)  = LAP (zapis mezicasu, jen v RUNNING)
--
--   SW[2:0]  : vyber mezicasu (0-4 platne, 5-7 zobrazi slot 4)
--   SW[15:3] : nepouzito
--
--   LED[4:0]  : indikace ulozenych mezicasu (bit 0 = slot 0, bit 4 = slot 4)
--   LED[15:5] : nepouzito
--
--   LED17_R/G/B : stavova RGB LED (R=zastaveno/chyba, G=bezi, B=idle/pauza)
--
--   SEG, DP, AN : 7-segmentovy displej

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity top is
    port (
        CLK100MHZ  : in  std_logic;
        CPU_RESETN : in  std_logic;   -- active low

        -- Tlacitka
        BTNL       : in  std_logic;   -- START
        BTNC       : in  std_logic;   -- PAUSE
        BTNR       : in  std_logic;   -- STOP / CLEAR+RESET LAP
        BTND       : in  std_logic;   -- LAP

        -- Spinace
        SW         : in  std_logic_vector(15 downto 0);

        -- LEDs
        LED        : out std_logic_vector(15 downto 0);

        -- RGB LED17 (stavova)
        LED17_R    : out std_logic;
        LED17_G    : out std_logic;
        LED17_B    : out std_logic;

        -- 7-segmentovy displej
        SEG        : out std_logic_vector(6 downto 0);
        DP         : out std_logic;
        AN         : out std_logic_vector(7 downto 0)
    );
end top;

architecture rtl of top is

    signal rst : std_logic;

    -- Debounced signaly
    signal btn_l_lv, btn_l_p : std_logic;
    signal btn_c_lv, btn_c_p : std_logic;
    signal btn_r_lv, btn_r_p : std_logic;
    signal btn_d_lv, btn_d_p : std_logic;

    -- Counter
    signal cnt_enable   : std_logic;
    signal cnt_rst      : std_logic;
    signal cnt_max      : std_logic;
    signal live_sec_t   : std_logic_vector(3 downto 0);
    signal live_sec_u   : std_logic_vector(3 downto 0);
    signal live_cs_t    : std_logic_vector(3 downto 0);
    signal live_cs_u    : std_logic_vector(3 downto 0);

    -- Lap memory
    signal lap_write    : std_logic;
    signal lap_rst      : std_logic;
    signal lap_sec_t    : std_logic_vector(3 downto 0);
    signal lap_sec_u    : std_logic_vector(3 downto 0);
    signal lap_cs_t     : std_logic_vector(3 downto 0);
    signal lap_cs_u     : std_logic_vector(3 downto 0);
    signal lap_saved    : std_logic_vector(4 downto 0);  -- 5 slotu

    -- Control
    signal show_lap     : std_logic;
    signal end_flag     : std_logic;
    signal error_flag   : std_logic;
    signal led_r        : std_logic;
    signal led_g        : std_logic;
    signal led_b        : std_logic;

    -- SW debounce (SW[2:0] pro vyber mezicasu)
    signal sw_deb_lv    : std_logic_vector(4 downto 0);

    -- Komponenty
    component debouncer
        generic (
            CLK_FREQ_HZ  : integer := 100_000_000;
            DEBOUNCE_MS  : integer := 20
        );
        port (
            clk       : in  std_logic;
            rst       : in  std_logic;
            sig_in    : in  std_logic;
            level_out : out std_logic;
            pulse_out : out std_logic
        );
    end component;

    component counter
        generic (
            CLK_FREQ_HZ : integer := 100_000_000
        );
        port (
            clk         : in  std_logic;
            rst         : in  std_logic;
            enable      : in  std_logic;
            sec_tens    : out std_logic_vector(3 downto 0);
            sec_units   : out std_logic_vector(3 downto 0);
            cs_tens     : out std_logic_vector(3 downto 0);
            cs_units    : out std_logic_vector(3 downto 0);
            tick_100hz  : out std_logic;
            max_reached : out std_logic
        );
    end component;

    component lap_memory
        port (
        clk          : in  std_logic;
        rst          : in  std_logic;
        -- Zapis mezicasu
        write_en     : in  std_logic;   -- pulz pri stisku BTND (LAP)
        -- Reset vsech slotu (pulz od STOP tlacitka ze stavu STOPPED)
        lap_rst      : in  std_logic;
        sec_tens_in  : in  std_logic_vector(3 downto 0);
        sec_units_in : in  std_logic_vector(3 downto 0);
        cs_tens_in   : in  std_logic_vector(3 downto 0);
        cs_units_in  : in  std_logic_vector(3 downto 0);
        -- Cteni (pro zobrazeni) - SW[2:0], platne 0-4
        read_addr    : in  std_logic_vector(4 downto 0);
        sec_tens_out : out std_logic_vector(3 downto 0);
        sec_units_out: out std_logic_vector(3 downto 0);
        cs_tens_out  : out std_logic_vector(3 downto 0);
        cs_units_out : out std_logic_vector(3 downto 0);
        -- Status: 5 bitu (jeden per slot)
        lap_saved_leds : out std_logic_vector(4 downto 0)
    );
    end component;

    component stopwatch_ctrl
        port (
        clk          : in  std_logic;
        rst          : in  std_logic;

        -- Debounced tlacitka (pulse_out)
        btn_left_p   : in  std_logic;   -- START
        btn_mid_p    : in  std_logic;   -- PAUSE
        btn_right_p  : in  std_logic;   -- STOP / CLEAR
        btn_bot_p    : in  std_logic;   -- LAP

        -- Spinace (level, debounced)
        sw           : in  std_logic_vector(4 downto 0);

        -- Counter interface
        cnt_enable   : out std_logic;
        cnt_rst      : out std_logic;
        cnt_max      : in  std_logic;   -- autostop signal pri 90s

        -- Lap memory interface
        lap_write    : out std_logic;   -- pulz: uloz mezicas
        lap_rst      : out std_logic;   -- pulz: vymaz vsechny mezicasy (2. stisk STOP)

        -- Display flags
        show_lap     : out std_logic;   -- '1' = zobraz mezicas na pravem panelu
        end_flag     : out std_logic;   -- '1' = zobraz "End" (dosazeno 90s)

        -- RGB LED17 (active high na Nexys A7)
        led_r        : out std_logic;
        led_g        : out std_logic;
        led_b        : out std_logic;

        -- Error flag (pro zobrazeni Err na displeji)
        error_flag   : out std_logic
    );
    end component;

    component seg7_display
        generic (
            CLK_FREQ_HZ : integer := 100_000_000;
            MUX_FREQ_HZ : integer := 1000
        );
        port (
            clk          : in  std_logic;
            rst          : in  std_logic;
            live_sec_t   : in  std_logic_vector(3 downto 0);
            live_sec_u   : in  std_logic_vector(3 downto 0);
            live_cs_t    : in  std_logic_vector(3 downto 0);
            live_cs_u    : in  std_logic_vector(3 downto 0);
            lap_sec_t    : in  std_logic_vector(3 downto 0);
            lap_sec_u    : in  std_logic_vector(3 downto 0);
            lap_cs_t     : in  std_logic_vector(3 downto 0);
            lap_cs_u     : in  std_logic_vector(3 downto 0);
            show_lap     : in  std_logic;
            error_flag   : in  std_logic;
            end_flag     : in  std_logic;
            seg          : out std_logic_vector(6 downto 0);
            dp           : out std_logic;
            an           : out std_logic_vector(7 downto 0)
        );
    end component;

begin

    rst <= not CPU_RESETN;

    -- -------------------------------------------------------------------------
    -- Debouncer pro tlacitka
    -- -------------------------------------------------------------------------
    u_deb_l : debouncer
        generic map (CLK_FREQ_HZ => 100_000_000, DEBOUNCE_MS => 20)
        port map (clk => CLK100MHZ, rst => rst, sig_in => BTNL,
                  level_out => btn_l_lv, pulse_out => btn_l_p);

    u_deb_c : debouncer
        generic map (CLK_FREQ_HZ => 100_000_000, DEBOUNCE_MS => 20)
        port map (clk => CLK100MHZ, rst => rst, sig_in => BTNC,
                  level_out => btn_c_lv, pulse_out => btn_c_p);

    u_deb_r : debouncer
        generic map (CLK_FREQ_HZ => 100_000_000, DEBOUNCE_MS => 20)
        port map (clk => CLK100MHZ, rst => rst, sig_in => BTNR,
                  level_out => btn_r_lv, pulse_out => btn_r_p);

    u_deb_d : debouncer
        generic map (CLK_FREQ_HZ => 100_000_000, DEBOUNCE_MS => 20)
        port map (clk => CLK100MHZ, rst => rst, sig_in => BTND,
                  level_out => btn_d_lv, pulse_out => btn_d_p);

    -- Spinace SW[2:0] (debounce 5ms)
    u_deb_sw0 : debouncer
        generic map (CLK_FREQ_HZ => 100_000_000, DEBOUNCE_MS => 5)
        port map (clk => CLK100MHZ, rst => rst, sig_in => SW(0),
                  level_out => sw_deb_lv(0), pulse_out => open);

    u_deb_sw1 : debouncer
        generic map (CLK_FREQ_HZ => 100_000_000, DEBOUNCE_MS => 5)
        port map (clk => CLK100MHZ, rst => rst, sig_in => SW(1),
                  level_out => sw_deb_lv(1), pulse_out => open);

    u_deb_sw2 : debouncer
        generic map (CLK_FREQ_HZ => 100_000_000, DEBOUNCE_MS => 5)
        port map (clk => CLK100MHZ, rst => rst, sig_in => SW(2),
                  level_out => sw_deb_lv(2), pulse_out => open);
                  
    u_deb_sw3 : debouncer
        generic map (CLK_FREQ_HZ => 100_000_000, DEBOUNCE_MS => 5)
        port map (clk => CLK100MHZ, rst => rst, sig_in => SW(3),
                  level_out => sw_deb_lv(3), pulse_out => open);

    u_deb_sw4 : debouncer
        generic map (CLK_FREQ_HZ => 100_000_000, DEBOUNCE_MS => 5)
        port map (clk => CLK100MHZ, rst => rst, sig_in => SW(4),
                  level_out => sw_deb_lv(4), pulse_out => open);

    -- -------------------------------------------------------------------------
    -- Counter
    -- -------------------------------------------------------------------------
    u_counter : counter
        generic map (CLK_FREQ_HZ => 100_000_000)
        port map (
            clk         => CLK100MHZ,
            rst         => cnt_rst,
            enable      => cnt_enable,
            sec_tens    => live_sec_t,
            sec_units   => live_sec_u,
            cs_tens     => live_cs_t,
            cs_units    => live_cs_u,
            tick_100hz  => open,
            max_reached => cnt_max
        );

    -- -------------------------------------------------------------------------
    -- Lap memory (5 slotu)
    -- -------------------------------------------------------------------------
    u_lap_mem : lap_memory
        port map (
            clk           => CLK100MHZ,
            rst           => rst,
            write_en      => lap_write,
            lap_rst       => lap_rst,
            sec_tens_in   => live_sec_t,
            sec_units_in  => live_sec_u,
            cs_tens_in    => live_cs_t,
            cs_units_in   => live_cs_u,
            read_addr     => sw_deb_lv,
            sec_tens_out  => lap_sec_t,
            sec_units_out => lap_sec_u,
            cs_tens_out   => lap_cs_t,
            cs_units_out  => lap_cs_u,
            lap_saved_leds => lap_saved
        );

    -- -------------------------------------------------------------------------
    -- FSM Rizeni
    -- -------------------------------------------------------------------------
    u_ctrl : stopwatch_ctrl
        port map (
            clk         => CLK100MHZ,
            rst         => rst,
            btn_left_p  => btn_l_p,
            btn_mid_p   => btn_c_p,
            btn_right_p => btn_r_p,
            btn_bot_p   => btn_d_p,
            sw          => sw_deb_lv,
            cnt_enable  => cnt_enable,
            cnt_rst     => cnt_rst,
            cnt_max     => cnt_max,
            lap_write   => lap_write,
            lap_rst     => lap_rst,
            show_lap    => show_lap,
            end_flag    => end_flag,
            led_r       => led_r,
            led_g       => led_g,
            led_b       => led_b,
            error_flag  => error_flag
        );

    -- -------------------------------------------------------------------------
    -- 7-Seg displej
    -- -------------------------------------------------------------------------
    u_display : seg7_display
        generic map (CLK_FREQ_HZ => 100_000_000, MUX_FREQ_HZ => 1000)
        port map (
            clk         => CLK100MHZ,
            rst         => rst,
            live_sec_t  => live_sec_t,
            live_sec_u  => live_sec_u,
            live_cs_t   => live_cs_t,
            live_cs_u   => live_cs_u,
            lap_sec_t   => lap_sec_t,
            lap_sec_u   => lap_sec_u,
            lap_cs_t    => lap_cs_t,
            lap_cs_u    => lap_cs_u,
            show_lap    => show_lap,
            error_flag  => error_flag,
            end_flag    => end_flag,
            seg         => SEG,
            dp          => DP,
            an          => AN
        );

    -- -------------------------------------------------------------------------
    -- LED vystupy
    -- LED[4:0]  = indikace ulozenych mezicasu (5 slotu)
    -- LED[15:5] = nepouzito
    -- -------------------------------------------------------------------------
    LED(4 downto 0)  <= lap_saved;
    LED(15 downto 5) <= (others => '0');

    LED17_R <= led_r;
    LED17_G <= led_g;
    LED17_B <= led_b;

end rtl;

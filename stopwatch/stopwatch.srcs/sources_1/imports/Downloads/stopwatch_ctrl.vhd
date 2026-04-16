-- stopwatch_ctrl.vhd
-- FSM rizeni stopek pro Nexys A7
--
-- Stavy:
--   IDLE    : cekani (cas = 0), modra LED (pauza/idle)
--   RUNNING : citac bezi, zelena LED
--   PAUSED  : citac zastaven, modra LED
--   STOPPED : zastaven s casem, cervena LED (DONE)
--   ERROR   : chyba - vice spinacu najednou
--
-- Tlacitka (po debouncingu, aktivni pulzy):
--   btn_left   : START  (IDLE->RUNNING, PAUSED->RUNNING)
--   btn_mid    : PAUSE  (RUNNING->PAUSED)
--   btn_right  : STOP / 2x CLEAR
--                  prvni stisk: RUNNING/PAUSED -> STOPPED
--                  druhy stisk ze STOPPED: -> IDLE (clear)
--   btn_bot    : LAP (ulozi mezicas, jen v RUNNING)
--
-- Spinace SW[2:0]: vyber mezicasu pro zobrazeni
-- Podminka chyby: vice nez 1 spinac aktivni soucasne

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity stopwatch_ctrl is
    port (
        clk          : in  std_logic;
        rst          : in  std_logic;

        -- Debounced tlacitka (pulse_out)
        btn_left_p   : in  std_logic;   -- START
        btn_mid_p    : in  std_logic;   -- PAUSE
        btn_right_p  : in  std_logic;   -- STOP / CLEAR
        btn_bot_p    : in  std_logic;   -- LAP

        -- Spinace (level)
        sw           : in  std_logic_vector(2 downto 0);

        -- Counter interface
        cnt_enable   : out std_logic;
        cnt_rst      : out std_logic;
        cnt_max      : in  std_logic;   -- autostop signal

        -- Lap memory interface
        lap_write    : out std_logic;

        -- Display select: '0' = zivý cas, '1' = mezicas
        show_lap     : out std_logic;

        -- RGB LED17 (active high na Nexys A7: RGB = R, G, B)
        led_r        : out std_logic;
        led_g        : out std_logic;
        led_b        : out std_logic;

        -- Error flag (pro zobrazeni na display / LED)
        error_flag   : out std_logic
    );
end stopwatch_ctrl;

architecture rtl of stopwatch_ctrl is

    type state_t is (IDLE, RUNNING, PAUSED, STOPPED, ERROR_ST);
    signal state      : state_t := IDLE;
    signal stop_cnt   : integer range 0 to 1 := 0;  -- pocita stisky STOP pro 2x clear

    -- Detekce vice spinacu
    signal sw_err     : std_logic;
    -- Pocet aktivnich spinacu
    signal sw_count   : integer range 0 to 3;

    signal prev_state_before_err : state_t := IDLE;

begin

    -- Pocet aktivnich spinacu
    process(sw)
        variable cnt_sw : integer range 0 to 3;
    begin
        cnt_sw := 0;
        for i in 0 to 2 loop
            if sw(i) = '1' then
                cnt_sw := cnt_sw + 1;
            end if;
        end loop;
        sw_count <= cnt_sw;
    end process;

    sw_err <= '1' when sw_count > 1 else '0';

    -- Hlavni FSM
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state      <= IDLE;
                stop_cnt   <= 0;
                lap_write  <= '0';
            else
                lap_write <= '0';  -- default

                case state is

                    -- -------------------------------------------------------
                    when IDLE =>
                        stop_cnt <= 0;
                        if sw_err = '1' then
                            prev_state_before_err <= IDLE;
                            state <= ERROR_ST;
                        elsif btn_left_p = '1' then
                            state <= RUNNING;
                        end if;

                    -- -------------------------------------------------------
                    when RUNNING =>
                        if cnt_max = '1' then
                            state    <= STOPPED;
                            stop_cnt <= 1;  -- uz zastaven, 1x dalsi stisk = clear
                        elsif sw_err = '1' then
                            prev_state_before_err <= RUNNING;
                            state <= ERROR_ST;
                        elsif btn_mid_p = '1' then
                            state <= PAUSED;
                        elsif btn_right_p = '1' then
                            state    <= STOPPED;
                            stop_cnt <= 0;
                        elsif btn_bot_p = '1' then
                            lap_write <= '1';
                        end if;

                    -- -------------------------------------------------------
                    when PAUSED =>
                        if sw_err = '1' then
                            prev_state_before_err <= PAUSED;
                            state <= ERROR_ST;
                        elsif btn_left_p = '1' then
                            state <= RUNNING;
                        elsif btn_right_p = '1' then
                            state    <= STOPPED;
                            stop_cnt <= 0;
                        end if;

                    -- -------------------------------------------------------
                    when STOPPED =>
                        if sw_err = '1' then
                            prev_state_before_err <= STOPPED;
                            state <= ERROR_ST;
                        elsif btn_right_p = '1' then
                            if stop_cnt = 0 then
                                stop_cnt <= 1;
                            else
                                -- Druhy stisk -> CLEAR -> IDLE
                                state    <= IDLE;
                                stop_cnt <= 0;
                            end if;
                        end if;

                    -- -------------------------------------------------------
                    when ERROR_ST =>
                        -- Pockat az se vsechny spinace uvolni
                        if sw_err = '0' then
                            state <= prev_state_before_err;
                        end if;

                    when others =>
                        state <= IDLE;

                end case;
            end if;
        end if;
    end process;

    -- Vystupni logika
    process(state, sw, sw_count)
    begin
        -- Defaulty
        cnt_enable  <= '0';
        cnt_rst     <= '0';
        led_r       <= '0';
        led_g       <= '0';
        led_b       <= '0';
        error_flag  <= '0';
        show_lap    <= '0';

        case state is
            when IDLE =>
                cnt_rst    <= '1';
                led_b      <= '1';   -- modra = idle/ready
                -- Zobraz mezicas pokud je prave jeden spinac aktivni
                if sw_count = 1 then
                    show_lap <= '1';
                end if;

            when RUNNING =>
                cnt_enable <= '1';
                led_g      <= '1';   -- zelena = bezi
                if sw_count = 1 then
                    show_lap <= '1';
                end if;

            when PAUSED =>
                led_b      <= '1';   -- modra = pauza
                if sw_count = 1 then
                    show_lap <= '1';
                end if;

            when STOPPED =>
                led_r      <= '1';   -- cervena = konec/done
                if sw_count = 1 then
                    show_lap <= '1';
                end if;

            when ERROR_ST =>
                error_flag <= '1';
                led_r      <= '1';
                led_g      <= '0';
                led_b      <= '0';

        end case;
    end process;

end rtl;

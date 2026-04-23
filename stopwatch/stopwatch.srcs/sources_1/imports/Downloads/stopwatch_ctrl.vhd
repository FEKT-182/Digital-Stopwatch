-- stopwatch_ctrl.vhd
-- FSM rizeni stopek pro Nexys A7
--
-- Stavy:
--   IDLE    : cekani (cas = 0), modra LED (idle/ready)
--   RUNNING : citac bezi, zelena LED
--   PAUSED  : citac zastaven, modra LED
--   STOPPED : zastaven s casem (nebo dosazeno 90s), cervena LED
--   ERROR   : chyba - vice spinacu najednou (blikajici Err na displeji)
--
-- Tlacitka (po debouncingu, aktivni pulzy):
--   btn_left   : START  (IDLE->RUNNING, PAUSED->RUNNING)
--   btn_mid    : PAUSE  (RUNNING->PAUSED)
--   btn_right  : STOP / CLEAR+RESET LAP
--                  prvni stisk (ze RUNNING/PAUSED): -> STOPPED
--                  druhy stisk (ze STOPPED): vymaze cas + mezicasy -> IDLE
--   btn_bot    : LAP (ulozi mezicas, jen v RUNNING)
--
-- Spinace SW[2:0]: vyber mezicasu 0-4 pro zobrazeni
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
end stopwatch_ctrl;

architecture rtl of stopwatch_ctrl is

    type state_t is (IDLE, RUNNING, PAUSED, STOPPED, ERROR_ST);
    signal state      : state_t := IDLE;
    signal stop_cnt   : integer range 0 to 1 := 0;
    signal timed_out  : std_logic := '0';  -- '1' kdyz citac dosahl 90s

    -- Detekce vice spinacu
    signal sw_err     : std_logic;
    signal sw_count   : integer range 0 to 5;

    signal prev_state_before_err : state_t := IDLE;

begin

    -- Pocet aktivnich spinacu
    process(sw)
        variable cnt_sw : integer range 0 to 5;
    begin
        cnt_sw := 0;
        for i in 0 to 4 loop
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
                lap_rst    <= '0';
                timed_out  <= '0';
            else
                lap_write <= '0';  -- default: nepsat
                lap_rst   <= '0';  -- default: neresetovat

                case state is

                    -- -------------------------------------------------------
                    when IDLE =>
                        stop_cnt  <= 0;
                        timed_out <= '0';
                        if sw_err = '1' then
                            prev_state_before_err <= IDLE;
                            state <= ERROR_ST;
                        elsif btn_left_p = '1' then
                            state <= RUNNING;
                        end if;

                    -- -------------------------------------------------------
                    when RUNNING =>
                        if cnt_max = '1' then
                            -- Autostop pri 90s
                            timed_out <= '1';
                            state     <= STOPPED;
                            stop_cnt  <= 0;  -- prvni "stop" je automaticky, potrebujeme 1 stisk pro clear
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
                        elsif btn_bot_p = '1' then
                            lap_write <= '1';
                        end if;

                    -- -------------------------------------------------------
                    when STOPPED =>
                        if sw_err = '1' then
                            prev_state_before_err <= STOPPED;
                            state <= ERROR_ST;
                        elsif btn_bot_p = '1' then
                            lap_write <= '1';
                        elsif btn_right_p = '1' then
                            if stop_cnt = 0 then
                                -- Prvni stisk STOP ze STOPPED: jen posun pocitadla
                                stop_cnt <= 1;
                            else
                                -- Druhy stisk: clear cas + reset mezicasy -> IDLE
                                lap_rst   <= '1';  -- pulz pro lap_memory reset
                                timed_out <= '0';
                                state     <= IDLE;
                                stop_cnt  <= 0;
                            end if;
                        end if;

                    -- -------------------------------------------------------
                    when ERROR_ST =>
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
    process(state, sw_count, timed_out)
    begin
        -- Defaulty
        cnt_enable  <= '0';
        cnt_rst     <= '0';
        led_r       <= '0';
        led_g       <= '0';
        led_b       <= '0';
        error_flag  <= '0';
        end_flag    <= '0';
        show_lap    <= '0';

        case state is
            when IDLE =>
                cnt_rst    <= '1';   -- drz citac na nule
                led_b      <= '1';   -- modra = idle/ready
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
                if timed_out = '1' then
                    end_flag <= '1'; -- zobraz "End" kdyz dosazeno 90s
                end if;
                if sw_count = 1 then
                    show_lap <= '1';
                end if;

            when ERROR_ST =>
                error_flag <= '1';
                led_r      <= '1';

        end case;
    end process;

end rtl;

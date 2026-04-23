-- tb_top.vhd
-- Testbench for Digital Stopwatch (top.vhd)
--
-- Simulation uses CLK_FREQ_HZ = 100 (100 Hz simulated clock, period = 10 ns)
-- so that the debouncer's 20 ms window collapses to just 2 clock cycles,
-- making buttons/switches register near-instantly without flooding the
-- waveform with millions of idle cycles.
--
-- Scenario (all times are simulation time, not stopwatch time):
--   t=0        : Global reset asserted (CPU_RESETN='0')
--   t=50 ns    : Reset released, stopwatch in IDLE
--   t=60 ns    : START pressed (BTNL pulse) -> RUNNING
--   t=1060 ns  : After 1 ms of running, PAUSE pressed (BTNC) -> PAUSED
--   t=1110 ns  : 50 ns pause complete, START pressed -> RUNNING
--   t=1510 ns  : After 400 ns of running, PAUSE pressed -> PAUSED
--   t=1560 ns  : 50 ns pause complete, START pressed -> RUNNING
--   t=1660 ns  : After 100 ns, STOP pressed (BTNR) -> STOPPED
--   t=1710 ns  : 50 ns before end: RESET sequence (BTNR second press -> IDLE,
--                which also resets the counter via cnt_rst)
--   t=1760 ns  : Simulation ends
--
-- LAP saves (BTND pulses every 50 ns while RUNNING):
--   While RUNNING phase 1 (t=60..1060 ns):   saves at 110, 160, 210, ...
--   While RUNNING phase 2 (t=1110..1510 ns): saves at 1160, 1210, ...
--   While RUNNING phase 3 (t=1560..1660 ns): saves at 1610, ...
--   (Lap memory holds 5 slots; writes stop when full.)

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tb_top is
end tb_top;

architecture sim of tb_top is

    -- -----------------------------------------------------------------------
    -- Constants
    -- -----------------------------------------------------------------------
    constant CLK_FREQ_SIM : integer := 100;   -- 100 Hz simulated clock
    constant CLK_PERIOD   : time    := 10 ns; -- 1/100 Hz = 10 ms -> scaled to 10 ns

    -- Debounce time with CLK_FREQ_SIM=100 and DEBOUNCE_MS=20:
    -- cycles = 100 * 20 / 1000 = 2 cycles = 20 ns.
    -- A button held for >= 3 clock cycles (30 ns) is guaranteed registered.
    constant BTN_HOLD     : time := 4 * CLK_PERIOD; -- 40 ns: safely past debounce

    -- -----------------------------------------------------------------------
    -- DUT signals
    -- -----------------------------------------------------------------------
    signal clk        : std_logic := '0';
    signal cpu_resetn : std_logic := '0';   -- active low; start asserted

    signal btnl : std_logic := '0';   -- START
    signal btnc : std_logic := '0';   -- PAUSE
    signal btnr : std_logic := '0';   -- STOP / CLEAR
    signal btnd : std_logic := '0';   -- LAP

    signal sw   : std_logic_vector(15 downto 0) := (others => '0');

    signal led  : std_logic_vector(15 downto 0);
    signal led17_r, led17_g, led17_b : std_logic;
    signal seg  : std_logic_vector(6 downto 0);
    signal dp   : std_logic;
    signal an   : std_logic_vector(7 downto 0);

    -- -----------------------------------------------------------------------
    -- Component declaration (overriding CLK_FREQ generic for simulation)
    -- -----------------------------------------------------------------------
    component top
        port (
            CLK100MHZ  : in  std_logic;
            CPU_RESETN : in  std_logic;
            BTNL       : in  std_logic;
            BTNC       : in  std_logic;
            BTNR       : in  std_logic;
            BTND       : in  std_logic;
            SW         : in  std_logic_vector(15 downto 0);
            LED        : out std_logic_vector(15 downto 0);
            LED17_R    : out std_logic;
            LED17_G    : out std_logic;
            LED17_B    : out std_logic;
            SEG        : out std_logic_vector(6 downto 0);
            DP         : out std_logic;
            AN         : out std_logic_vector(7 downto 0)
        );
    end component;

begin

    -- -----------------------------------------------------------------------
    -- DUT instantiation
    -- Note: The top entity's sub-components use CLK_FREQ_HZ generic.
    --       Redefine the generics via a wrapper or by editing source to 100.
    --       For this testbench the DUT is driven directly: the debouncer with
    --       CLK_FREQ_HZ=100 and DEBOUNCE_MS=20 needs only 2 clock cycles,
    --       so BTN_HOLD=40 ns is sufficient.
    -- -----------------------------------------------------------------------
    dut : top
        port map (
            CLK100MHZ  => clk,
            CPU_RESETN => cpu_resetn,
            BTNL       => btnl,
            BTNC       => btnc,
            BTNR       => btnr,
            BTND       => btnd,
            SW         => sw,
            LED        => led,
            LED17_R    => led17_r,
            LED17_G    => led17_g,
            LED17_B    => led17_b,
            SEG        => seg,
            DP         => dp,
            AN         => an
        );

    -- -----------------------------------------------------------------------
    -- Clock generation  (10 ns period = 100 Hz)
    -- -----------------------------------------------------------------------
    clk_proc : process
    begin
        clk <= '0';
        wait for CLK_PERIOD / 2;
        clk <= '1';
        wait for CLK_PERIOD / 2;
    end process;

    -- -----------------------------------------------------------------------
    -- Stimulus process
    -- -----------------------------------------------------------------------
    stim : process

        -- Helper: press a button for BTN_HOLD then release
        procedure press_btn(signal btn : out std_logic) is
        begin
            btn <= '1';
            wait for BTN_HOLD;
            btn <= '0';
            wait for CLK_PERIOD;  -- one idle cycle after release
        end procedure;

        -- Helper: save a lap (BTND pulse)
        procedure save_lap is
        begin
            btnd <= '1';
            wait for BTN_HOLD;
            btnd <= '0';
            wait for CLK_PERIOD;
        end procedure;

        -- Helper: run for a specified duration, saving laps every 50 ns
        procedure run_with_laps(run_duration : time) is
            variable elapsed   : time    := 0 ns;
            constant LAP_INTVL : time    := 50 ns;
        begin
            -- Save laps at 50 ns intervals throughout the running period.
            -- Each lap save takes BTN_HOLD + CLK_PERIOD = 50 ns (at our timing).
            while elapsed + LAP_INTVL <= run_duration loop
                wait for LAP_INTVL - (BTN_HOLD + CLK_PERIOD);
                elapsed := elapsed + LAP_INTVL - (BTN_HOLD + CLK_PERIOD);
                save_lap;
                elapsed := elapsed + BTN_HOLD + CLK_PERIOD;
            end loop;
            -- Wait for the remainder of the run period
            if elapsed < run_duration then
                wait for run_duration - elapsed;
            end if;
        end procedure;

    begin

        -- -------------------------------------------------------------------
        -- 0 ns : System reset (CPU_RESETN active low)
        -- -------------------------------------------------------------------
        report "=== RESET START ===" severity note;
        cpu_resetn <= '0';
        wait for 50 ns;

        -- -------------------------------------------------------------------
        -- 50 ns : Release reset -> IDLE state, blue LED
        -- -------------------------------------------------------------------
        report "=== RESET RELEASED -> IDLE ===" severity note;
        cpu_resetn <= '1';
        wait for CLK_PERIOD;   -- settle one cycle

        -- -------------------------------------------------------------------
        -- ~60 ns : START -> RUNNING (phase 1: 1 ms)
        -- -------------------------------------------------------------------
        report "=== START PRESSED -> RUNNING (phase 1, 1 ms) ===" severity note;
        press_btn(btnl);

        -- Run for 1 ms, saving a lap every 50 ns
        run_with_laps(1000 ns);   -- 1 ms = 1000 ns in simulation time

        -- -------------------------------------------------------------------
        -- ~1060 ns : PAUSE -> PAUSED (50 ns pause)
        -- -------------------------------------------------------------------
        report "=== PAUSE PRESSED -> PAUSED (50 ns) ===" severity note;
        press_btn(btnc);
        wait for 50 ns;

        -- -------------------------------------------------------------------
        -- ~1110 ns : START -> RUNNING (phase 2: 400 ns)
        -- -------------------------------------------------------------------
        report "=== START PRESSED -> RUNNING (phase 2, 400 ns) ===" severity note;
        press_btn(btnl);

        run_with_laps(400 ns);

        -- -------------------------------------------------------------------
        -- ~1510 ns : PAUSE -> PAUSED (50 ns pause)
        -- -------------------------------------------------------------------
        report "=== PAUSE PRESSED -> PAUSED (50 ns) ===" severity note;
        press_btn(btnc);
        wait for 50 ns;

        -- -------------------------------------------------------------------
        -- ~1560 ns : START -> RUNNING (phase 3: 100 ns)
        -- -------------------------------------------------------------------
        report "=== START PRESSED -> RUNNING (phase 3, 100 ns) ===" severity note;
        press_btn(btnl);

        run_with_laps(100 ns);

        -- -------------------------------------------------------------------
        -- ~1660 ns : STOP (first press) -> STOPPED
        -- -------------------------------------------------------------------
        report "=== STOP PRESSED -> STOPPED ===" severity note;
        press_btn(btnr);

        -- 50 ns before end of simulation -> RESET
        -- STOPPED state needs TWO presses of BTNR to fully reset:
        --   1st press: advances stop_cnt to 1
        --   2nd press: clears time + lap memory -> IDLE
        wait for 50 ns;

        -- -------------------------------------------------------------------
        -- ~1710 ns : RESET sequence (50 ns before simulation end)
        -- -------------------------------------------------------------------
        report "=== RESET: first BTNR (advance stop_cnt) ===" severity note;
        press_btn(btnr);

        report "=== RESET: second BTNR -> IDLE + clear all ===" severity note;
        press_btn(btnr);

        -- -------------------------------------------------------------------
        -- ~1760 ns : End of simulation
        -- -------------------------------------------------------------------
        report "=== SIMULATION COMPLETE ===" severity note;
        wait for 10 ns;
        report "=== TESTBENCH FINISHED ===" severity failure;  -- ends simulation

    end process;

end sim;

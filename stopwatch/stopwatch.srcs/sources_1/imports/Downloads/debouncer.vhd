-- debouncer.vhd
-- Synchronizovany debouncer pro tlacitka a spinace
-- Vystupuje rising-edge pulz (pulse_out) a urovnovy signal (level_out)

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity debouncer is
    generic (
        CLK_FREQ_HZ  : integer := 100_000_000;  -- 100 MHz Nexys A7
        DEBOUNCE_MS  : integer := 20             -- 20 ms debounce
    );
    port (
        clk       : in  std_logic;
        rst       : in  std_logic;
        sig_in    : in  std_logic;
        level_out : out std_logic;   -- stabilni uroven
        pulse_out : out std_logic    -- jediny hodinovy pulz pri rising edge
    );
end debouncer;

architecture rtl of debouncer is
    constant MAX_COUNT : integer := (CLK_FREQ_HZ / 1000) * DEBOUNCE_MS;

    signal cnt      : integer range 0 to MAX_COUNT := 0;
    signal stable   : std_logic := '0';
    signal prev     : std_logic := '0';
    signal sync0    : std_logic := '0';
    signal sync1    : std_logic := '0';
begin

    -- Dvoustupnova synchronizace (metastabilita)
    process(clk)
    begin
        if rising_edge(clk) then
            sync0 <= sig_in;
            sync1 <= sync0;
        end if;
    end process;

    -- Citac debounce
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                cnt    <= 0;
                stable <= '0';
                prev   <= '0';
            else
                if sync1 /= stable then
                    if cnt = MAX_COUNT - 1 then
                        stable <= sync1;
                        cnt    <= 0;
                    else
                        cnt <= cnt + 1;
                    end if;
                else
                    cnt <= 0;
                end if;

                prev <= stable;
            end if;
        end if;
    end process;

    level_out <= stable;
    pulse_out <= stable and (not prev);  -- rising edge pulz

end rtl;

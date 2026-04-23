-- counter.vhd
-- BCD stopky citac: setiny (00-99) a sekundy (00-89)
-- Max cas: 89:99 (90 sekund), pak autostop
-- Vystup: sec_tens, sec_units, cs_tens, cs_units (BCD cifry)
--         tick_100hz : pulz kazde 1/100 s (pro externi pouziti)
--         max_reached: '1' kdyz dosazeno 90s (autostop)

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity counter is
    generic (
        CLK_FREQ_HZ : integer := 100_000_000
    );
    port (
        clk         : in  std_logic;
        rst         : in  std_logic;
        enable      : in  std_logic;   -- '1' = citac bezi
        sec_tens    : out std_logic_vector(3 downto 0);
        sec_units   : out std_logic_vector(3 downto 0);
        cs_tens     : out std_logic_vector(3 downto 0);  -- setiny - desitky
        cs_units    : out std_logic_vector(3 downto 0);  -- setiny - jednotky
        tick_100hz  : out std_logic;
        max_reached : out std_logic
    );
end counter;

architecture rtl of counter is
    -- Delicka pro 100 Hz (kazde 10ms -> 1/100s)
    constant DIV_100HZ : integer := CLK_FREQ_HZ / 100;

    signal div_cnt  : integer range 0 to DIV_100HZ - 1 := 0;
    signal tick     : std_logic := '0';

    -- BCD registry
    signal r_cs_u   : integer range 0 to 9 := 0;   -- setiny jednotky
    signal r_cs_t   : integer range 0 to 9 := 0;   -- setiny desitky
    signal r_sec_u  : integer range 0 to 9 := 0;   -- sekundy jednotky
    signal r_sec_t  : integer range 0 to 8 := 0;   -- sekundy desitky (max 8)

    signal r_max    : std_logic := '0';
begin

    -- 100 Hz tick generator
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                div_cnt <= 0;
                tick    <= '0';
            else
                if div_cnt = DIV_100HZ - 1 then
                    div_cnt <= 0;
                    tick    <= '1';
                else
                    div_cnt <= div_cnt + 1;
                    tick    <= '0';
                end if;
            end if;
        end if;
    end process;

    -- BCD citac
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                r_cs_u  <= 0;
                r_cs_t  <= 0;
                r_sec_u <= 0;
                r_sec_t <= 0;
                r_max   <= '0';
            elsif enable = '1' and tick = '1' and r_max = '0' then

                -- setiny jednotky
                if r_cs_u = 9 then
                    r_cs_u <= 0;
                    -- setiny desitky
                    if r_cs_t = 9 then
                        r_cs_t <= 0;
                        -- sekundy jednotky
                        if r_sec_u = 9 then
                            r_sec_u <= 0;
                            -- sekundy desitky
                            if r_sec_t = 8 then
                                -- Dosazeno 90 sekund -> autostop
                                r_max <= '1';
                            else
                                r_sec_t <= r_sec_t + 1;
                            end if;
                        else
                            r_sec_u <= r_sec_u + 1;
                        end if;
                    else
                        r_cs_t <= r_cs_t + 1;
                    end if;
                else
                    r_cs_u <= r_cs_u + 1;
                end if;

            end if;
        end if;
    end process;

    -- Prevod int -> std_logic_vector BCD
    sec_tens    <= std_logic_vector(to_unsigned(r_sec_t, 4));
    sec_units   <= std_logic_vector(to_unsigned(r_sec_u, 4));
    cs_tens     <= std_logic_vector(to_unsigned(r_cs_t,  4));
    cs_units    <= std_logic_vector(to_unsigned(r_cs_u,  4));
    tick_100hz  <= tick;
    max_reached <= r_max;

end rtl;

-- lap_memory.vhd
-- Uloziste mezicasu: 5 slotu (indexovano spinaci SW[2:0], platne hodnoty 0-4)
-- Kazdy slot: sec_t(4b), sec_u(4b), cs_t(4b), cs_u(4b) = 16 bitu
-- lap_saved_leds: bitmapa ulozenych slotu (5 bitu, pro LED[4:0] nad spinaci)
-- lap_rst: vymaze vsechny sloty (aktivni 1 clk pulz, ovladano STOP tlacitkem)

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity lap_memory is
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
end lap_memory;

architecture rtl of lap_memory is
    type lap_data_t is array(0 to 4) of std_logic_vector(15 downto 0);
    signal mem        : lap_data_t := (others => (others => '0'));
    signal saved_mask : std_logic_vector(4 downto 0) := (others => '0');

    -- Auto-increment write pointer (0-4, zastavi na 4)
    signal write_ptr  : integer range 0 to 4 := 0;
begin

    -- Zapis / reset
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                mem        <= (others => (others => '0'));
                saved_mask <= (others => '0');
                write_ptr  <= 0;
            elsif lap_rst = '1' then
                -- STOP tlacitko ze stavu STOPPED: vymaz vsechny mezicasy
                mem        <= (others => (others => '0'));
                saved_mask <= (others => '0');
                write_ptr  <= 0;
            elsif write_en = '1' then
                -- Uloz mezicas do aktualniho slotu
                mem(write_ptr) <= sec_tens_in & sec_units_in & cs_tens_in & cs_units_in;
                saved_mask(write_ptr) <= '1';
                -- Posun write pointer (zastavi na poslednim slotu)
                if write_ptr < 4 then
                    write_ptr <= write_ptr + 1;
                end if;
            end if;
        end if;
    end process;

    -- Asynchronni cteni
    process(read_addr, mem)
        variable idx : integer range 0 to 4;
    begin
        -- Omez adresu na platny rozsah 0-4
        if to_integer(unsigned(read_addr)) > 4 then
            idx := 4;
        else
            idx := to_integer(unsigned(read_addr));
        end if;
        sec_tens_out  <= mem(idx)(15 downto 12);
        sec_units_out <= mem(idx)(11 downto 8);
        cs_tens_out   <= mem(idx)(7  downto 4);
        cs_units_out  <= mem(idx)(3  downto 0);
    end process;

    lap_saved_leds <= saved_mask;

end rtl;

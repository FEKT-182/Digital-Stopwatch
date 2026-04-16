-- lap_memory.vhd
-- Uloziste mezicasu: 8 slotu (indexovano spinaci SW[2:0])
-- Kazdy slot: sec_t(4b), sec_u(4b), cs_t(4b), cs_u(4b) = 16 bitu
-- lap_saved_leds: bitmapa ulozenych slotu (pro LED nad spinaci)

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity lap_memory is
    port (
        clk          : in  std_logic;
        rst          : in  std_logic;
        -- Zapis mezicasu
        write_en     : in  std_logic;   -- pulz pri stisku spodniho tlacitka
        sec_tens_in  : in  std_logic_vector(3 downto 0);
        sec_units_in : in  std_logic_vector(3 downto 0);
        cs_tens_in   : in  std_logic_vector(3 downto 0);
        cs_units_in  : in  std_logic_vector(3 downto 0);
        -- Cteni (pro zobrazeni)
        read_addr    : in  std_logic_vector(2 downto 0);   -- SW[2:0]
        sec_tens_out : out std_logic_vector(3 downto 0);
        sec_units_out: out std_logic_vector(3 downto 0);
        cs_tens_out  : out std_logic_vector(3 downto 0);
        cs_units_out : out std_logic_vector(3 downto 0);
        -- Status
        lap_saved_leds : out std_logic_vector(7 downto 0)  -- bitmapa plnych slotu
    );
end lap_memory;

architecture rtl of lap_memory is
    type lap_data_t is array(0 to 7) of std_logic_vector(15 downto 0);
    signal mem        : lap_data_t := (others => (others => '0'));
    signal saved_mask : std_logic_vector(7 downto 0) := (others => '0');

    -- Pocitadlo pro auto-increment adresy zapisu
    signal write_ptr  : integer range 0 to 7 := 0;
begin

    -- Zapis
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                mem        <= (others => (others => '0'));
                saved_mask <= (others => '0');
                write_ptr  <= 0;
            elsif write_en = '1' then
                mem(write_ptr) <= sec_tens_in & sec_units_in & cs_tens_in & cs_units_in;
                saved_mask(write_ptr) <= '1';
                if write_ptr < 7 then
                    write_ptr <= write_ptr + 1;
                end if;
            end if;
        end if;
    end process;

    -- Asynchronni cteni (combinacni)
    process(read_addr, mem)
        variable idx : integer range 0 to 7;
    begin
        idx := to_integer(unsigned(read_addr));
        sec_tens_out  <= mem(idx)(15 downto 12);
        sec_units_out <= mem(idx)(11 downto 8);
        cs_tens_out   <= mem(idx)(7  downto 4);
        cs_units_out  <= mem(idx)(3  downto 0);
    end process;

    lap_saved_leds <= saved_mask;

end rtl;

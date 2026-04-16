-- seg7_display.vhd
-- Casovy multiplex pro 8x 7-segmentovych displej na Nexys A7
--
-- Rozlozeni displeje:
--   AN[7:4] = leve 4 cifry  = zivý cas  (SS:CC  sekundy:setiny)
--   AN[3:0] = prave 4 cifry = mezicas   (SS:CC)
--   Tecky (DP) zapnuty mezi sekundami a setinami
--
-- Pokud show_lap='0':  AN[7:4] = zivý cas,  AN[3:0] = zivý cas (zdvojeni)
--                       realne zobrazuje jen jedna skupina
-- Pokud show_lap='1':  AN[7:4] = zivý cas,  AN[3:0] = mezicas
--
-- Pri error_flag: vsechny displeje zobrazuji "Err" blikajici

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity seg7_display is
    generic (
        CLK_FREQ_HZ : integer := 100_000_000;
        MUX_FREQ_HZ : integer := 1000   -- 1 kHz multiplex (1ms per digit)
    );
    port (
        clk          : in  std_logic;
        rst          : in  std_logic;

        -- Živý cas
        live_sec_t   : in  std_logic_vector(3 downto 0);
        live_sec_u   : in  std_logic_vector(3 downto 0);
        live_cs_t    : in  std_logic_vector(3 downto 0);
        live_cs_u    : in  std_logic_vector(3 downto 0);

        -- Mezicas
        lap_sec_t    : in  std_logic_vector(3 downto 0);
        lap_sec_u    : in  std_logic_vector(3 downto 0);
        lap_cs_t     : in  std_logic_vector(3 downto 0);
        lap_cs_u     : in  std_logic_vector(3 downto 0);

        show_lap     : in  std_logic;
        error_flag   : in  std_logic;

        -- Nexys A7 7-seg vystup
        seg          : out std_logic_vector(6 downto 0);  -- CA..CG (active low)
        dp           : out std_logic;                      -- desetinna tecka (active low)
        an           : out std_logic_vector(7 downto 0)   -- anody (active low)
    );
end seg7_display;

architecture rtl of seg7_display is

    constant DIV_MUX : integer := CLK_FREQ_HZ / MUX_FREQ_HZ;

    signal mux_cnt  : integer range 0 to DIV_MUX - 1 := 0;
    signal digit_sel: integer range 0 to 7 := 0;

    -- Blikani pro error (cca 2 Hz)
    signal blink_cnt : integer range 0 to CLK_FREQ_HZ / 4 - 1 := 0;
    signal blink     : std_logic := '0';

    signal current_digit : std_logic_vector(3 downto 0);
    signal show_dp       : std_logic;

    -- BCD -> 7seg dekoder (Nexys A7: active low, CA=seg(6)...CG=seg(0))
    function bcd_to_seg(bcd : std_logic_vector(3 downto 0)) return std_logic_vector is
        -- Vraci 7 bitu: CA CB CC CD CE CF CG (active low)
        variable s : std_logic_vector(6 downto 0);
    begin
        case bcd is
            when "0000" => s := "0000001";  -- 0
            when "0001" => s := "1001111";  -- 1
            when "0010" => s := "0010010";  -- 2
            when "0011" => s := "0000110";  -- 3
            when "0100" => s := "1001100";  -- 4
            when "0101" => s := "0100100";  -- 5
            when "0110" => s := "0100000";  -- 6
            when "0111" => s := "0001111";  -- 7
            when "1000" => s := "0000000";  -- 8
            when "1001" => s := "0000100";  -- 9
            when others => s := "1111111";  -- blank
        end case;
        return s;
    end function;

    -- Specialni znaky pro ERR
    -- E = 0110000, r = 1110001, mezera = 1111111
    constant SEG_E     : std_logic_vector(6 downto 0) := "0110000";
    constant SEG_r     : std_logic_vector(6 downto 0) := "1110001";
    constant SEG_BLANK : std_logic_vector(6 downto 0) := "1111111";
    constant SEG_DASH  : std_logic_vector(6 downto 0) := "1111110";

begin

    -- Multiplexer takt
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                mux_cnt   <= 0;
                digit_sel <= 0;
                blink_cnt <= 0;
                blink     <= '0';
            else
                -- Blik pro error
                if blink_cnt = CLK_FREQ_HZ / 4 - 1 then
                    blink_cnt <= 0;
                    blink     <= not blink;
                else
                    blink_cnt <= blink_cnt + 1;
                end if;

                -- Digit MUX
                if mux_cnt = DIV_MUX - 1 then
                    mux_cnt   <= 0;
                    if digit_sel = 7 then
                        digit_sel <= 0;
                    else
                        digit_sel <= digit_sel + 1;
                    end if;
                else
                    mux_cnt <= mux_cnt + 1;
                end if;
            end if;
        end if;
    end process;

    -- Kombinacni vystup
    process(digit_sel, live_sec_t, live_sec_u, live_cs_t, live_cs_u,
            lap_sec_t,  lap_sec_u,  lap_cs_t,  lap_cs_u,
            show_lap, error_flag, blink)

        variable seg_v : std_logic_vector(6 downto 0);
        variable dp_v  : std_logic;
        variable an_v  : std_logic_vector(7 downto 0);

    begin
        seg_v := SEG_BLANK;
        dp_v  := '1';  -- dp active low, '1' = vypnuta
        an_v  := "11111111";  -- vsechny vypnute

        if error_flag = '1' then
            -- Zobraz "Err Err" blikajici na vsech 8 digitech
            -- AN[7] = blank, AN[6]=E, AN[5]=r, AN[4]=r, AN[3]=blank, AN[2]=E, AN[1]=r, AN[0]=r
            if blink = '1' then
                an_v := not std_logic_vector(to_unsigned(2 ** digit_sel, 8));
                case digit_sel is
                    when 6 | 2 => seg_v := SEG_E;
                    when 5 | 1 => seg_v := SEG_r;
                    when 4 | 0 => seg_v := SEG_r;
                    when others => seg_v := SEG_BLANK;
                end case;
            end if;
            dp_v := '1';

        else
            -- Normalni zobrazeni
            -- AN[7:4] = zivý cas:  7=sec_t, 6=sec_u, [dp mezi 6 a 5], 5=cs_t, 4=cs_u
            -- AN[3:0] = mezicas:   3=sec_t, 2=sec_u, [dp mezi 2 a 1],  1=cs_t, 0=cs_u
            an_v := not std_logic_vector(to_unsigned(2 ** digit_sel, 8));

            case digit_sel is
                -- Živý cas (leve 4 cifry)
                when 7 => seg_v := bcd_to_seg(live_sec_t); dp_v := '1';
                when 6 => seg_v := bcd_to_seg(live_sec_u); dp_v := '0';  -- tecka = oddelovac
                when 5 => seg_v := bcd_to_seg(live_cs_t);  dp_v := '1';
                when 4 => seg_v := bcd_to_seg(live_cs_u);  dp_v := '1';

                -- Mezicas nebo zivý cas (prave 4 cifry)
                when 3 =>
                    if show_lap = '1' then seg_v := bcd_to_seg(lap_sec_t);
                    else                   seg_v := bcd_to_seg(live_sec_t); end if;
                    dp_v := '1';
                when 2 =>
                    if show_lap = '1' then seg_v := bcd_to_seg(lap_sec_u);
                    else                   seg_v := bcd_to_seg(live_sec_u); end if;
                    dp_v := '0';  -- tecka = oddelovac
                when 1 =>
                    if show_lap = '1' then seg_v := bcd_to_seg(lap_cs_t);
                    else                   seg_v := bcd_to_seg(live_cs_t); end if;
                    dp_v := '1';
                when 0 =>
                    if show_lap = '1' then seg_v := bcd_to_seg(lap_cs_u);
                    else                   seg_v := bcd_to_seg(live_cs_u); end if;
                    dp_v := '1';

                when others => seg_v := SEG_BLANK; dp_v := '1';
            end case;
        end if;

        seg <= seg_v;
        dp  <= dp_v;
        an  <= an_v;
    end process;

end rtl;

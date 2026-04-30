Ovládání


Displej (8x 7-segmentových číslic) 
	
	XX:XX(živý čas - sekundy:setiny) YY:YY(kolo - sekundy:setiny) => do 90 sekund, autostop
	Error message pro více spínačů
	Stavová RGB LED - LED16, R - pause, G - běží, B - konec

Tlačítka
	
	Levé tlačítko - start
	Prostřední tlačítko - pause
	Pravé tlačítko - stop, 2x vymazání
	Spodní tlačítko - zapsání mezičasu

Spínače 
	
	výběr mezičasu
	LED nad spínači - uložení mezičasu

Komponenty


[Counter](stopwatch/stopwatch.srcs/sources_1/imports/Downloads/counter.vhd)

Kaskádový BCD čítač, který tikne 100x za sekundu a sleduje setiny a sekundy. Automaticky se zastaví a nastaví max_reached při dosažení 90 sekund.

[Debouncer](stopwatch/stopwatch.srcs/sources_1/imports/Downloads/debouncer.vhd)

Dvoustupňový synchronizátor následovaný časovačem, který čeká 20 ms stabilního vstupu před přijetím stisku tlačítka. Výstupem je jak ustálená úroveň, tak jednocyklový pulz náběžné hrany.

[Lap_memory](stopwatch/stopwatch.srcs/sources_1/imports/Downloads/lap_memory.vhd)

Registrové pole s pěti sloty, které při každém stisku BTND uloží aktuální BCD čas, s automaticky se inkrementujícím ukazatelem zápisu. Přepínači se vybírá, který uložený slot se zobrazí.

[Seg7_display](stopwatch/stopwatch.srcs/sources_1/imports/Downloads/seg7_display.vhd)

Časově multiplexovaný ovladač 1 kHz pro 8místný sedmisegmentový displej. Levé čtyři cifry zobrazují živý čas, pravé čtyři vybraný mezičas; existují přepisy pro blikající zprávy „Err" a „End".

[Stopwatch_ctrl](stopwatch/stopwatch.srcs/sources_1/imports/Downloads/stopwatch_ctrl.vhd)

Hlavní FSM s pěti stavy (IDLE -> RUNNING -> PAUSED -> STOPPED -> ERROR). Převádí debounced pulzy tlačítek na signály pro povolení/reset čítače, zápis mezičasu a RGB LED.

[Top](stopwatch/stopwatch.srcs/sources_1/imports/Downloads/top.vhd)

Propojuje všechny výše uvedené komponenty, rozvádí 100MHz hodinový signál a aktivně nízký reset a mapuje piny desky (tlačítka, přepínače, LED, segmenty) na porty příslušných submodulů.


Ostatní
	
Jan - Plakát, kód, video

Petr - Kód, github

Vojtěch - Kód, schéma, simulace

Claude AI, ChatGPT - Korekce, pomoc při potížích 

; ADC_Demo.asm
; Small test file for ADC Peripheral
; Updates current voltage reading and outputs to hex display if any switch is on

ORG 0

MainLoop:
	; get switch values
	IN		Switches
	; skip refresh and loop back if all switches are down
	JZERO 	MainLoop
	; else get current voltage reading
	IN 		ADC_ADDR
	; Outputs that value to hex displays
	OUT 	Hex0
	; infinite loop
	JUMP 	MainLoop


Switches:  EQU 000
LEDs:      EQU 001
Timer:     EQU 002
Hex0:      EQU 004
Hex1:      EQU 005
ADC_ADDR:  EQU 192

# Sniper 2031 — ADC Controller Peripheral
**ECE 2031 | Team Sniper 2031**

---


## Project Overview

This project implements a custom SCOMP peripheral for the LTC2308 analog-to-digital converter (ADC) chip on the DE10-Standard FPGA board. The peripheral translates between SCOMP's simple I/O bus interface and the SPI communication protocol required by the ADC chip.

The peripheral is demonstrated through **Sniper 2031** — a 1D arcade shooting game where a player uses a potentiometer to aim a weapon LED at a target LED on the DE10's 10-LED array and presses a button to fire.

---

## Hardware — ADC Controller Peripheral

### What it does

The peripheral continuously reads analog voltage from an input source using the LTC2308 ADC chip via SPI, and exposes the most recent 12-bit result to SCOMP through a single memory-mapped I/O address.

### Peripheral API

| Address | Name | Access | Bits [15:12] | Bits [11:0] |
|---------|------|--------|--------------|-------------|
| 0xC0 | ADC_DATA | Read-only | Always 0 | 12-bit result (0–4095) |

**Usage:**
```
IN   192    ; AC = current ADC reading, range 0 to 4095
```
> Note: 192 decimal = 0xC0 hex. SCASM requires decimal addresses.

No initialization or trigger required. The peripheral samples continuously in the background. A fresh value is always available immediately upon reading.

### SPI State Machine

The peripheral uses a 5-state VHDL state machine:

```
IDLE → CONV_PULSE → CONV_WAIT → TRANSFER → HOLD → (back to IDLE)
```

| State | Description |
|-------|-------------|
| IDLE | Drives CONVST high to trigger conversion, primes MOSI with first config bit |
| CONV_PULSE | Pulls CONVST low to keep ADC awake, starts wait counter |
| CONV_WAIT | Waits 85 clock cycles (~1.7 µs) for conversion to complete |
| TRANSFER | Shifts 12 bits in/out over SPI — config on MOSI, result on MISO |
| HOLD | Latches completed 12-bit result into output register, zero-pads to 16 bits |

### Key Design Decisions

- **Continuous polling** — state machine loops back to IDLE immediately after every conversion. SCOMP always reads a fresh value with no wait.
- **85-cycle wait** — DE10 runs at 50 MHz (20 ns/cycle). 85 × 20 ns = 1.7 µs, safely above the LTC2308's 1.6 µs maximum conversion time.
- **Hardcoded config** — TX word `100010` selects CH0, single-ended, unipolar mode. No programmer configuration needed.
- **CLK_DIV generic** — SPI clock speed is adjustable via a VHDL generic parameter for signal integrity flexibility.

### VHDL IO Bus Integration

```vhdl
IO_DATA <= output_mem
  WHEN (IO_ADDR = "00011000000")
  AND  (IO_READ = '1')
  ELSE "ZZZZZZZZZZZZZZZZ";
```

The address `"00011000000"` in binary = `0xC0` in hex = `192` in decimal.

---

## Software — Sniper 2031 Game

### How to assemble

1. Open `sniper2031.asm` in the **portable Notepad++** provided with the lab files (not a regular Notepad++ install — it must have SCASM configured).
2. Copy the `scasm.cfg` file from a previous lab folder into the same directory as `sniper2031.asm`.
3. Press `Ctrl+1` to run SCASM.
4. If successful, a `.mif` file will be generated in the same folder.
5. Load the `.mif` file into your Quartus project as the SCOMP program memory.

### How the game works

```
10 LEDs in a row:  [ ][ ][ ][W][ ][ ][ ][T][ ][ ]
                         ^               ^
                      Weapon           Target
```

- **W** = Weapon LED, controlled by the potentiometer
- **T** = Target LED, fixed position that moves after each hit
- Turn the potentiometer to move the weapon LED left or right
- Press the fire button (Switch bit 0) when aligned with the target to score

### Software algorithm

**Every game loop frame:**

1. `IN 192` — read ADC value (0–4095)
2. Subtract minimum offset (552) to account for potentiometer floor
3. Repeated subtraction of bucket size (354) to find LED index 0–9
4. Bit shift a `1` left by the index to get one-hot weapon pattern
5. OR weapon + target patterns → output to LEDs
6. Read fire button — if pressed, AND weapon + target
7. Non-zero AND result = hit → increment score, move target

### I/O Address Map (software side)

| Address (decimal) | Address (hex) | Device | Usage |
|-------------------|---------------|--------|-------|
| 192 | 0xC0 | ADC peripheral | Read potentiometer value |
| 0 | 0x00 | LEDs | Output weapon + target display |
| 80 | 0x50 | Switches | Read fire button (bit 0) |
| 4 | 0x04 | HEX display | Display score |

### Constants

| Constant | Value | Reason |
|----------|-------|--------|
| ADC_MIN | 552 (0x228) | Observed potentiometer minimum on hardware |
| BUCKET_SIZE | 354 | (4095 − 552) / 10 = 354.3 per LED bucket |

---

## Testing Plan

### Phase 1 — ModelSim Simulation
Verify SPI timing waveforms match the LTC2308 datasheet before programming the FPGA. Confirm CONVST pulses correctly, 85-cycle wait is observed, and exactly 12 SCK pulses occur per cycle.

### Phase 2 — Hardware Smoke Test
Run a minimal SCOMP program that loops `IN 192` and outputs the raw value to the 7-seg display. Turn the potentiometer — numbers should change smoothly. **This phase has already been verified on the physical DE10 board.**

### Phase 3 — Full Game Integration
Load `sniper2031.asm`, verify weapon LED tracks the potentiometer across all 10 positions, and confirm hit detection works correctly when weapon and target align.

---

## Contingency Plan

| Risk | Mitigation |
|------|-----------|
| SPI timing incorrect | Fix in ModelSim simulation before touching hardware |
| Peripheral not responding on board | Isolate: check address decode, tri-state buffer, then SPI logic independently |
| Signal integrity issues | Increase CLK_DIV generic to slow SPI clock from 50 MHz to 12.5 MHz or lower |
| Game logic not finished in time | Fall back to smoke test demo — peripheral functionality is proven without the game |

---

## Register Map

See `ADC_Peripheral_Register_Map.pdf` for the full formal register map and interface description.

**Summary:**

Reading address `0xC0` returns the most recent 12-bit ADC conversion result, right-aligned in a 16-bit word. Bits [15:12] are always zero. Range is 0 to 4095. No write operations or configuration are required.

---

*ECE 2031 Digital Design Laboratory — Spring 2026*
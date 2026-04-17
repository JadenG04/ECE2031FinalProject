; =============================================================
; Sniper 2031 — SCOMP Assembly Game
; =============================================================
; Peripheral: ADC Controller at address 0xC0
; Returns: 12-bit unsigned value, range 552-4095
;
; Hardware:
;   0xC0 = ADC peripheral (potentiometer)
;   0x00 = LEDs (10 LEDs, bits 9-0)
;   0x50 = Switches (bit 0 = fire button)
;   0x04 = HEX display (score)
;
; Memory locations used as variables:
;   WEAPON_PAT = one-hot pattern for weapon LED
;   TARGET_PAT = one-hot pattern for target LED
;   SCORE      = current player score
;   IDX        = loop index / scratch
;   SCRATCH    = general scratch variable
;   TARGET_IDX = current target LED index
; =============================================================

        ORG     0           ; program starts at address 0

; =============================================================
; INITIALIZATION
; =============================================================
INIT:
        LOADI   0               ; score = 0
        STORE   SCORE

        LOADI   7               ; target starts at LED index 7
        STORE   TARGET_IDX

        CALL    MAKE_TARGET     ; build initial target pattern

; =============================================================
; MAIN GAME LOOP
; =============================================================
GAME_LOOP:

        ; --- Read ADC ---
        IN      192            ; AC = raw ADC value (0-4095)
        STORE   SCRATCH

        ; --- Subtract minimum offset (0x228 = 552) ---
        SUB     ADC_MIN         ; AC = AC - 552
        JNEG    CLAMP           ; if negative, clamp to 0
        STORE   SCRATCH
        JUMP    SCALE

CLAMP:
        LOADI   0
        STORE   SCRATCH

        ; --- Scale to LED index 0-9 ---
SCALE:
        LOADI   0
        STORE   IDX             ; IDX = 0 (LED index counter)

SCALE_LOOP:
        LOAD    SCRATCH
        SUB     BUCKET          ; subtract one bucket size (354)
        JNEG    SCALE_DONE      ; went negative, found the bucket
        STORE   SCRATCH         ; save updated value
        LOAD    IDX
        ADDI    1               ; increment LED index
        STORE   IDX
        SUB     NINE            ; check if IDX >= 9
        JPOS    CLAMP_MAX       ; clamp at 9
        JZERO   CLAMP_MAX
        JUMP    SCALE_LOOP

CLAMP_MAX:
        LOADI   9
        STORE   IDX

SCALE_DONE:
        ; IDX now holds LED index 0-9
        CALL    MAKE_WEAPON     ; build weapon one-hot pattern

        ; --- Display weapon + target ---
        LOAD    WEAPON_PAT
        OR      TARGET_PAT      ; AC = weapon OR target
        OUT     1            ; display both LEDs

        ; --- Check fire button ---
        IN      80            ; AC = switch input
        AND     BUTTON_MASK     ; isolate bit 0
        JZERO   GAME_LOOP       ; not pressed, keep looping

        ; --- Button pressed: check for hit ---
        LOAD    WEAPON_PAT
        AND     TARGET_PAT      ; AC = weapon AND target
        JZERO   MISS            ; zero = miss

        ; --- HIT ---
        LOAD    SCORE
        ADDI    1               ; score++
        STORE   SCORE
        OUT     4            ; display score on HEX

        ; Move target forward 3 positions
        LOAD    TARGET_IDX
        ADDI    3
        STORE   TARGET_IDX

        ; Keep target in range 0-9 (modulo 10)
MOD_LOOP:
        LOAD    TARGET_IDX
        SUB     TEN
        JNEG    MOD_DONE
        STORE   TARGET_IDX
        JUMP    MOD_LOOP

MOD_DONE:
        CALL    MAKE_TARGET
        JUMP    GAME_LOOP

MISS:
        JUMP    GAME_LOOP


; =============================================================
; SUBROUTINE: MAKE_WEAPON
; Converts IDX (0-9) into a one-hot pattern
; Stores result in WEAPON_PAT
; =============================================================
MAKE_WEAPON:
        LOADI   1               ; start with bit 0 set
        STORE   WEAPON_PAT
        LOAD    IDX
        STORE   SHIFT_CNT

WEAPON_SHIFT:
        LOAD    SHIFT_CNT
        JZERO   WEAPON_DONE     ; counter = 0, done
        LOAD    WEAPON_PAT
        SHIFT   1               ; shift left by 1
        STORE   WEAPON_PAT
        LOAD    SHIFT_CNT
        ADDI    -1
        STORE   SHIFT_CNT
        JUMP    WEAPON_SHIFT

WEAPON_DONE:
        RETURN


; =============================================================
; SUBROUTINE: MAKE_TARGET
; Converts TARGET_IDX (0-9) into a one-hot pattern
; Stores result in TARGET_PAT
; =============================================================
MAKE_TARGET:
        LOADI   1               ; start with bit 0 set
        STORE   TARGET_PAT
        LOAD    TARGET_IDX
        STORE   SHIFT_CNT

TARGET_SHIFT:
        LOAD    SHIFT_CNT
        JZERO   TARGET_DONE     ; counter = 0, done
        LOAD    TARGET_PAT
        SHIFT   1               ; shift left by 1
        STORE   TARGET_PAT
        LOAD    SHIFT_CNT
        ADDI    -1
        STORE   SHIFT_CNT
        JUMP    TARGET_SHIFT

TARGET_DONE:
        RETURN


; =============================================================
; VARIABLES AND CONSTANTS
; =============================================================
        ORG     256

WEAPON_PAT: DW  0
TARGET_PAT: DW  0
SCORE:      DW  0
IDX:        DW  0
SCRATCH:    DW  0
TARGET_IDX: DW  7
SHIFT_CNT:  DW  0
ADC_MIN:    DW  552
BUCKET:     DW  354
NINE:       DW  9
TEN:        DW  10
BUTTON_MASK: DW  1
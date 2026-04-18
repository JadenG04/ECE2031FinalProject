; =============================================================
; Sniper 2031 — SCOMP Assembly Game
; =============================================================
; Peripheral: ADC Controller at address 192 (0xC0)
; Potentiometer range: 552 (min) to 4095 (max)
;
; Controls:
;   Potentiometer = move weapon LED left/right
;   Switch 0      = fire button
;
; Hardware I/O:
;   192 = ADC peripheral (0xC0)
;   0   = Switches (read) / LEDs (write) -- check your system
;   1   = LEDs
;   4   = HEX display (score)
; =============================================================

        ORG     0

; =============================================================
; INITIALIZATION
; =============================================================
INIT:
        LOADI   0
        STORE   SCORE

        LOADI   7
        STORE   TARGET_IDX

        CALL    MAKE_TARGET

; =============================================================
; MAIN GAME LOOP
; =============================================================
GAME_LOOP:

        ; --- Read ADC ---
        IN      192
        STORE   SCRATCH

        ; --- Subtract potentiometer floor ---
        SUB     ADC_MIN
        JNEG    CLAMP_ZERO
        STORE   SCRATCH
        JUMP    SCALE

CLAMP_ZERO:
        LOADI   0
        STORE   SCRATCH

        ; --- Scale to LED index 0-9 ---
SCALE:
        LOADI   0
        STORE   IDX

SCALE_LOOP:
        LOAD    SCRATCH
        SUB     BUCKET
        JNEG    SCALE_DONE
        STORE   SCRATCH
        LOAD    IDX
        ADDI    1
        STORE   IDX
        SUB     NINE
        JPOS    CLAMP_MAX
        JZERO   CLAMP_MAX
        JUMP    SCALE_LOOP

CLAMP_MAX:
        LOADI   9
        STORE   IDX

SCALE_DONE:
        CALL    MAKE_WEAPON

        ; --- Display weapon + target ---
        LOAD    WEAPON_PAT
        OR      TARGET_PAT
        OUT     1

        ; --- Read switch 0 as fire button ---
        IN      0               ; read switches from port 0
        AND     BUTTON_MASK     ; isolate bit 0 (switch 0)
        JZERO   GAME_LOOP       ; not pressed, keep looping

        ; --- Fire pressed: check hit ---
        LOAD    WEAPON_PAT
        AND     TARGET_PAT
        JZERO   MISS            ; miss

        ; --- HIT ---
        LOAD    SCORE
        ADDI    1
        STORE   SCORE
        OUT     4               ; show score on HEX

        ; move target 3 positions
        LOAD    TARGET_IDX
        ADDI    3
        STORE   TARGET_IDX

MOD_LOOP:
        LOAD    TARGET_IDX
        SUB     TEN
        JNEG    MOD_DONE
        STORE   TARGET_IDX
        JUMP    MOD_LOOP

MOD_DONE:
        CALL    MAKE_TARGET

        ; --- Wait for switch to be released ---
WAIT_RELEASE:
        IN      0
        AND     BUTTON_MASK
        JNEG    WAIT_RELEASE
        JPOS    WAIT_RELEASE

        JUMP    GAME_LOOP

MISS:
        JUMP    GAME_LOOP


; =============================================================
; MAKE_WEAPON
; =============================================================
MAKE_WEAPON:
        LOADI   1
        STORE   WEAPON_PAT
        LOAD    IDX
        STORE   SHIFT_CNT

MW_LOOP:
        LOAD    SHIFT_CNT
        JZERO   MW_DONE
        LOAD    WEAPON_PAT
        SHIFT   1
        STORE   WEAPON_PAT
        LOAD    SHIFT_CNT
        ADDI    -1
        STORE   SHIFT_CNT
        JUMP    MW_LOOP

MW_DONE:
        RETURN


; =============================================================
; MAKE_TARGET
; =============================================================
MAKE_TARGET:
        LOADI   1
        STORE   TARGET_PAT
        LOAD    TARGET_IDX
        STORE   SHIFT_CNT

MT_LOOP:
        LOAD    SHIFT_CNT
        JZERO   MT_DONE
        LOAD    TARGET_PAT
        SHIFT   1
        STORE   TARGET_PAT
        LOAD    SHIFT_CNT
        ADDI    -1
        STORE   SHIFT_CNT
        JUMP    MT_LOOP

MT_DONE:
        RETURN


; =============================================================
; VARIABLES AND CONSTANTS
; =============================================================
        ORG     256

WEAPON_PAT:  DW  0
TARGET_PAT:  DW  0
SCORE:       DW  0
IDX:         DW  0
SCRATCH:     DW  0
TARGET_IDX:  DW  7
SHIFT_CNT:   DW  0
ADC_MIN:     DW  552
BUCKET:      DW  354
NINE:        DW  9
TEN:         DW  10
BUTTON_MASK: DW  1
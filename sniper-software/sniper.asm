; Sniper 2031 - SCOMP Assembly Game
; ECE 2031 Final Project
;
; How to play:
;   Turn the potentiometer to move your weapon LED
;   Flip switch 0 up to fire
;   If your weapon LED lines up with the target LED, you score a point
;   The target moves to a new position after each hit
;
; The ADC peripheral reads the potentiometer and returns a value
; between 552 (knob fully left) and 4095 (knob fully right).
; We map that range to LED positions 0-9 using repeated subtraction
; since SCOMP doesn't have a divide instruction.

        ORG     0

; ---------------------------------------------------------------
; INIT - runs once at startup
; Set score to 0, place target at LED 7, build its bit pattern
; ---------------------------------------------------------------
INIT:
        LOADI   0
        STORE   SCORE           ; score starts at 0

        LOADI   7
        STORE   TARGET_IDX      ; target starts at LED position 7

        CALL    MAKE_TARGET     ; convert index 7 to one-hot pattern


; ---------------------------------------------------------------
; GAME LOOP - runs forever
; Every iteration: read knob, find LED position, display, check fire
; ---------------------------------------------------------------
GAME_LOOP:

        ; Step 1: Read the potentiometer value from our ADC peripheral
        ; The peripheral is at I/O address 192 (0xC0)
        ; It returns a 12-bit number from 0 to 4095
        IN      192
        STORE   SCRATCH

        ; Step 2: Our potentiometer doesn't go all the way to 0
        ; It bottoms out around 552 (0x228), so subtract that offset
        ; This gives us a usable range of 0 to 3543
        SUB     ADC_MIN
        JNEG    CLAMP_ZERO      ; if result went negative, clamp to 0
        STORE   SCRATCH
        JUMP    SCALE

CLAMP_ZERO:
        LOADI   0
        STORE   SCRATCH         ; floor the value at 0


        ; Step 3: Map the ADC value (0-3543) to an LED index (0-9)
        ; We can't divide in SCOMP, so we use repeated subtraction instead
        ; Keep subtracting 354 (one bucket) and count how many times it fits
        ; Example: value=1000 -> subtract 354 twice -> index=2 -> LED 2
SCALE:
        LOADI   0
        STORE   IDX             ; start LED index counter at 0

SCALE_LOOP:
        LOAD    SCRATCH
        SUB     BUCKET          ; subtract one bucket worth (354)
        JNEG    SCALE_DONE      ; if negative, we found the right bucket
        STORE   SCRATCH         ; save the remainder
        LOAD    IDX
        ADDI    1               ; move to next LED position
        STORE   IDX
        SUB     NINE            ; make sure we don't go past LED 9
        JPOS    CLAMP_MAX
        JZERO   CLAMP_MAX       ; catch exactly 9 too
        JUMP    SCALE_LOOP

CLAMP_MAX:
        LOADI   9
        STORE   IDX             ; cap at LED 9 (rightmost)

SCALE_DONE:
        ; IDX now has the correct LED position (0=leftmost, 9=rightmost)
        CALL    MAKE_WEAPON     ; convert index to one-hot bit pattern


        ; Step 4: Show both the weapon LED and target LED at the same time
        ; OR the two patterns together so both bits are set
        ; Example: weapon=0001000 target=0100000 -> display=0101000
        LOAD    WEAPON_PAT
        OR      TARGET_PAT      ; combine weapon and target into one value
        OUT     1               ; send to LED port


        ; Step 5: Check if the player is pressing the fire button
        ; Switch 0 is connected to bit 0 of port 0
        ; If the switch is off (0), skip the hit check and loop again
        IN      0               ; read all switches
        AND     BUTTON_MASK     ; isolate just bit 0 (switch 0)
        JZERO   GAME_LOOP       ; switch is off, keep looping


        ; Step 6: Switch is on - check if weapon is on the same LED as target
        ; AND the two one-hot patterns together
        ; If they are on the same position, result is non-zero = hit
        ; If they are on different positions, result is 0 = miss
        LOAD    WEAPON_PAT
        AND     TARGET_PAT      ; non-zero means same LED = hit
        JZERO   MISS            ; zero means different LEDs = miss


        ; Step 7: HIT - increment score and move the target
        LOAD    SCORE
        ADDI    1               ; add 1 to score
        STORE   SCORE
        OUT     4               ; display updated score on HEX display

        ; Move target forward 3 positions
        ; Using modulo 10 to wrap around (9 -> 2, etc.)
        LOAD    TARGET_IDX
        ADDI    3
        STORE   TARGET_IDX

MOD_LOOP:
        LOAD    TARGET_IDX
        SUB     TEN             ; keep subtracting 10 until under 10
        JNEG    MOD_DONE
        STORE   TARGET_IDX
        JUMP    MOD_LOOP

MOD_DONE:
        CALL    MAKE_TARGET     ; rebuild target pattern at new position

        ; Wait for the player to let go of the switch
        ; Without this, one press could score multiple times
WAIT_RELEASE:
        IN      0
        AND     BUTTON_MASK
        JNEG    WAIT_RELEASE    ; still held, keep waiting
        JPOS    WAIT_RELEASE    ; still held, keep waiting

        JUMP    GAME_LOOP       ; switch released, back to game


MISS:
        ; Player fired but weapon and target were on different LEDs
        ; No score change, just loop back
        JUMP    GAME_LOOP


; ---------------------------------------------------------------
; MAKE_WEAPON subroutine
; Input:  IDX = LED position (0-9)
; Output: WEAPON_PAT = one-hot bit pattern
;
; One-hot means exactly one bit is set in the 16-bit value
; We start with 1 (bit 0 set) and shift left IDX times
; Index 0 = 0000000001 (LED 0, leftmost)
; Index 3 = 0000001000 (LED 3)
; Index 9 = 1000000000 (LED 9, rightmost)
; ---------------------------------------------------------------
MAKE_WEAPON:
        LOADI   1               ; start with bit 0 set
        STORE   WEAPON_PAT
        LOAD    IDX
        STORE   SHIFT_CNT       ; shift this many times

MW_LOOP:
        LOAD    SHIFT_CNT
        JZERO   MW_DONE         ; done shifting
        LOAD    WEAPON_PAT
        SHIFT   1               ; shift left by 1 position
        STORE   WEAPON_PAT
        LOAD    SHIFT_CNT
        ADDI    -1              ; decrement counter
        STORE   SHIFT_CNT
        JUMP    MW_LOOP

MW_DONE:
        RETURN


; ---------------------------------------------------------------
; MAKE_TARGET subroutine
; Input:  TARGET_IDX = LED position (0-9)
; Output: TARGET_PAT = one-hot bit pattern
; Same logic as MAKE_WEAPON but uses TARGET_IDX
; ---------------------------------------------------------------
MAKE_TARGET:
        LOADI   1               ; start with bit 0 set
        STORE   TARGET_PAT
        LOAD    TARGET_IDX
        STORE   SHIFT_CNT       ; shift this many times

MT_LOOP:
        LOAD    SHIFT_CNT
        JZERO   MT_DONE         ; done shifting
        LOAD    TARGET_PAT
        SHIFT   1               ; shift left by 1 position
        STORE   TARGET_PAT
        LOAD    SHIFT_CNT
        ADDI    -1              ; decrement counter
        STORE   SHIFT_CNT
        JUMP    MT_LOOP

MT_DONE:
        RETURN


; ---------------------------------------------------------------
; VARIABLES AND CONSTANTS
; Placed at address 256 to stay out of the way of the program code
; ---------------------------------------------------------------
        ORG     256

WEAPON_PAT:  DW  0      ; one-hot pattern for weapon LED position
TARGET_PAT:  DW  0      ; one-hot pattern for target LED position
SCORE:       DW  0      ; current player score
IDX:         DW  0      ; current LED index (0-9) for weapon
SCRATCH:     DW  0      ; temporary variable for ADC math
TARGET_IDX:  DW  7      ; current target LED index (starts at 7)
SHIFT_CNT:   DW  0      ; counter used in shift loops

; Math constants
ADC_MIN:     DW  552    ; potentiometer floor value (0x228 observed on hardware)
BUCKET:      DW  354    ; (4095-552)/10 = 354 steps per LED bucket
NINE:        DW  9      ; used to clamp LED index at maximum of 9
TEN:         DW  10     ; used for modulo 10 when wrapping target position
BUTTON_MASK: DW  1      ; bit mask for switch 0 (fire button)
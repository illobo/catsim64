; ------------------------------------------------------------------ title
; The start screen (title.py): the logo over raster bars, the controls, the
; two cats on the floor, the dub tune. Polled, with interrupts off: bars in
; the top border and behind the logo, black below, the floor colour from
; T_FLOOR_LINE. Ends when fire (port 2) or a mouse button (port 1) is
; pressed and released, with the screen blanked and the SID silent.

jhold    = $20            ; frames the joystick fire has been held (game)
cdark    = $21            ; SX_POKE: subtracted from every SX_CUT (echoes)
smark    = $22            ; SX_POKE: the cat meowing, $ff none
tpose    = $26            ; per cat: 1 if shown meowing
toff     = $24            ; bar scroll
tpress   = $25            ; a button went down

title   lda #0
        sta $d015
        sta $dc02               ; ports in, no keyboard column: joysticks only
        sta $dc03
        sta $d020
        sta $d021
        lda #$0b                ; blank while the screen is set up
        sta $d011
        lda #$33
        sta $01
        ldx #0
-       .for o = 0, o < $400, o += $100
        lda $d800+o,x           ; the lowercase ROM font
        sta charset+o,x
        lda tcharhi+o,x         ; cats and quad blocks as codes $80-$ff
        sta charset+$400+o,x
        .next
        inx
        bne -
        lda #$36
        sta $01
        ldx #0
-       .for o = 0, o < $300, o += $100
        lda tscreen+o,x
        sta SCREEN+o,x
        lda tcolour+o,x
        sta COLRAM+o,x
        .next
        lda tscreen+$2e8,x
        sta SCREEN+$2e8,x
        lda tcolour+$2e8,x
        sta COLRAM+$2e8,x
        inx
        bne -
        lda #$10 | (charset >> 10)
        sta $d018
        lda #$08
        sta $d016
        lda #$ff
        sta smark
        lda #0
        sta tpose
        sta tpose+1
        sta tpress
        sta toff
        sta cdark
        jsr sfx_stop
        ldx #2                  ; the three voices' tracks
-       lda mtrklo,x
        sta sptrl,x
        lda mtrkhi,x
        sta sptrh,x
        dex
        bpl -
        lda #$1b
        sta $d011

tframe   bit $d011               ; wait for the bottom border, then line 0
        bpl tframe
-       bit $d011
        bmi -
        ldx #T_BAR_TOP          ; a colour per line, written at its start
        ldy toff
tbar    lda bartab,y
-       cpx $d012
        bne -
        sta $d020
        sta $d021
        iny
        inx
        cpx #T_BAR_END
        bne tbar
        lda #0
-       cpx $d012
        bne -
        sta $d020
        sta $d021

        ldx #1                  ; a cat that starts or stops meowing:
-       lda #0                  ; redraw it (one cat a frame at most, so
        cpx smark               ; this ends well before the floor line)
        bne +
        lda #1
+       cmp tpose,x
        beq +
        sta tpose,x
        jsr tcat
        jmp tfloor
+       dex
        bpl -

tfloor  ldx #T_FLOOR_LINE       ; the floor colour; the rest of the work
        lda #FLOOR_BG           ; has the lower border and vblank
-       cpx $d012
        bne -
        sta $d021

        jsr sfx
        inc frame
        ldy toff                ; the bars roll down
        dey
        bpl +
        ldy #71
+       sty toff

        lda frame               ; the prompt pulses
        lsr a
        lsr a
        and #7
        tay
        lda tpulse,y
        ldx #79
-       sta COLRAM+T_PROMPT,x
        dex
        bpl -

        lda $dc00               ; fire in port 2, a button in port 1
        and #$10
        beq +
        lda $dc01
        and #$11
        cmp #$11
        bne +
        lda tpress              ; all up: start once one was pressed
        bne tdone
        jmp tframe
+       lda #1
        sta tpress
        jmp tframe

tdone   lda #$0b
        sta $d011
        lda #0
        sta $d020
        sta $d021
        sta $d418
        jmp sfx_stop

tpulse  .byte WHITE, LGREY, GREY, DGREY, DGREY, GREY, LGREY, WHITE

; cat X (0/1) sits (A = 0) or meows (A = 1); keeps X
tcat    sta tmp
        txa
        asl a
        ora tmp
        tay
        lda tfrlo,y
        sta fp
        lda tfrhi,y
        sta fp+1
        lda tboxlo,x
        sta p1
        sta p3
        lda tboxhi,x
        sta p1+1
        clc
        adc #>(COLRAM-SCREEN)
        sta p3+1
        lda fp                  ; codes, then 40 colours
        clc
        adc #40
        sta fc
        lda fp+1
        adc #0
        sta fc+1
        stx cat
        ldx #8*5-1
-       txa
        tay
        lda (fc),y
        sta tmp
        lda (fp),y
        ldy tboxoff,x
        sta (p1),y
        lda tmp
        sta (p3),y
        dex
        bpl -
        ldx cat
        rts

; every voice idle, calls and slides forgotten
sfx_stop
        ldx #sfxstate_end-sptrl-1
        lda #0
-       sta sptrl,x
        dex
        bpl -
        rts

        .include "title.inc"

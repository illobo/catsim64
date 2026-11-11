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
tcnt     = $23            ; bar lines to go
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
        sta cdark
        jsr sfx_stop
        ldx #2                  ; the three voices' tracks
-       lda mtrklo,x
        sta sptrl,x
        lda mtrkhi,x
        sta sptrh,x
        dex
        bpl -
        jsr tbuild
        lda #$1b
        sta $d011

tframe   bit $d011               ; wait for the bottom border, then line 0
        bpl tframe
-       bit $d011
        bmi -
        lda #T_BAR_END-T_BAR_TOP+1-9    ; the lines without the 9 bad ones
        sta tcnt
        jsr tbars

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
        jsr tbuild              ; the bars of the next frame

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

; The bars' colours for the next frame, a line each: black, then every bar
; of tbardef (the farthest first) painted at its place on the sine.
tbuf     = $0334                ; T_BAR_LINES bytes, in one page (tbars)
tbuild  lda #0
        ldx #T_BAR_LINES-1
-       sta tbuf,x
        dex
        bpl -
        ldx #0
tbnext  lda frame
        asl a
        clc
        adc tbardef,x
        tay
        lda tsin,y
        sta tmp
        lda frame
        asl a
        clc
        adc frame
        clc
        adc tbardef+1,x
        tay
        lda tsin,y
        lsr a
        clc
        adc tmp
        tay                     ; the bar's top line
-       lda tbardef+2,x
        bmi +
        sta tbuf,y
        iny
        inx
        bne -
+       inx
        inx
        inx
        cpx #tbardef_end-tbardef
        bne tbnext
        rts

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

;------------------------------------------------------------------- bars
; The raster bars, lines T_BAR_TOP to T_BAR_END-1, border and background,
; then black. Every colour is written in the horizontal blank before its
; line, so nothing shows: cycle-exact from a jitter-free start.
; Cycles count from 0 = the first one a read sees the new $d012 in.
;   sync    the poll finds line 16 with its read at cycle 0-6; three more
;           reads, each a line later at the very end of the line, tell
;           the late from the early and the early wait 4, 2, 1 more
;   a line  63 cycles, $d021 written at cycle 56, $d020 at 60
;   a bad   line (every 8th from 51) halts the CPU from cycle 12 to 54:
;           the line before it runs straight into the halt, the writes
;           wait in it and land at 57 and 61 (the halt must catch the
;           first sta itself: an instruction cut in two by it would end
;           after it and push the writes back), and the seven lines after
;           are exact again
; The colours are tbuf's, a line each, built by tbuild a frame ahead. The
; routine sits in one page and so does tbuf: a branch or an index crossing
; a page would cost a cycle.
TB_SIZE  = 136                  ; tbars' length, at most

        .if (>*) != (>(* + TB_SIZE - 1))
        .align 256
        .fi
tbars   ldx #T_BAR_TOP-4
-       cpx $d012
        bne -
        ldy #7                  ; 54 cycles: the read 60 after the poll's
        jsr tdly
        nop
        nop
        nop
        cpx $d012
        bne +
        nop                     ; still this line: early, 4 more
        bit tmp
+       inx
        ldy #7                  ; 52
        jsr tdly
        nop
        nop
        cpx $d012
        bne +
        bit tmp                 ; 2 more
+       inx
        ldy #8                  ; 53
        jsr tdly
        cpx $d012
        bne +
        nop                     ; 1 more
+       ldx #51-(T_BAR_TOP-1)   ; cycle 4 of line 19; lines to the bad line
        ldy #0
        nop
        nop
        nop
        nop
        jmp tline
tbar    lda tbuf,y              ; 49
        sta $d021               ; written at 56
        sta $d020               ; and 60
        iny                     ; 61
        dex                     ; 0
        beq tbad
        jsr trts                ; 4
        bit tmp
tline   dec tcnt                ; 19
        beq tend
        jsr trts                ; 26
        nop
        nop
        nop
        nop
        jmp tbar
tbad    lda tbuf,y              ; 5 of a bad line: the colour after its own
        ldx #7
        sta $d021               ; 11: halted in it until 55, written at 57
        sta $d020               ; and 61
        iny                     ; 62
        jsr trts                ; 1
        bit tmp
        jmp tline
tend    ldx #4                  ; 27 of line T_BAR_END-1: black from the next
-       dex
        bne -
        bit tmp
        lda #0
        sta $d021               ; written at 56
        sta $d020               ; and 60
        rts
tdly    dey                     ; ldy #n, jsr tdly: 13+5n cycles
        bne tdly
trts    rts
tbars_end

        .include "title.inc"
        .cerror tbars_end - tbars > TB_SIZE, "TB_SIZE too small"
        .cerror (>tbars) != (>(tbars_end - 1)), "tbars crosses a page"
        .cerror (>tbuf) != (>(tbuf + T_BAR_LINES - 1)), "tbuf crosses a page"

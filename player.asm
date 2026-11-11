; ------------------------------------------------------------------ mouse
; 1351 on port 1: POTX/POTY hold the position mod 64 in bits 1-6 (bit 0 is
; noise). The buttons are joystick lines on $DC01: fire = left, up = right.
; Port A bit 7 is low to select port 1's POTs, which also drives keyboard
; column 7: SPACE works as the left button and "1" as the right one.

COUCH_MAXX = 54           ; cat x range on the couch seat
P_STEPY  = 10             ; mouse units per row
P_STEPX  = 4              ; fastest step, 2 px units per frame
PAW_OK   = FEED_EVERY-1500 ; pawing the feeder refills it after 30 s
JOY_X    = 4              ; joystick: mouse units a frame (a 4 px step)
JOY_Y    = 2              ; a row every 5 frames
JOY_NAP  = 40             ; frames of held fire that make the right button

mouse   lda injn                ; test hook
        beq +
        dec injn
        lda injdx
        sta mdx
        lda injdy
        sta mdy
        lda injb
        jmp mbtns
+       lda $d419
        ldy opotx
        jsr movchk
        sty opotx
        sta mdx
        lda $d41a
        ldy opoty
        jsr movchk
        sty opoty
        eor #$ff                ; POTY grows upwards, rows grow down
        clc
        adc #1
        sta mdy
        lda $dc01
        eor #$ff
        ldy #0
        lsr a                   ; C = up = right button
        bcc +
        ldy #2
+       and #8                  ; fire = left button
        beq +
        iny
+       sty tmp2

; a joystick in port 2 works too: it overrides the motion; fire is the left
; button, and held for JOY_NAP frames the right one as well
        lda $dc00
        lsr a
        bcs +
        ldy #256-JOY_Y
        sty mdy
+       lsr a
        bcs +
        ldy #JOY_Y
        sty mdy
+       lsr a
        bcs +
        ldy #256-JOY_X
        sty mdx
+       lsr a
        bcs +
        ldy #JOY_X
        sty mdx
+       lsr a
        bcc +
        lda #0
        sta jhold
        beq jdone
+       ldy jhold
        cpy #JOY_NAP
        bcs +
        iny
        sty jhold
+       lda #1
        cpy #JOY_NAP
        bcc +
        lda #3
+       ora tmp2
        sta tmp2
jdone   ; F1 (keyboard column 0, row 4) changes room. Row 4 is the line of the
        ; left button, and "up" on the joystick pulls column 0 low: F1 is down
        ; if neither is, and the row goes low once column 0 is driven low too.
        lda $dc00
        lsr a
        bcc nof1
        lda $dc01
        and #$10
        beq nof1
        lda #$c1                ; (port A already holds a 0 in bit 0)
        sta $dc02
        lda $dc01
        lda $dc01
        ldy #$c0
        sty $dc02
        and #$10
        bne nof1
        lda tmp2
        ora #4
        sta tmp2
nof1    lda tmp2
mbtns   sta tmp
        eor mbtn
        and tmp
        sta mclick
        lda tmp
        sta mbtn
        lda mdx
        ora mdy
        sta mmove
        lda mdy                 ; "up + button": up counts for a moment, so a
        bpl +                   ; flick of the mouse will do
        lda #10
        sta uprec
        rts
+       lda uprec
        beq +
        dec uprec
+       rts

; A = new POT value, Y = old one -> A = signed motion, Y = value to keep
; (the 1351 manual's routine: changes of one unit are noise)
movchk  sty tmp
        sta tmp2
        sec
        sbc tmp
        and #%01111111
        cmp #%01000000
        bcs +
        lsr a
        beq mnull
        ldy tmp2
        rts
+       ora #%11000000
        cmp #$ff
        beq mnull
        sec
        ror a
        ldy tmp2
        rts
mnull   lda #0
        rts

; ------------------------------------------------------------------ player cat
; cat 0 (X = 0), entered from cat_think with the timers already counted down
player  lda state
        asl a
        tay
        lda pstates+1,y
        pha
        lda pstates,y
        pha
        rts

pstates .word ps_free-1, ps_free-1, ps_free-1, ps_bat-1, ps_jump-1, ps_sleep-1, ps_hiss-1, ps_meow-1
        .word ps_free-1, ps_goeat-1, ps_eat-1, ps_arc-1, ps_scratch-1

; sit or carry: mouse-driven
ps_free lda mclick
        and #2
        beq +
        jmp p_sleep
+       lda mclick
        and #1
        beq p_move
        jmp p_action

p_move  jsr calc_ovl
        ldy plat
        beq pm_floor
        jsr platidx
        lda platx0,y
        sta xmin
        lda platx1,y
        sta xmax
        lda mdy                 ; on furniture: a push down jumps off
        beq pm_x
        bmi pm_x
        clc
        adc accy
        sta accy
        cmp #P_STEPY
        bcc pm_x
        lda #0
        sta accy
        lda #CYMIN
        sta tmp2
        lda cx
        sta tmp
        jsr blocked
        bcs pm_x
        lda #0
        sta plat
        lda #CYMIN
        jmp p_jumpto

pm_floor
        lda #0
        sta xmin
        lda #CXMAX
        sta xmax
        lda mdy
        clc
        adc accy
        sta accy
        bmi pm_up
        cmp #P_STEPY
        bcc pm_x
        lda cy
        cmp #CYMAX
        bcs pm_yend
        adc #1
        bne pm_y
pm_up   cmp #256-P_STEPY+1
        bcs pm_x
        lda cy
        cmp #CYMIN+1
        bcc pm_yend
        sbc #1
pm_y    jsr tryy
pm_yend lda #0
        sta accy

pm_x    lda mdx                 ; step = (accx + mdx) asr 1, the odd bit stays
        clc
        adc accx
        tay
        and #1
        sta accx
        tya
        cmp #$80
        ror a
        beq pm_anim
        bmi pm_left
        cmp #P_STEPX+1
        bcc +
        lda #P_STEPX
+       sta pstep
        lda #0
        sta dir
        lda cx
        clc
        adc pstep
        cmp xmax
        bcc pm_setx
        lda xmax
        bcs pm_setx
pm_left cmp #256-P_STEPX
        bcs +
        lda #256-P_STEPX
+       sta pstep
        lda #1
        sta dir
        lda cx
        clc
        adc pstep
        bcs +                   ; carry clear: went below 0
        lda #0
+       cmp xmin
        bcs pm_setx
        lda xmin
pm_setx cmp cx
        beq pm_edge
        jsr tryx
        jmp pm_anim

; pushing on at the end: the desk's right end and the piano room's left
; edge are the two sides of the door
pm_edge inc edge
        lda edge
        cmp #6
        bcc pm_anim
        lda room
        bne +
        lda plat
        cmp #PL_DESK
        bne pm_anim
        lda dir
        bne pm_anim
        beq pm_door
+       lda plat
        bne pm_anim
        lda dir
        beq pm_anim
pm_door lda #1
        sta roomreq

pm_anim jsr p_settle
        lda moved
        beq pm_idle
        lda #0
        sta idle
        sta edge
        inc anim
        lda anim
        lsr a
        lsr a
        and #3
        sta pose
        rts
pm_idle lda idle
        cmp #6
        bcc +                   ; keep the run frame for a moment
        lda frame
        adc catphase
        and #127
        cmp #9
        lda #P_SIT0
        bcs ++
        lda #P_SIT1
        bne ++
+       inc idle
        rts
+       sta pose
        rts

; state = carry if the ball is in my mouth, else sit
p_settle
        lda owner
        beq +
        lda #S_SIT
        .byte $2c
+       lda #S_CARRY
        sta state
        rts

p_jumpto
        sta ty
        lda cx
        sta tx
        lda #S_TOBED
        sta state
        rts

; ---- jumping on or off the couch: a row every other frame
ps_jump lda #P_JUMP
        sta pose
        lda frame
        and #1
        bne +
        jsr calc_ovl
        lda cy
        cmp ty
        beq p_landed
        bcc ++
        sbc #1
        jsr tryy
        lda moved
        beq p_landed
+       rts
+       adc #1
        jsr tryy
        lda moved
        beq p_landed
        rts
p_landed
        jsr p_settle
        lda #P_SIT0
        sta pose
        lda #0
        sta accy
        sta idle
        rts

; ---- left button
p_action
        lda uprec               ; with "up": leap from a spot
        beq +
        jsr find_spot
        bcc +
        lda spbox,y             ; (remember what to do if we can't)
        lda sptx,y
        jsr arc_spot
        bcc +
        rts
+       lda owner               ; carrying: toss it
        bne +
        jsr kick
        jmp p_paw
+       jsr near_ball
        bcc p_nocat
        lda owner
        bmi p_grab
        tay                     ; the grey cat has it: steal, it hisses
        jsr hiss_at
p_grab  lda #FX_GRAB
        jsr sfx_play
        lda #0
        sta owner
        lda #S_CARRY
        sta state
        rts

p_nocat jsr find_spot           ; at a spot?
        bcc p_boop
        cpy #0
        bne +
        lda dir                 ; the couch's very end, facing the desk: leap
        bne p_boop
        lda cx
        cmp #COUCH_MAXX-10
        bcc p_boop
        jsr arc_spot
        bcc p_boop
        rts
+       lda spbox,y             ; something to scratch
        bmi p_boop
        jmp scratch_start

p_boop  lda cx                  ; the other cat within a paw's reach?
        sta tmp
        lda cx+1
        jsr absdiff
        cmp #32                 ; (26 is touching)
        bcs p_feeder
        lda cy
        sta tmp
        lda cy+1
        jsr absdiff
        cmp #7
        bcs p_feeder
        lda cx+1                ; boop! face it
        cmp cx
        lda #0
        rol a
        eor #1
        sta dir
        ldy #1
        lda state+1
        cmp #S_SLEEP            ; a sleeping or eating cat hisses
        beq +
        cmp #S_EAT
        beq +
        cmp #S_HISS
        bcc p_meowback
        jmp p_paw               ; already hissing or meowing
p_meowback
        ldx #1                  ; anything else meows back
        stx cat
        jsr start_meow
        ldx #0
        stx cat
        jmp p_paw
+       jsr hiss_at
        jmp p_paw

p_feeder
        lda room                ; (the living room's floor only)
        ora plat
        bne p_couch
        lda cy
        cmp #FEED_CY+4
        bcs p_couch
        lda cx
        cmp #FEED_LX-6
        bcc p_couch
        cmp #FEED_RX+7
        bcs p_couch
        lda food
        beq p_pawbowl
        lda cx                  ; the near side of the bowl, or the other
        cmp #(FEED_LX+FEED_RX)/2
        lda #FEED_LX
        bcc +
        lda #FEED_RX
+       sta tx
        jsr eatspot
        bcc +
        lda #FEED_LX+FEED_RX
        sec
        sbc tx
        sta tx
        jsr eatspot
        bcs p_meowj
+       lda #FEED_CY
        sta ty
        lda #S_GOEAT
        sta state
        rts

p_pawbowl
        lda cx                  ; face the bowl and paw at it
        cmp #(FEED_LX+FEED_RX)/2
        lda #0
        rol a
        sta dir
        lda fth                 ; long enough since the last meal: refill
        cmp #>PAW_OK
        bcc +
        bne p_tock
        lda ftl
        cmp #<PAW_OK
        bcs p_tock
+       lda #1
        sta ftl
        lda #0
        sta fth
        jmp p_paw
p_tock  lda #FX_KICK
        jsr sfx_play
        jmp p_paw
p_meowj jmp start_meow

p_couch lda plat                ; in front of furniture: jump up
        bne p_meow
        lda cy
        cmp #CYMIN+2
        bcs p_meow
        lda room
        asl a
        tay
        jsr p_onto
        bcs +
        lda room
        asl a
        tay
        iny
        jsr p_onto
        bcc p_meow
+       rts

; platform (table index Y) within reach and free: hop onto it, carry set
p_onto  lda platjmp,y
        beq po_no
        lda cx
        clc
        adc #14
        cmp platx0,y
        bcc po_no
        lda platx1,y
        clc
        adc #14
        cmp cx
        bcc po_no
        lda cx                  ; the nearest place on it
        cmp platx0,y
        bcs +
        lda platx0,y
+       cmp platx1,y
        bcc +
        lda platx1,y
+       sta tx
        sta tmp
        lda platcy,y
        sta ty
        sta tmp2
        tya
        and #1
        clc
        adc #1
        sta arcplat
        lda #0
        sta arcev
        jsr overlaps            ; the other cat sleeps there
        bcs po_no
        lda #2
        jsr arc_go
        sec
        rts
po_no   clc
        rts

p_meow  jmp start_meow

; swipe pose for a moment
p_paw   lda #S_BAT
        sta state
        lda #12
        sta timer
        lda #P_BAT
        sta pose
        rts

; carry set if spot tx, FEED_CY would overlap the grey cat
eatspot lda tx
        sta tmp
        lda #FEED_CY
        sta tmp2
        jmp overlaps

; cat Y hisses (at the player)
hiss_at lda #S_HISS
        sta state,y
        lda #45
        sta timer,y
        lda #SPRBASE+SPR_HISS
        sta word,y
        lda #60
        sta wtime,y
        lda #P_HISS
        sta pose,y
        lda #FX_HISS
        jmp sfx_play

; carry set if the ball (free or in the grey cat's mouth) is within reach
near_ball
        lda bzh
        cmp #16
        bcs nb_no
        lda cy
        asl a
        asl a
        asl a
        adc #39
        sec
        sbc byh
        clc
        adc #14
        cmp #29
        bcs nb_no
        jsr mouth_x
        sec
        lda t16
        sbc bxl
        sta t16
        lda t16+1
        sbc bxh
        bne +
        lda t16
        cmp #15
        bcs nb_no
        sec
        rts
+       cmp #$ff
        bne nb_no
        lda t16
        cmp #256-14
        bcc nb_no
        rts                     ; carry set from cmp
nb_no   clc
        rts

; ---- right button: nap wherever you are
p_sleep jsr drop_if_owner
        lda #S_SLEEP
        sta state
        lda #0
        sta zph
        sta wake
        rts

; ---- the other states: motion or a click hands control back
ps_sleep
        lda mclick
        bne pwake
        lda mdx                 ; wake = |dx| + |dy| summed
        jsr absa
        sta tmp
        lda mdy
        jsr absa
        clc
        adc tmp
        adc wake
        bcs pwake
        sta wake
        cmp #40
        bcs pwake
        lda frame
        adc catphase
        and #64
        beq +
        lda #1
+       clc
        adc #P_SLEEP0
        sta pose
        lda frame
        and #1
        bne +
        inc zph
        lda zph
        cmp #48
        bcc +
        lda #0
        sta zph
+       rts
pwake   jsr p_settle
        lda #P_SIT0
        sta pose
        lda #0
        sta idle
        rts

absa    bpl +
        eor #$ff
        clc
        adc #1
+       rts

ps_bat  lda #P_BAT
        sta pose
        lda timer
        bne +
        jsr p_settle
+       rts

ps_hiss lda #P_HISS
        sta pose
        jmp p_wait

ps_meow lda #P_MEOW
        sta pose
p_wait  lda timer
        beq +
        lda mmove
        ora mclick
        bne +
        rts
+       jsr p_settle
        jmp ps_free

ps_goeat
        lda food
        beq +
        lda mmove
        ora mclick
        bne +
        jsr move_run
        lda cx
        cmp tx
        bne ++
        lda cy
        cmp ty
        bne ++
        lda #S_EAT
        sta state
        lda tx
        cmp #FEED_RX
        lda #0
        rol a
        sta dir
        rts
+       jsr p_settle
        jmp ps_free
+       rts

ps_eat  lda mmove
        ora mclick
        beq +
        jsr p_settle
        jmp ps_free
+       jmp st_eat

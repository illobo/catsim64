; ------------------------------------------------------------------ rooms
; Two rooms share the screen: 0 the living room, 1 the piano room. Each is
; stored packed (gen.py lz) and unpacked into the live background copy
; (bgscreen/bgcolour, RAM under the KERNAL) on entry. Furniture a cat can
; stand on is a "platform" (two per room); "spots" are places where the
; left button does something special: an arc jump (with up) or scratching.

; platforms, index room*2 + plat-1
PL_COUCH = 1
PL_DESK  = 2
PL_SOFA  = 1
PL_PIANO = 2
platcy  .byte BED_CY, DESK_CY, SOFA_CY, PIANO_CY
platx0  .byte 0, DESK_X0, SOFA_X0, PIANO_X0
platx1  .byte COUCH_MAXX, DESK_X1, SOFA_X1, PIANO_X1
platjmp .byte 1, 0, 1, 1        ; the left button in front of it jumps up

; per room
rwall   .byte WALL_BG, WALL_BG2
rfloor  .byte FLOOR_BG, FLOOR_BG2
rcatcol .byte LGREY, CAT2_BODY  ; the room's own cat
rball0  .byte RED, BALL2_STRAND
rball1  .byte LRED, BALL2_DISC
rscrlo  .byte <room0scr, <room1scr
rscrhi  .byte >room0scr, >room1scr
rcollo  .byte <room0col, <room1col
rcolhi  .byte >room0col, >room1col
raicx   .byte 100, 56           ; where the room's cat starts
raicy   .byte 18, 17
rbedx   .byte 6, SOFA_X1        ; ...and sleeps (the right end of the couch stays free)
rbedmin .byte 0, SOFA_X0
rbedmax .byte COUCH_MAXX, SOFA_X1
rpcx    .byte DESK_X1, 2        ; where the player comes in
rpcy    .byte DESK_CY, 14
rpdir   .byte 1, 0
rpplat  .byte PL_DESK, 0

; spots: 0 the couch's right end -> the desk; 1/2 right/left of the palm
; (scratch it, or jump over it); 3 at the sofa's arm (scratch, or jump onto
; the sofa over it); 4 on the sofa (back over the arm)
NSPOTS   = 5
sproom  .byte 0, 1, 1, 1, 1
spplat  .byte PL_COUCH, 0, 0, 0, PL_SOFA
spcx    .byte COUCH_MAXX-12, PLANT_SCR_CX, PLANT_LEFT_CX, SOFA_SCR_CX, SOFA_X0
sptol   .byte 13, 7, 5, 7, 8
spdir   .byte 0, 1, 0, 0, 1
spbox   .byte $ff, 0, 0, 1, $ff ; what gets scratched
sptplat .byte PL_DESK, 0, 0, PL_SOFA, 0
sptx    .byte DESK_X0+2, PLANT_LEFT_CX, PLANT_SCR_CX, SOFA_X0, SOFA_SCR_CX
sptcy   .byte DESK_CY, $ff, $ff, SOFA_CY, SOFA_SCR_CY   ; $ff: the row it is in

; scratched things: the cells of this colour in the box flicker
boxlo   .byte <PLANT_POS, <ARM_POS
boxhi   .byte >PLANT_POS, >ARM_POS
boxw    .byte PLANT_W, ARM_W
boxh    .byte PLANT_H, ARM_H
boxfrom .byte GREEN, LRED
boxto   .byte LGREEN, WHITE

; Y = table index of the player's platform
platidx lda room
        asl a
        clc
        adc plat
        tay
        dey
        rts

; ---- unpack (fp) to (dst): 0 end, 1-$7f literals, $80+n copy n+2 bytes
; from <next byte>+1 back
unlz    ldy #0
        lda (fp),y
        bne +
        rts
+       tax
        jsr fpinc
        txa
        bmi ulmatch
-       lda (fp),y
        sta (dst),y
        jsr fpinc
        inc dst
        bne +
        inc dst+1
+       dex
        bne -
        beq unlz
ulmatch and #$7f
        tax
        inx
        inx
        clc                     ; p1 = dst - offset - 1
        lda dst
        sbc (fp),y
        sta p1
        lda dst+1
        sbc #0
        sta p1+1
        jsr fpinc
-       lda (p1),y
        sta (dst),y
        inc p1
        bne +
        inc p1+1
+       inc dst
        bne +
        inc dst+1
+       dex
        bne -
        beq unlz

fpinc   inc fp
        bne +
        inc fp+1
+       rts

; ---- room A: background, colours, its cat and ball at their default spots.
; The screen is blank (or about to be redrawn) while this runs.
room_load
        sta room
        tax
        beq +
        stx seen2               ; been to the piano room
+
        lda rwall,x
        sta wallbg
        lda rfloor,x
        sta floorbg
        lda rcatcol,x
        sta catpal+5
        lda rball0,x
        sta $d027
        lda rball1,x
        sta $d028
        lda rbedx,x
        sta bedx
        lda rbedmin,x
        sta bedmin
        lda rbedmax,x
        sta bedmax
        lda platcy              ; the bed is platform 1
        cpx #0
        beq +
        lda platcy+2
+       sta bedcy
        lda rscrlo,x
        sta fp
        lda rscrhi,x
        sta fp+1
        lda #<bgscreen
        sta dst
        lda #>bgscreen
        sta dst+1
        jsr unlz
        ldx room
        lda rcollo,x
        sta fp
        lda rcolhi,x
        sta fp+1
        lda #<bgcolour
        sta dst
        lda #>bgcolour
        sta dst+1
        jsr unlz
        lda room
        bne +
        lda lamp                ; the lamp stays broken
        beq +
        lda #1
        jsr lamp_patch
        lda #2
        jsr lamp_patch
+       ldx #0
-       .for o = 0, o < $300, o += $100
        lda bgscreen+o,x
        sta SCREEN+o,x
        lda bgcolour+o,x
        sta COLRAM+o,x
        .next
        lda bgscreen+$2e8,x
        sta SCREEN+$2e8,x
        lda bgcolour+$2e8,x
        sta COLRAM+$2e8,x
        inx
        bne -

        ldx room                ; the room's cat
        lda raicx,x
        sta cx+1
        lda raicy,x
        sta cy+1
        lda #1
        sta dir+1
        lda #110
        sta timer+1
        lda #150
        sta energy+1
        lda #P_SIT0
        sta pose+1
        lda #S_SIT
        sta state+1
        lda #0
        sta wtime+1
        sta plat+1
        sta scrlit
        sta lpend
        lda #<450
        sta mtl+1
        lda #>450
        sta mth+1
        lda #$ff
        sta pkey
        sta pkey+1

        ldx #vzh-bxf            ; the ball
        lda #0
-       sta bxf,x
        dex
        bpl -
        lda #160
        sta bxl
        lda #170
        sta byh
        lda #$ff
        sta owner

        lda room
        bne +
        ldx #2                  ; remember the cells under the kibble
-       lda bgscreen+KIBBLE_POS,x
        sta kiborig,x
        lda bgcolour+KIBBLE_POS,x
        sta kibocol,x
        dex
        bpl -
        lda #$ff                ; draw the pile again
        sta flevel
        sta crazy               ; and restart the monitor
+       rts

; ---- change to room A through the door: the player lands on the other
; room's entry spot
room_go pha
        jsr hint_off
        ldx #0
        stx cat
        jsr drop_if_owner
        lda #$0b
        sta $d011
        lda lamp                ; shade in mid-air: it's on the floor by the time we're back
        cmp #1
        bne +
        jsr lamp_down
+       lda room
        bne +
        lda food                ; the bowl waits
        sta foodsave
        lda #0
        sta food
        beq ++
+       lda foodsave
        sta food
+       pla
        jsr room_load
        ldx room
        lda rpcx,x
        sta cx
        lda rpcy,x
        sta cy
        lda rpdir,x
        sta dir
        lda rpplat,x
        sta plat
        lda #S_SIT
        sta state
        lda #P_SIT0
        sta pose
        lda #0
        sta accx
        sta accy
        sta edge
        sta idle
        sta wtime
        sta roomreq
        ldx #1
-       jsr cat_offset
        lda off
        sta oldlo,x
        lda off+1
        sta oldhi,x
        dex
        bpl -
        lda #0
        sta vsync
-       lda vsync
        beq -
        jsr cats_draw
        jsr sprites
        lda #$1b
        sta $d011
        rts

; F1, or the player pushed through a door
room_check
        lda mclick
        and #4
        bne +
        lda roomreq
        beq ++
+       lda room
        eor #1
        jmp room_go
+       rts

; ---- once a frame, after the cats
roomfx  lda flash               ; border flash
        beq +
        dec flash
        ldx flash
        lda flashtab,x
        sta $d020
+       lda room
        bne room1fx
        jsr terminal
        jsr stars
        jsr feeder
        jsr hint_run
        jmp lamp_run

room1fx lda state               ; what the player scratches flickers
        cmp #S_SCRATCH
        bne +
        lda frame
        and #3
        bne ++
        lda #1
        sta scrlit
        lda frame
        and #4
        beq boxcol              ; A = 0: as it was
        ldx scrbox
        lda boxto,x
        bne boxcol
+       lda scrlit
        beq +
        lda #0
        sta scrlit
        beq boxcol
+       rts

; the box's cells get colour A (0: their own); cells a cat covers stay
boxcol  sta tmp2
        ldy scrbox
        lda boxlo,y
        sta off
        lda boxhi,y
        sta off+1
        jsr setptrs
        ldy scrbox
        lda boxh,y
        sta tmp
bcrow   ldx scrbox
        ldy boxw,x
        dey
-       lda (p1),y
        cmp (p2),y
        bne +
        lda (p4),y
        cmp boxfrom,x
        bne +
        lda tmp2
        bne bc1
        lda (p4),y
bc1     sta (p3),y
+       dey
        bpl -
        jsr add40
        dec tmp
        bne bcrow
        rts

flashtab .byte BLACK, DGREY, RED, ORANGE, YELLOW, WHITE, YELLOW, WHITE, LRED, WHITE, YELLOW, WHITE

; ------------------------------------------------------------------ lamp
; lamp: 0 whole, 1 the shade is falling (sprite 3), 2 broken for good
lamp_hit
        lda lamp
        bne +
        inc lamp
        lda #1
        sta lpend
        lda #SHADE_Y0
        sta lampy
        lda #SHADE_X0
        sta lampx
        lda #0
        sta lampvy
        lda #YELLOW
        sta $d02a
        lda #%11101000
        sta $d017
        sta $d01d
        lda #FX_KICK
        jsr sfx_play
+       rts

lamp_run
        lda lamp
        cmp #1
        bne +
        inc lampvy
        lda lampvy
        lsr a
        lsr a
        clc
        adc lampy
        sta lampy
        lda frame
        lsr a
        bcc lr1_
        lda lampx
        cmp #SHADE_X1
        beq lr1_
        dec lampx
lr1_    lda lampy
        cmp #SHADE_Y1
        bcc +
        lda #2
        sta lpend
        lda #8
        sta flash
        lda #FX_CRASH
        jsr sfx_play
        lda #FX_TINKLE
        jsr sfx_play
lamp_down
        lda #2
        sta lamp
        lda #WHITE
        sta $d02a
        lda #%11100000
        sta $d017
        sta $d01d
+       rts

; patch A (1: shade gone, 2: shade on the floor) into screen and background
lamp_patch
        ldx #<lamppatch1
        ldy #>lamppatch1
        cmp #1
        beq +
        ldx #<lamppatch2
        ldy #>lamppatch2
+       stx fp
        sty fp+1
        lda #0
        sta lpend
-       ldy #0
        lda (fp),y
        bmi +
        sta off+1
        iny
        lda (fp),y
        sta off
        jsr setptrs
        ldy #2
        lda (fp),y
        ldy #0
        sta (p1),y
        sta (p2),y
        ldy #3
        lda (fp),y
        ldy #0
        sta (p3),y
        sta (p4),y
        clc
        lda fp
        adc #4
        sta fp
        bcc -
        inc fp+1
        bne -
+       rts

; between restoring and drawing the cats: what changed in the background
bghook  lda lpend
        beq +
        jsr lamp_patch
+       lda room
        bne +
        ; the monitor's text lives in the background copy (a cat on the
        ; desk stands in front of it): what the terminal changed goes on
        ; screen here
        lda bgcolour+LED_POS
        sta COLRAM+LED_POS
        lsr tdirty
        bcc bh_col
        ldx #TERM_W-1
-       .for r = 0, r < TERM_H, r += 1
        lda bgscreen+(TERM_Y+r)*40+TERM_X,x
        sta SCREEN+(TERM_Y+r)*40+TERM_X,x
        .next
        dex
        bpl -
bh_col  lsr tdirty
        bcc +
        ldx #TERM_W-1
-       .for r = 0, r < TERM_H, r += 1
        lda bgcolour+(TERM_Y+r)*40+TERM_X,x
        sta COLRAM+(TERM_Y+r)*40+TERM_X,x
        .next
        dex
        bpl -
+       rts

; ------------------------------------------------------------------ hint
; The player has landed on the desk: the grey cat looks at the viewer and
; "says" GO RIGHT TO ENTER THE NEXT ROOM in meows (hintfx, gen.py), wherever
; it is and whatever it was doing. The script pokes the number of words said
; so far into hintw; they appear on the top wall row (screen only: no cat
; gets there, and the background copy has what was there), stay two seconds
; and go. Leaving the desk or the room ends it at once. Only until the
; player has seen the piano room (seen2).
hint_start
        jsr hint_off
        ldx #1
        stx cat
        jsr meow_pose
        lda #HINT_FRAMES+10
        sta timer+1
        sta wtime+1
        lda #FX_HINT
        jsr sfx_play
        lda #1                  ; GO
        sta hintw
        ldx #0
        stx cat
        rts

hint_run
        lda hintw
        ora hinton
        beq hr_out
        lda plat
        cmp #PL_DESK
        bne hint_off
        lda hintw
        cmp #8
        bcs +
        lda state+1             ; the cat was cut short: show it all
        cmp #S_MEOW
        beq +
        lda #8
        sta hintw
+       lda hintw
        cmp hinton
        beq hr_same
        ldy hinton              ; first word: a blank band for the line
        sta hinton
        tax
        cpy #0
        bne +
        ldy #HINT_LEN+1
        lda #32
-       sta SCREEN+HINT_POS-1,y
        dey
        bpl -
+       ldy hintend,x
        dey
-       lda hinttext,y
        sta SCREEN+HINT_POS,y
        lda #WHITE
        sta COLRAM+HINT_POS,y
        dey
        bpl -
        lda #110                ; once all is said it stays two seconds
        sta hintt
hr_out  rts
hr_same cmp #8
        bcc hr_out
        dec hintt
        bne hr_out
        beq hint_clr

; hint gone, the cat silent
hint_off
        lda hintw
        ora hinton
        beq hr_out
        lda state+1
        cmp #S_MEOW
        bne hint_clr
        lda hintw
        cmp #8
        bcs hint_clr
        sei                     ; stop the phrase
        lda #0
        sta sptrh+1
        sta reth+1
        sta pslc+1
        sta cslc+1
        sta $d40b
        cli
        lda #1
        sta timer+1
        sta wtime+1
hint_clr
        lda #0
        sta hintw
        sta hinton
        ldy #39
-       lda bgscreen,y
        sta SCREEN,y
        lda bgcolour,y
        sta COLRAM,y
        dey
        bpl -
        rts

; ------------------------------------------------------------------ spots
; carry set, Y = the spot the player stands at
find_spot
        ldy #NSPOTS-1
-       lda sproom,y
        cmp room
        bne ++
        lda spplat,y
        cmp plat
        bne ++
        lda cx
        sec
        sbc spcx,y
        bcs +
        eor #$ff
        adc #1
+       cmp sptol,y
        bcs +
        lda plat
        bne fs_yes
        lda cy                  ; on the floor: close to the wall
        cmp #CYMIN+4
        bcs +
fs_yes  sec
        rts
+       dey
        bpl -
        clc
        rts

; leap from spot Y; carry clear if the other cat sits where it would land
arc_spot
        lda sptx,y
        sta tx
        sta tmp
        lda sptcy,y
        bpl +
        lda cy
+       sta ty
        sta tmp2
        lda sptplat,y
        sta arcplat
        lda #0
        cpy #0
        bne +
        lda #1                  ; the leap to the desk: flash, lamp
+       sta arcev
        jsr overlaps
        bcs +
        lda #1
        jsr arc_go
        sec
        rts
+       clc
        rts

; fly to tx/ty (platform arcplat) in 32/A frames
arc_go  sta arcspd
        lda #0
        sta arct
        sta arcxl
        lda #$80
        sta arcyl
        lda cy
        sta arcyh
        sec
        lda tx
        sbc cx
        beq +
        ldy #0
        bcs ag1_
        iny
ag1_    sty dir
+       jsr arcmul
        lda t16
        sta arcsxl
        lda t16+1
        sta arcsxh
        sec
        lda ty
        sbc cy
        jsr arcmul
        lda t16
        sta arcsyl
        lda t16+1
        sta arcsyh
        lda #S_ARC
        sta state
        lda #P_JUMP
        sta pose
        rts

; t16 = signed A * 8 * arcspd
arcmul  sta t16
        ldy #0
        cmp #$80
        bcc +
        dey
+       sty t16+1
        ldy arcspd
        iny
        iny
-       asl t16
        rol t16+1
        dey
        bne -
        rts

; ---- in the air
ps_arc  lda #P_JUMP
        sta pose
        clc
        lda arcxl
        adc arcsxl
        sta arcxl
        lda cx
        adc arcsxh
        sta cx
        clc
        lda arcyl
        adc arcsyl
        sta arcyl
        lda arcyh
        adc arcsyh
        sta arcyh
        lda arct
        clc
        adc arcspd
        sta arct
        tay
        lda lift,y              ; 1/16 rows
        asl a
        asl a
        asl a
        asl a
        sta tmp
        lda lift,y
        lsr a
        lsr a
        lsr a
        lsr a
        sta tmp2
        sec
        lda arcyl
        sbc tmp
        lda arcyh
        sbc tmp2
        sta cy
        lda arcev
        beq ++
        cpy #6
        bne +
        lda #12
        sta flash
+       cpy #10
        bne +
        jsr lamp_hit
        ldy arct
+       cpy #32
        bcc +
        lda tx
        sta cx
        lda ty
        sta cy
        lda arcplat
        sta plat
        lda #FX_BOUNCE
        jsr sfx_play
        lda arcev               ; on the desk: the grey cat has a hint,
        beq pa_land             ; until the player has been next door
        lda seen2
        bne pa_land
        jsr hint_start
pa_land jmp p_landed
+       rts

; ---- scratching at spot Y: four swipes
scratch_start
        lda spcx,y
        sta cx
        lda spdir,y
        sta dir
        lda spbox,y
        sta scrbox
        lda #4
        sta scrn
        lda #0
        sta timer
        sta wake
        lda #S_SCRATCH
        sta state
        rts

ps_scratch
        lda mdx                 ; walking off ends it
        jsr absa
        sta tmp
        lda mdy
        jsr absa
        clc
        adc tmp
        adc wake
        sta wake
        cmp #24
        bcs ++
        lda timer
        bne +
        lda scrn
        beq ++
        dec scrn
        lda #12
        sta timer
        lda #FX_SCRATCH
        jsr sfx_play
+       lda timer
        cmp #5
        lda #P_BAT
        bcs sc1_
        lda #P_SIT0
sc1_    sta pose
        rts
+       jmp p_landed

; ------------------------------------------------------------------ piano
; cat X on the keys: every new key (2 px units) plays its note, on voices
; 1 and 2 in turn so the notes ring into each other; voice 2 is tuned a
; little sharp, as a saloon piano should be
piano   lda room
        beq pn_out
        lda cy,x
        cmp #PIANO_CY
        bne pn_off
        lda cx,x
        sec
        sbc #PIANO_X0
        bcc pn_off
        cmp #PIANO_X1-PIANO_X0+1
        bcs pn_off
        lsr a
        cmp pkey,x
        beq pn_out
        sta pkey,x
        tay
        lda pvoice
        eor #1
        sta pvoice
        bne +
        lda pianolo,y
        sta $d400
        lda pianohi,y
        sta $d401
        lda #FX_PIANO
        jmp sfx_play
+       lda pianolo,y           ; f + f/128: about 13 cents
        asl a
        lda pianohi,y
        rol a
        clc
        adc pianolo,y
        sta $d407
        lda pianohi,y
        adc #0
        sta $d408
        lda #FX_PIANO2
        jmp sfx_play
pn_off  lda #$ff
        sta pkey,x
pn_out  rts

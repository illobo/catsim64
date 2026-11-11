; Cat Simulator 64: the PETSCII cats living room, but the orange cat is yours.
; A 1351 mouse on port 1 moves it; the right button naps, the left button
; interacts with whatever is in reach (ball, other cat, feeder, couch) and
; meows when nothing is. The grey cat lives its own life as before.
; Build: python3 gen.py && 64tass -C -a -o catsim.prg catsim.asm
;
; Raster chain: line 170 switches $D021 from the room's wall colour to its
; floor colour, line 252 restores it, writes the sprite shadow registers and
; runs the SFX. The main loop runs once per frame after that: restore + redraw
; both cats from the background copy, then the cat AI, ball physics, sprites
; and the room's own things (rooms.asm: two rooms, the lamp, the piano).
; After the title the game runs with $01 = $35: cat frames under the BASIC
; ROM, the background copy under the KERNAL, own IRQ entry at $fffe.

SCREEN   = $0400
COLRAM   = $d800
SPRBASE  = $2000 / 64

CYMIN    = 11             ; floor rows for the cat box (ground = cy*8+39)
CYMAX    = 20
CXMAX    = 128            ; cat x in 2 px units
BYMIN    = 130            ; ball ground y range
BYMAX    = 196
BED_CY   = 8              ; on the couch seat
GRAV     = $28

S_SIT    = 0
S_CHASE  = 1
S_CARRY  = 2
S_BAT    = 3
S_TOBED  = 4
S_SLEEP  = 5
S_HISS   = 6
S_MEOW   = 7
S_ROAM   = 8
S_GOEAT  = 9
S_EAT    = 10
S_ARC    = 11             ; player: flying in an arc
S_SCRATCH = 12            ; player: scratching the furniture
bgscreen = $e000          ; the live background copy: RAM under the KERNAL
bgcolour = $e400
FEED_FIRST = 1200         ; frames until the first meal (24 s)
FEED_EVERY = 3000         ; then every 60 s
FOOD     = 24             ; a small portion: ~4 s for two cats
MEOW0    = 550            ; frames between "look at the viewer and meow"
MEOW1    = 700

; zero page
frame    = $02
vsync    = $03
seed     = $04            ; 2 bytes
cat      = $06
palbase  = $07
moved    = $08
tmp      = $09
tmp2     = $0a
p1       = $10            ; screen
p2       = $12            ; bg screen
p3       = $14            ; colour RAM
p4       = $16            ; bg colour
fp       = $18
fc       = $1a
off      = $1c
t16      = $1e

cx       = $30            ; per-cat arrays, index 0/1
cy       = $32
dir      = $34            ; 0 right, 1 left
pose     = $36
state    = $38
timer    = $3a
anim     = $3c
energy   = $3e
tx       = $40
ty       = $42
oldlo    = $44
oldhi    = $46
word     = $48            ; sprite frame of the speech word
wtime    = $4a
zph      = $4c
edec     = $4e
mtl      = $94            ; meow countdown lo/hi
mth      = $96
food     = $98            ; kibble left in the bowl
ftl      = $99            ; feeder countdown
fth      = $9a
flevel   = $9b            ; kibble pile shown (0-3)

opotx    = $a0            ; mouse: last POT values
opoty    = $a1
mbtn     = $a2            ; buttons held: 1 left, 2 right
mclick   = $a3            ; buttons pressed this frame
mdx      = $a4            ; signed motion this frame
mdy      = $a5
accx     = $a6            ; motion not yet turned into steps
accy     = $a7
idle     = $a8            ; frames without motion
wake     = $a9            ; motion while asleep
mmove    = $aa            ; nonzero if the mouse moved this frame
injdx    = $ab            ; test hook: injdx, injdy, injb are used instead
injdy    = $ac            ; of the mouse for injn frames (write injn last)
injb     = $ad
injn     = $ae
ovl      = $af            ; 1 if the cats already overlap (any step allowed)
pstep    = $b0
lbars    = $b1            ; loader bars on the monitor
ckey     = $b2            ; last C= key state ($20 = up)
lastf    = $b3            ; per cat: frame shown last (pose*4+phase | dir<<7)
fcnt     = $b7            ; draw: cells left
fchg     = $b8            ; draw: frame changed, copy the bitmaps
fdyn     = $b9            ; draw: 0 / 40, the cat's first dynamic char
dst      = $bc
drawend  = $be            ; raster line when cats_draw finished (debug)
drawmax  = $bf

bxf      = $50            ; ball x: frac, lo, hi (pixels)
bxl      = $51
bxh      = $52
vxl      = $53            ; signed 1/256 px per frame
vxh      = $54
byf      = $55            ; ball ground y
byh      = $56
vyl      = $57
vyh      = $58
bzf      = $59            ; height above ground
bzh      = $5a
vzl      = $5b
vzh      = $5c
rotl     = $5d
roth     = $5e
owner    = $5f            ; $ff free, else cat index

tptr     = $60
twait    = $62
trow     = $63
tcol     = $64
sp       = $66            ; SFX player: script pointer
rofs     = $68            ; SID register offset of the voice
sfxv     = $69            ; voice being run
sfxx     = $6a
sfxy     = $6b
cutoff   = $6c            ; filter cutoff (high byte)
purring  = $6d
sidmodel = $6e            ; 0 = 6581, 1 = 8580 (detected at start)

tbase    = $91            ; monitor script: where $ff loops to
irqt     = $93            ; the bottom IRQ's own scratch byte

room     = $c0            ; 0 living room, 1 piano room
wallbg   = $c1            ; $d021 above / below the split
floorbg  = $c2
plat     = $c3            ; per cat: 0 floor, 1/2 the room's furniture
arct     = $c5            ; arc jump: progress 0-32
arcspd   = $c6            ; ...added a frame
arcxl    = $c7            ; x fraction (cx is the high byte)
arcsxl   = $c8            ; x step
arcsxh   = $c9
arcyl    = $ca            ; straight-line y
arcyh    = $cb
arcsyl   = $cc
arcsyh   = $cd
arcplat  = $ce            ; platform it lands on
arcev    = $cf            ; 1: the leap to the desk (flash, lamp)
flash    = $d0            ; border flash countdown
lamp     = $d1            ; 0 whole, 1 shade falling, 2 broken
lampy    = $d2
lampvy   = $d3
lampx    = $d4
lpend    = $d5            ; lamp patch to apply before the cats are drawn
crazy    = $d6            ; the monitor runs the cat-on-keyboard script
uprec    = $d7            ; frames left in which "up" counts as held
edge     = $d8            ; frames pushed against a door
scrn     = $d9            ; scratch: swipes left
scrbox   = $da            ; ...at which thing
scrlit   = $db            ; ...its colours are changed
pkey     = $dc            ; per cat: piano key it stands on, $ff none
pvoice   = $de
foodsave = $df            ; the bowl while we are next door
roomreq  = $e0            ; nonzero: go through the door
bedcy    = $e1            ; where the room's cat sleeps
bedx     = $e2
bedmin   = $e3
bedmax   = $e4
xmin     = $e5            ; player: x range where it stands
xmax     = $e6
overrun  = $e8            ; frames the main loop took too long (debug)
mashx    = $e7
hinton   = $eb            ; hint: words on screen (hintw = $ea: words said)
seen2    = $ed            ; the player has been to the piano room: no more hints
hintt    = $ec            ; ...frames it stays once all are
tdirty   = $e9            ; monitor changed in the background copy: 1 text, 2 colours            ; cell the player last stood in on the desk

sxl      = $70            ; sprite shadow registers
sxh      = $78
sy       = $80
spen     = $88
sptr     = $89            ; 8 bytes, to $90

        * = $0801
        .word (+), 2026
        .null $9e, format("%d", start)
+       .word 0

start   sei
        lda #<nmi_off           ; RESTORE (and RUN/STOP+RESTORE) does nothing
        sta $0318
        lda #>nmi_off
        sta $0319
        jsr sid_init
        jsr title
        lda #$33                ; ROM charset into RAM: the cats get 80 own chars
        sta $01
        ldx #0
-       .for o = 0, o < $800, o += $100
        lda $d000+o,x
        sta charset+o,x
        .next
        inx
        bne -
        lda #<nmi_off           ; RAM vectors under the KERNAL
        sta $fffa
        lda #>nmi_off
        sta $fffb
        lda #<irqent
        sta $fffe
        lda #>irqent
        sta $ffff
        lda #$35                ; only I/O left: cat frames under BASIC, the
        sta $01                 ; background copy under the KERNAL
        lda #$c0                ; port A bits 6/7 out: POTs read port 1
        sta $dc02
        lda #$40
        sta $dc00
        lda #$7f
        sta $dc0d
        lda $dc0d
        lda #0
        sta $d020
        lda #$10 | (charset >> 10)  ; screen $0400, chars from RAM
        sta $d018
        lda #$08
        sta $d016

        ldx #$ef                ; zero page work area
        lda #0
-       sta $00,x
        dex
        cpx #1
        bne -
        lda #$ff                ; no cat bitmaps yet
        sta lastf
        sta lastf+1

        ; cats
        lda #20
        sta cx
        lda #15
        sta cy
        lda #60
        sta timer
        lda #70
        sta energy
        lda #P_SIT0
        sta pose
        lda #<300               ; first meows come a little sooner
        sta mtl
        lda #>300
        sta mth

        lda #<FEED_FIRST
        sta ftl
        lda #>FEED_FIRST
        sta fth

        ; sprites: 0 strands, 1 disc, 2 shadow, 3/4 zzz, 5/6 words
        lda #BLACK
        sta $d029
        lda #WHITE
        sta $d02a
        sta $d02b
        lda #BLACK              ; balloon outline + text, white fill behind
        sta $d02c
        sta $d02d
        lda #WHITE
        sta $d02e
        lda #SPRBASE+SPR_BUBBLE
        sta sptr+7
        lda #%11100000
        sta $d017
        sta $d01d
        lda #0
        sta $d01c
        sta $d01b
        lda #SPRBASE+SPR_DISC
        sta sptr+1
        lda #SPRBASE+SPR_SHADOW
        sta sptr+2

        jsr sid_init

        lda #$a7
        sta seed
        lda #$1c
        sta seed+1
        lda $d419
        sta opotx
        lda $d41a
        sta opoty

        lda #0                  ; the living room, its cat and ball
        jsr room_load
        ldx #1
-       jsr cat_offset
        lda off
        sta oldlo,x
        lda off+1
        sta oldhi,x
        dex
        bpl -

        lda #<irq_split
        sta $0314
        lda #>irq_split
        sta $0315
        lda #$1b
        sta $d011
        lda #170
        sta $d012
        lda #1
        sta $d01a
        sta $d019
        cli

main    lda vsync
        beq main
        lda #0
        sta vsync
mframe  inc frame
        jsr cats_draw
        lda $d012               ; how late did the cats get done? (debug)
        sta drawend
        cmp drawmax
        bcc +
        sta drawmax
+       jsr mouse
        ldx #0
        jsr cat_think
        ldx #1
        jsr cat_think
        jsr ball_update
        jsr sprites
        jsr roomfx              ; monitor, stars, feeder, lamp / scratching
        jsr purr
        jsr room_check
        lda vsync               ; (debug) the next frame has begun already:
        beq +                   ; count the frames we were too slow
        inc overrun
+       jmp main

; ------------------------------------------------------------------ IRQs
; RAM under the KERNAL is banked in, so the vector at $fffe comes here: the
; same 29 cycles as the KERNAL's entry, to keep the split where it was
irqent  pha
        txa
        pha
        tya
        pha
        tsx
        lda $0104,x
        and #$10
        beq +
+       jmp ($0314)

irqexit pla
        tay
        pla
        tax
        pla
        rti

irq_split                       ; lands in the right border of line 170
        lda floorbg
        sta $d021
        lda #1
        sta $d019
        lda #252
        sta $d012
        lda #<irq_bot
        sta $0314
        lda #>irq_bot
        sta $0315
        jmp irqexit

irq_bot lda #1
        sta $d019
        lda wallbg
        sta $d021
        ldx #7
        lda #0
        sta irqt
-       lda sxl,x
        ldy times2,x
        sta $d000,y
        lda sy,x
        sta $d001,y
        lda sxh,x
        lsr a
        rol irqt
        lda sptr,x
        sta SCREEN+$3f8,x
        dex
        bpl -
        lda irqt
        sta $d010
        lda spen
        sta $d015
        jsr sfx
        lda #1
        sta vsync
        lda #170
        sta $d012
        lda #<irq_split
        sta $0314
        lda #>irq_split
        sta $0315
        jmp irqexit

times2  .byte 0, 2, 4, 6, 8, 10, 12, 14

; ------------------------------------------------------------------ helpers
rnd     lda seed
        asl a
        rol seed+1
        bcc +
        eor #$2d
+       sta seed
        eor seed+1
        eor $d012
        rts

; off = rowoff[cy] + cx/4 for cat X
cat_offset
        ldy cy,x
        lda cx,x
        lsr a
        lsr a
        clc
        adc rowlo,y
        sta off
        lda rowhi,y
        adc #0
        sta off+1
        rts

; p1..p4 = SCREEN/bgscreen/COLRAM/bgcolour + off
setptrs clc
        lda off
        adc #<SCREEN
        sta p1
        lda off+1
        adc #>SCREEN
        sta p1+1
        clc
        lda off
        adc #<bgscreen
        sta p2
        lda off+1
        adc #>bgscreen
        sta p2+1
        clc
        lda off
        adc #<COLRAM
        sta p3
        lda off+1
        adc #>COLRAM
        sta p3+1
        clc
        lda off
        adc #<bgcolour
        sta p4
        lda off+1
        adc #>bgcolour
        sta p4+1
        rts

add40   ldx #6
-       clc
        lda p1,x
        adc #40
        sta p1,x
        bcc +
        inc p1+1,x
+       dex
        dex
        bpl -
        rts

; ------------------------------------------------------------------ cat drawing
cats_draw
        lda cx                  ; the cats' boxes well apart (and last
        sta tmp                 ; frame's too)?
        lda cx+1
        jsr absdiff
        cmp #44
        bcs cd_far
        lda cy
        sta tmp
        lda cy+1
        jsr absdiff
        cmp #7
        bcs cd_far
        ldx #0
        jsr restore
        ldx #1
        jsr restore
        jsr bghook              ; lamp patch, monitor text
        ldx #0                  ; the cat further back first
        lda cy+1
        cmp cy
        bcs +
        inx
+       lda state               ; ...but a meowing cat always on top
        cmp #S_MEOW             ; (not up on the furniture: the beam gets
        bne +                   ; there before the second cat is drawn)
        lda cy
        cmp #CYMIN
        bcc +
        ldx #1
+       lda state+1
        cmp #S_MEOW
        bne +
        lda cy+1
        cmp #CYMIN
        bcc +
        ldx #0
+       txa                     ; (draw uses tmp/tmp2)
        pha
        jsr draw
        pla
        eor #1
        tax
        jmp draw

; Each cat on its own, the one higher up first, and a cat that has not
; changed is not wiped before it is drawn: there is no moment without it
; for the beam to come by (it blinked on the furniture while the other cat's
; new frame was being copied).
cd_far  ldx #0
        lda cy+1
        cmp cy
        bcs +
        inx
+       txa
        pha
        jsr still
        bcc +
        jsr restore
+       jsr bghook
        pla
        pha
        tax
        jsr draw
        pla
        eor #1
        tax
        pha
        jsr still
        bcc +
        jsr restore
+       pla
        tax
        jmp draw

; carry clear if cat X is where and how it was drawn last
still   jsr cat_offset
        lda off
        cmp oldlo,x
        bne +
        lda off+1
        cmp oldhi,x
        bne +
        jsr fidx
        cmp lastf,x
        bne +
        clc
        rts
+       sec
        rts

; A = cat X's frame: (pose*2 + dir)*4 + phase
fidx    lda pose,x
        cmp #P_MEOW
        php
        asl a
        plp
        beq +                   ; the front view has no direction
        ora dir,x
+       asl a
        asl a
        sta tmp
        lda cx,x
        and #3
        ora tmp
        rts

restore lda oldlo,x
        sta off
        lda oldhi,x
        sta off+1
        jsr setptrs
        lda #5
        sta tmp
-       ldy #7
-       lda (p2),y
        sta (p1),y
        lda (p4),y
        sta (p3),y
        dey
        bpl -
        jsr add40
        dec tmp
        bne --
        rts

; Cat X: the frame's non-empty cells go on screen as the cat's own chars
; (one per box cell, from DYNCODES) in its palette colour; the bitmaps are
; copied into the RAM charset only when the frame changed.
draw    stx cat
        txa
        asl a
        asl a
        sta palbase
        jsr fidx
        tay
        cmp lastf,x
        beq +
        sta lastf,x
        lda #1
        .byte $2c
+       lda #0
        sta fchg
        lda framelo,y
        sta fp
        lda framehi,y
        sta fp+1
        lda dynbase,x
        sta fdyn
        jsr cat_offset
        lda off
        sta oldlo,x
        lda off+1
        sta oldhi,x
        jsr setptrs
        ldy #0
        lda (fp),y
        beq drawout
        sta fcnt
        inc fp
        bne dcell
        inc fp+1
dcell   ldy #0
        lda (fp),y              ; box cell -> the cat's char
        clc
        adc fdyn
        tax
        iny
        lda (fp),y              ; screen offset in the box
        sta tmp2
        iny
        lda (fp),y              ; palette index
        ora palbase
        tay
        lda catpal,y
        ldy tmp2
        sta (p3),y
        lda dyncode,x
        sta (p1),y
        lda fchg
        beq dnext
        lda dynlo3,x            ; char bitmap - 3: the bytes sit at fp+3..10
        sta dst
        lda dynhi3,x
        sta dst+1
        .for b = 3, b < 11, b += 1
        ldy #b
        lda (fp),y
        sta (dst),y
        .next
dnext   clc
        lda fp
        adc #11
        sta fp
        bcc +
        inc fp+1
+       dec fcnt
        bne dcell
drawout ldx cat
        rts

dynbase .byte 0, 40
dyncode .byte DYNCODES
dynlo3  .byte <(charset + DYNCODES * 8 - 3)
dynhi3  .byte >(charset + DYNCODES * 8 - 3)

catpal  .byte 0, BLACK, WHITE, YELLOW  ; black tabby with white socks (player)
        .byte 0, LGREY, WHITE, YELLOW

; ------------------------------------------------------------------ cat AI
cat_think
        stx cat
        lda #0
        sta moved
        lda timer,x
        beq +
        dec timer,x
+       lda wtime,x
        beq +
        dec wtime,x
+       jsr piano
        cpx #0                  ; cat 0 is the player's
        bne +
        jmp player
+       lda mtl,x               ; time to meow at the viewer?
        ora mth,x
        bne mdec
        lda state,x
        cmp #S_CARRY+1
        bcs dispatch            ; busy: try again next frame
        jsr start_meow
        jmp dispatch
mdec    lda mtl,x
        bne +
        dec mth,x
+       dec mtl,x
dispatch
        lda state,x
        asl a
        tay
        lda states+1,y
        pha
        lda states,y
        pha
        rts

states  .word st_sit-1, st_chase-1, st_carry-1, st_bat-1, st_tobed-1, st_sleep-1, st_hiss-1, st_meow-1
        .word st_roam-1, st_goeat-1, st_eat-1, st_sit-1, st_sit-1

start_meow
        jsr meow_pose
        jsr rnd                 ; a different meow each time, in this cat's voice
        and #3
        sta tmp
        txa
        asl a
        asl a
        ora tmp
        clc
        adc #FX_MEOW
        jmp sfx_play

; cat X (= cat) turns to the viewer, balloon up, for 75 frames
meow_pose
        lda meowlo,x
        sta mtl,x
        lda meowhi,x
        sta mth,x
        jsr drop_if_owner
        lda #S_MEOW
        sta state,x
        lda #75
        sta timer,x
        sta wtime,x
        lda cx,x                ; the front view is cell aligned
        and #$fc
        sta tmp
        lda cy,x
        sta tmp2
        jsr overlaps            ; snapping left landed on the other cat?
        lda tmp
        bcc +
        adc #3                  ; (carry set) snap right instead
+       sta cx,x
        lda #SPRBASE+SPR_MEOW
        sta word,x
        lda #$a2                ; (the piano takes voice 2 out of the filter)
        jmp wroute

meowlo  .byte <MEOW0, <MEOW1
meowhi  .byte >MEOW0, >MEOW1

; ---- looking at the viewer: meow!
st_meow lda #P_MEOW
        sta pose,x
        lda timer,x
        bne +
        lda #S_SIT
        sta state,x
        lda #20
        sta timer,x
+       rts

; ---- sitting, watching the ball
st_sit  lda cy,x                 ; sitting on top of the player? move
        cmp #CYMIN
        bcc +                   ; not while on the couch
        lda cx,x
        sta tmp
        sta tx,x
        lda cy,x
        sta tmp2
        jsr overlaps
        bcc +
        jsr dodge
        jsr move_run            ; trot (rows only step every 8 frames)
        inc anim,x
        lda anim,x
        lsr a
        lsr a
        lsr a
        and #3
        sta pose,x
        rts
+       jsr face_ball
        lda frame
        adc catphase,x
        and #127
        cmp #9
        lda #P_SIT0
        bcs +
        lda #P_SIT1
+       sta pose,x
        lda timer,x
        bne +
        lda food
        bne go_eat
        lda energy,x
        beq go_bed
        lda owner
        cmp cat
        beq +
        jsr rnd
        cmp #70
        bcc go_roam
        lda #S_CHASE
        sta state,x
        lda #200
        sta timer,x
+       rts

go_eat  jsr drop_if_owner
        lda #S_GOEAT
        sta state,x
        rts

go_roam lda #S_ROAM             ; zoomies: dash to a random spot
        sta state,x
        lda #120
        sta timer,x
        jsr rnd
        and #127
        sta tx,x
        jsr rnd
        and #7
        clc
        adc #CYMIN
        sta ty,x
        rts

go_bed  jsr drop_if_owner
        lda #S_TOBED
        sta state,x
        lda #60
        sta timer,x
        lda bedx
        sta tx,x
        sta tmp
        lda bedcy
        sta tmp2
        jsr overlaps            ; the player is in the way: lie next to it
        bcc gb_out              ; if the bed is wide enough
        lda cx
        clc
        adc #26
        cmp bedmax
        bcc gb_set
        beq gb_set
        lda cx
        sbc #26
        bcc gb_out
        cmp bedmin
        bcc gb_out
gb_set  sta tx,x
gb_out  rts

catphase .byte 0, 61

; ---- chasing the ball (free or in the other cat's mouth)
st_chase
        lda food
        bne go_eat
        jsr tire
        lda energy,x
        beq go_bed
        lda timer,x
        bne +
        jmp sit_a_while
+       jsr chase_target
        jsr move_run
        jsr contact
        bcc l1_
        lda owner
        bmi l2_
        cmp cat                 ; in the other cat's mouth: steal it?
        beq l1_
        tay
        lda state,y             ; (not in mid-air)
        cmp #S_ARC
        bcs l1_
        jsr rnd
        cmp stealp,y
        bcs l1_
        ldy owner               ; the victim hisses
        lda #S_HISS
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
        jsr sfx_play
        jmp grab
l2_      jsr rnd                 ; free ball: grab or bat
        cmp #45
        bcc grab
        lda #S_BAT
        sta state,x
        lda #16
        sta timer,x
l1_     rts

stealp  .byte 5, 70                ; per-frame odds, from the player / AI

grab    lda #FX_GRAB
        jsr sfx_play
        lda cat
        sta owner
        lda #S_CARRY
        sta state,x
        lda #160
        sta timer,x
        lda #0                  ; run away from the other cat
        sta tmp
        txa
        eor #1
        tay
        lda cx,y
        cmp #64
        bcs +
        lda #64
        sta tmp
+       jsr rnd
        and #63
        ora tmp
        sta tx,x
        jsr rnd
        and #7
        clc
        adc #CYMIN
        sta ty,x
        rts

; ---- carrying the ball to a spot, then drop or toss it
st_carry
        jsr tire
        lda tx,x
        cmp cx,x
        beq +
        lda #0
        rol a                   ; carry set: tx >= cx -> right
        eor #1
        sta dir,x
+       lda timer,x
        beq +
        jsr move_run
        lda moved
        bne l3_
        lda cx,x                ; blocked by the player on the way: head
        cmp tx,x                ; somewhere else instead of dropping it
        beq +
        jsr rnd
        and #127
        sta tx,x
        rts
+       jsr drop_ball           ; arrived: drop it
        jsr rnd
        cmp #110
        bcs sit_a_while
        lda #S_BAT
        sta state,x
        lda #16
        sta timer,x
l3_      rts

sit_a_while
        lda #S_SIT
        sta state,x
        jsr rnd
        and #31
        adc #16
        sta timer,x
        rts

; ---- zoomies
st_roam jsr tire
        jsr face_target
        lda timer,x
        beq +
        jsr move_run
        lda moved
        bne ++
+       jmp sit_a_while
+       rts

; ---- food! run to my side of the bowl
st_goeat
        lda food
        bne +
        jmp sit_a_while
+       lda feedx,x
        sta tx,x
        sta tmp
        lda #FEED_CY
        sta ty,x
        sta tmp2
        jsr overlaps            ; the player eats there: the other side
        bcc +
        lda #FEED_LX+FEED_RX
        sec
        sbc tx,x
        sta tx,x
+
        jsr face_target
        jsr move_run
        lda cx,x
        cmp tx,x
        bne +
        lda cy,x
        cmp ty,x
        bne +
        lda #S_EAT
        sta state,x
        lda tx,x                ; face the bowl: left side faces right
        cmp #FEED_RX
        lda #0
        rol a
        sta dir,x
+       rts

; ---- munching
st_eat  lda frame
        lsr a
        lsr a
        lsr a
        adc catphase,x
        and #1
        clc
        adc #P_EAT0
        sta pose,x
        lda frame
        and #15
        bne +
        lda food
        beq +
        dec food
+       lda food
        beq +
        rts
+       lda energy,x            ; full and happy
        clc
        adc #80
        bcc +
        lda #255
+       sta energy,x
        jmp sit_a_while

feedx   .byte FEED_LX, FEED_RX

; dir from tx (keeps dir when already there)
face_target
        lda tx,x
        cmp cx,x
        beq +
        lda #0
        rol a
        eor #1
        sta dir,x
+       rts

; ---- swiping the ball
st_bat  lda #P_BAT
        sta pose,x
        lda timer,x
        cmp #10
        bne +
        jsr contact_loose
        bcc +
        jsr kick
+       lda timer,x
        bne +
        jsr rnd
        cmp #140
        bcc +
        jmp sit_a_while
+        lda #S_CHASE
        sta state,x
        lda #200
        sta timer,x
+       rts

; ---- going to the couch
st_tobed
        lda timer,x             ; stuck behind the player for a while
        bne +
        jmp sit_a_while
+       lda tx,x
        sta tmp
        lda #CYMIN
        ldy cx,x
        cpy tmp
        bne +
        lda bedcy
+       sta ty,x
        lda tx,x
        cmp cx,x
        beq +
        lda #0
        rol a
        eor #1
        sta dir,x
+       lda frame
        and #1
        bne +
        jsr move_to
        lda moved
        beq +
        lda #60
        sta timer,x
+       lda cx,x
        cmp tx,x
        bne +
        lda cy,x
        cmp bedcy
        bne +
        lda #S_SLEEP
        sta state,x
        jsr rnd
        and #127
        adc #150
        sta timer,x
        lda #0
        sta zph,x
+       rts

; ---- sleeping, timer counts in 4-frame units
st_sleep
        lda frame
        and #3
        beq +
        inc timer,x             ; undo the per-frame decrement
+       lda frame
        adc catphase,x
        and #64
        beq +
        lda #1
+       clc
        adc #P_SLEEP0
        sta pose,x
        lda frame
        and #1
        bne +
        inc zph,x
        lda zph,x
        cmp #48
        bcc +
        lda #0
        sta zph,x
+       lda timer,x
        bne +
        jsr rnd                 ; wake up, meow, look around
        and #127
        ora #128
        sta energy,x
        lda #S_SIT
        sta state,x
        lda #80
        sta timer,x
+       rts

; ---- hissing after being robbed
st_hiss lda #P_HISS
        sta pose,x
        lda timer,x
        bne +
        lda #S_CHASE
        sta state,x
        lda #200
        sta timer,x
+       rts

; energy drops by one every 16 frames of activity
tire    inc edec,x
        lda edec,x
        and #15
        bne +
        lda energy,x
        beq +
        dec energy,x
+       rts

drop_if_owner
        lda owner
        cmp cat
        beq drop_ball
        rts

; let go of the ball: it falls from the mouth with a little push forward
; (0.4-0.9 px/frame, a slight sideways drift and pop), so it bounces and rolls
; a bit away from the cat. Keeps X.
drop_ball
        lda #$ff
        sta owner
        jsr rnd
        and #$7f
        clc
        adc #$60
        sta vxl
        lda #0
        sta vxh
        lda dir,x
        beq +
        jsr negvx
+       jsr rnd                 ; vy = -$20..$1f
        and #$3f
        sec
        sbc #$20
        sta vyl
        lda #0
        sbc #0
        sta vyh
        lda #$c0                ; a small pop up
        sta vzl
        lda #0
        sta vzh
        rts

; dir/tx/ty so the mouth reaches the ball
chase_target
        jsr center_dx           ; t16 = bx - (cx*2+28)
        lda t16+1
        bmi +
        lda t16
        cmp #6
        bcc l4_
        lda #0
        sta dir,x
        beq l4_
+       lda t16
        cmp #$fa
        bcs l4_
        lda #1
        sta dir,x
l4_      lda bxl                 ; t16 = bx (facing left) or bx - 55
        sta t16
        lda bxh
        sta t16+1
        lda dir,x
        bne +
        sec
        lda t16
        sbc #MOUTH_X
        sta t16
        lda t16+1
        sbc #0
        sta t16+1
        bpl +
        lda #0
        sta t16
        sta t16+1
+       lsr t16+1
        ror t16
        lda t16
        cmp #CXMAX
        bcc +
        lda #CXMAX
+       sta tx,x
        lda byh
        sec
        sbc #39
        lsr a
        lsr a
        lsr a
        cmp #CYMIN
        bcs +
        lda #CYMIN
+       cmp #CYMAX+1
        bcc +
        lda #CYMAX
+       sta ty,x
        txa                     ; keep out of the other cat's way, unless
        eor #1                  ; it's stealing the ball from it
        cmp owner
        beq +
        lda tx,x
        sta tmp
        lda ty,x
        sta tmp2
        jsr overlaps
        bcc +
        jmp dodge
+       rts

; carry set if a cat box at tmp (cx), tmp2 (cy) would overlap the other cat
; (Y = other cat on return)
overlaps
        txa
        eor #1
        tay
        lda cx,y
        sec
        sbc tmp
        clc
        adc #26
        cmp #53
        bcs +
        lda cy,y
        sec
        sbc tmp2
        clc
        adc #4
        cmp #9
        bcs +
        sec
        rts
+       clc
        rts

; ty = a row 5 away from the other cat (Y), in front or behind
dodge   lda cy,y
        cmp #CYMAX-4
        bcs +
        adc #5
        sta ty,x
        rts
+       sbc #5
        cmp #CYMIN
        bcs +
        lda #CYMIN
+       sta ty,x
        rts

; A = |A - tmp|
absdiff sec
        sbc tmp
        bcs +
        eor #$ff
        adc #1
+       rts

center_dx
        lda cx,x
        asl a
        sta t16
        lda #0
        rol a
        sta t16+1
        clc
        lda t16
        adc #28
        sta t16
        bcc +
        inc t16+1
+       sec
        lda bxl
        sbc t16
        sta t16
        lda bxh
        sbc t16+1
        sta t16+1
        rts

face_ball
        jsr center_dx
        lda t16+1
        bmi +
        lda t16
        cmp #10
        bcc l5_
        lda #0
        sta dir,x
        rts
+       lda t16
        cmp #$f6
        bcs l5_
        lda #1
        sta dir,x
l5_      rts

; step towards tx/ty and pick a run/jump frame
move_run
        jsr move_to
        lda moved
        beq +
        inc anim,x
        lda anim,x
        lsr a
        lsr a
        and #3
        sta pose,x
        lda cy,x
        cmp #CYMIN
        bcs l6_
        lda #P_JUMP
        sta pose,x
        rts
+       lda #P_SIT0
        sta pose,x
l6_      rts

move_to jsr calc_ovl
        lda cx,x
        cmp tx,x
        beq l7_
        bcc +
        sbc #1
        jmp ++
+       adc #1
+       jsr tryx
l7_      lda frame
        and #7
        bne l8_
        lda cy,x
        cmp ty,x
        beq l8_
        bcc +
        sbc #1
        jmp ++
+       adc #1
+       jsr tryy
l8_      lda state,x             ; walking (not running) has its own frames
        cmp #S_TOBED
        bne +
        lda moved
        beq +
        inc anim,x
        lda anim,x
        lsr a
        lsr a
        lsr a
        and #3
        sta pose,x
        lda cy,x
        cmp #CYMIN
        bcs +
        lda #P_JUMP
        sta pose,x
+       rts

; ovl = 1 if cat X already overlaps the other one (then any step is allowed,
; so they can come apart)
calc_ovl
        lda cx,x
        sta tmp
        lda cy,x
        sta tmp2
        jsr overlaps
        lda #0
        rol a
        sta ovl
        rts

; cx = A / cy = A unless that lands on the other cat; moved++ on success
tryx    sta tmp
        lda cy,x
        sta tmp2
        jsr blocked
        bcs +
        lda tmp
        sta cx,x
        inc moved
+       rts

tryy    sta tmp2
        lda cx,x
        sta tmp
        jsr blocked
        bcs +
        lda tmp2
        sta cy,x
        inc moved
+       rts

blocked lda ovl
        bne +
        jmp overlaps
+       clc
        rts

; carry set if the mouth touches the ball (free or carried)
contact lda owner
        cmp cat
        beq nope
contact_loose
        lda bzh
        cmp #12
        bcs nope
        lda cy,x                ; ground row vs ball ground
        asl a
        asl a
        asl a
        adc #39
        sec
        sbc byh
        clc
        adc #10
        cmp #21
        bcs nope
        jsr mouth_x
        sec
        lda t16
        sbc bxl
        sta t16
        lda t16+1
        sbc bxh
        bne +
        lda t16
        cmp #9
        bcs nope
        sec                     ; (cmp left carry clear: that was the bug)
        rts
+       cmp #$ff
        bne nope
        lda t16
        cmp #$f8
        bcc nope
        sec
        rts
nope    clc
        rts

; t16 = x of the mouth of cat X
mouth_x lda cx,x
        asl a
        sta t16
        lda #0
        rol a
        sta t16+1
        lda dir,x
        bne +
        clc
        lda t16
        adc #MOUTH_X
        sta t16
        bcc +
        inc t16+1
+       rts

kick    lda #FX_KICK
        jsr sfx_play
        lda #$ff
        sta owner
        jsr rnd
        and #$7f
        sta vxl
        jsr rnd
        and #3                  ; 1.0 .. 3.5 px/frame
        bne +
        lda #2
+       sta vxh                 ; 1.0 .. 2.5 px/frame
        lda dir,x
        beq +
        sec
        lda #0
        sbc vxl
        sta vxl
        lda #0
        sbc vxh
        sta vxh
+       jsr rnd
        sta vyl
        and #$80
        beq +
        lda #$ff
+       sta vyh
        jsr rnd
        and #$7f
        sta vzl
        lda #2
        sta vzh
        rts

; ------------------------------------------------------------------ ball
ball_update
        lda owner
        bmi free
        tax                     ; in a mouth
        jsr mouth_x
        lda t16
        sta bxl
        lda t16+1
        sta bxh
        lda cy,x
        asl a
        asl a
        asl a
        adc #39
        sta byh
        lda #8
        sta bzh
        lda #0
        sta vxl
        sta vxh
        sta vyl
        sta vyh
        sta vzl
        sta vzh
        rts

free    ldy #0                  ; x += vx
        lda vxh
        bpl +
        dey
+       clc
        lda bxf
        adc vxl
        sta bxf
        lda bxl
        adc vxh
        sta bxl
        tya
        adc bxh
        sta bxh
        clc                     ; roll
        lda rotl
        adc vxl
        sta rotl
        lda roth
        adc vxh
        sta roth
        clc                     ; y += vy
        lda byf
        adc vyl
        sta byf
        lda byh
        adc vyh
        sta byh
        ; walls
        lda bxh
        bmi bwall               ; below 0: let go at the left edge, facing left
        bne +
        lda bxl
        cmp #8
        bcs l9_
bwall   lda #8
        sta bxl
        lda #0
        sta bxh
        lda vxh
        bpl l9_
        jsr negvx
        jmp l9_
+       lda bxl
        cmp #$32
        bcc l9_
        lda #$31
        sta bxl
        lda vxh
        bmi l9_
        jsr negvx
l9_      lda byh
        cmp #BYMIN
        bcs +
        cmp #BYMIN-8            ; let go up on the furniture: that much
        bcs bfloor              ; higher above the floor instead
        lda #BYMIN
        sec
        sbc byh
        clc
        adc bzh
        sta bzh
bfloor  lda #BYMIN
        sta byh
        lda vyh
        bpl l10_
        jsr negvy
        jmp l10_
+       cmp #BYMAX+1
        bcc l10_
        lda #BYMAX
        sta byh
        lda vyh
        bmi l10_
        jsr negvy
l10_      ; height
        lda bzh
        ora vzh
        ora vzl
        beq ground
        sec
        lda vzl
        sbc #GRAV
        sta vzl
        lda vzh
        sbc #0
        sta vzh
        clc
        lda bzf
        adc vzl
        sta bzf
        lda bzh
        adc vzh
        sta bzh
        bpl inair
        lda #0                  ; landed: bounce at half speed
        sta bzh
        sta bzf
        sec
        lda #0
        sbc vzl
        sta vzl
        lda #0
        sbc vzh
        sta vzh
        lsr vzh
        ror vzl
        lda vzh
        bne +
        lda vzl
        cmp #$90
        bcs +
        lda #0
        sta vzl
        rts
+       lda #FX_BOUNCE          ; audible bounce
        jmp sfx_play
inair   rts

ground  ldx #vxl                ; rolling friction
        jsr damp
        ldx #vyl
        jmp damp

negvx   sec
        lda #0
        sbc vxl
        sta vxl
        lda #0
        sbc vxh
        sta vxh
        rts

negvy   sec
        lda #0
        sbc vyl
        sta vyl
        lda #0
        sbc vyh
        sta vyh
        rts

; v -= v/32 for the 16-bit signed value at zp X, zero when tiny
damp    lda 1,x
        sta tmp
        lda 0,x
        ldy #5
-       pha
        lda tmp
        cmp #$80
        ror tmp
        pla
        ror a
        dey
        bne -
        sta tmp2
        sec
        lda 0,x
        sbc tmp2
        sta 0,x
        lda 1,x
        sbc tmp
        sta 1,x
        bne +
        lda 0,x
        cmp #$18
        bcs l11_
        bcc zero
+       cmp #$ff
        bne l11_
        lda 0,x
        cmp #$e8
        bcc l11_
zero    lda #0
        sta 0,x
        sta 1,x
l11_      rts

; ------------------------------------------------------------------ sprites
sprites lda #%00000111
        sta spen
        clc                     ; ball strands + disc
        lda bxl
        adc #18
        sta sxl
        sta sxl+1
        lda bxh
        adc #0
        sta sxh
        sta sxh+1
        lda byh
        clc
        adc #38
        sec
        sbc bzh
        sta sy
        sta sy+1
        lda roth
        lsr a
        and #15
        clc
        adc #SPRBASE+SPR_BALL
        sta sptr
        clc                     ; shadow
        lda bxl
        adc #17
        sta sxl+2
        lda bxh
        adc #0
        sta sxh+2
        lda byh
        clc
        adc #48
        sta sy+2

        ldx #1
catspr  stx cat
        lda state,x             ; zzz
        cmp #S_SLEEP
        bne nozzz
        lda cx,x
        asl a
        sta t16
        lda #0
        rol a
        sta t16+1
        lda zph,x
        lsr a
        lsr a
        lsr a
        and #3
        tay
        lda wobble,y
        ldy dir,x
        clc
        adc zoffs,y
        clc
        adc t16
        sta sxl+3,x
        lda t16+1
        adc #0
        sta sxh+3,x
        lda cy,x
        asl a
        asl a
        asl a
        adc #30+50-8
        sec
        sbc zph,x
        sta sy+3,x
        lda zph,x
        lsr a
        lsr a
        lsr a
        lsr a
        clc
        adc #SPRBASE+SPR_Z
        sta sptr+3,x
        lda spen
        ora zbit,x
        sta spen
nozzz   lda wtime,x             ; speech word
        beq noword
        lda cx,x
        asl a
        sta t16
        lda #0
        rol a
        sta t16+1
        clc                     ; balloon above the head
        lda t16
        adc #32
        sta sxl+5,x
        sta sxl+7
        lda t16+1
        adc #0
        sta sxh+5,x
        sta sxh+7
        lda cy,x
        asl a
        asl a
        asl a
        adc #50-28
        sta sy+5,x
        sta sy+7
        lda word,x
        sta sptr+5,x
        lda spen
        ora wbit,x
        ora #$80                ; fill follows the last cat (cat 0 wins)
        sta spen
noword  dex
        bmi +
        jmp catspr
+       lda lamp                ; the falling lamp shade borrows sprite 3
        cmp #1
        bne +
        lda lampx
        sta sxl+3
        lda #0
        sta sxh+3
        ldy #SPRBASE+SPR_SHADE
        lda lampy
        sta sy+3
        cmp #SHADE_Y0+20
        bcc shfr
        iny
        cmp #SHADE_Y0+48
        bcc shfr
        iny
        cmp #SHADE_Y0+76
        bcc shfr
        iny
shfr    sty sptr+3
        lda spen
        ora #$08
        sta spen
+       rts

wobble  .byte 0, 2, 3, 1
zoffs   .byte 46+24, 6+24
zbit    .byte $08, $10
wbit    .byte $20, $40

; ------------------------------------------------------------------ monitor
; The C= key (keyboard column 7 is already selected for the mouse) toggles
; tape-loader stripes on the monitor; the script also shows them while LOADING.
; All of it is written to the background copy; bghook puts it on screen
; before the cats are drawn, so a cat on the desk stands in front of the text.
; With the player on the desk the computer goes crazy: its own script, and
; every cell the cat steps into types a key.
terminal
        ldy #0
        lda plat
        cmp #PL_DESK
        bne +
        iny
+       cpy crazy
        beq +
        sty crazy
        jsr term_reset
+       lda crazy
        beq +
        lda cx
        lsr a
        lsr a
        cmp mashx
        beq +
        sta mashx
        jsr rnd
        and #31
        tay
        lda mashchars,y
        jsr tput
        lda #FX_BOUNCE          ; clack
        jsr sfx_play
+       lda $dc01
        and #$20
        tay
        eor ckey
        sty ckey
        beq +
        tya
        bne +                   ; just released
        lda lbars
        eor #1
        sta lbars
        bne +
        jsr bars_clear
+       jsr term_run
        lda lbars
        bne loadbars
        rts

; one random stripe pattern and colour per text row, new every frame
loadbars
        ldx #TERM_H-1
-       jsr rnd
        and #31
        tay
        lda stripes,y
        sta tmp
        jsr rnd
        and #7
        tay
        lda barcol,y
        sta tmp2
        lda trowlo,x
        sta p1
        sta p3
        lda trowhi,x
        sta p1+1
        clc
        adc #>(bgcolour-bgscreen)
        sta p3+1
        ldy #TERM_W-1
-       lda tmp
        sta (p1),y
        lda tmp2
        sta (p3),y
        dey
        bpl -
        dex
        bpl --
        lda #3
        sta tdirty
        rts

; the script from the top (crazy or not), blank monitor, LED off
term_reset
        ldx #<termscript
        ldy #>termscript
        lda crazy
        beq +
        ldx #<crazyscript
        ldy #>crazyscript
+       stx tptr
        stx tbase
        sty tptr+1
        sty tbase+1
        lda #0
        sta twait
        lda #DGREY
        sta bgcolour+LED_POS

; bars off: blank monitor, text colour back, cursor home
bars_clear
        lda #3
        sta tdirty
        lda #0
        sta lbars
        sta trow
        sta tcol
        ldx #TERM_W-1
-       .for r = 0, r < TERM_H, r += 1
        lda #32
        sta bgscreen+(TERM_Y+r)*40+TERM_X,x
        lda #LBLUE
        sta bgcolour+(TERM_Y+r)*40+TERM_X,x
        .next
        dex
        bpl -
        rts

barcol  .byte WHITE, RED, CYAN, PURPLE, GREEN, YELLOW, ORANGE, LRED

term_run
        lda twait
        beq tnext
        dec twait
        ; blink the cursor
        jsr tcursor
        lda frame
        and #16
        beq +
        lda #160
        .byte $2c
+       lda #32
        ldy tcol

; char A to (p1),y, if it isn't there yet
tpoke   cmp (p1),y
        beq +
        sta (p1),y
        lda #1
        ora tdirty
        sta tdirty
+       rts

tcursor ldy trow
        lda trowlo,y
        sta p1
        lda trowhi,y
        sta p1+1
        rts

tnext   jsr tcursor             ; hide the cursor
        ldy tcol
        lda #32
        jsr tpoke
tloop   ldy #0
        lda (tptr),y
        inc tptr
        bne +
        inc tptr+1
+       cmp #NL
        beq tnl
        cmp #$80
        bcc tchar
        cmp #$c0
        bcs +
        and #$3f
        sta twait
        rts
+       cmp #$ff
        bne +
        lda tbase
        sta tptr
        lda tbase+1
        sta tptr+1
        jmp tloop
+       cmp #$c2
        beq tclear
        cmp #$c3                ; loader bars on / off
        bne +
        lda #1
        sta lbars
        jmp tloop
+       cmp #$c4
        bne +
        jsr bars_clear
        jmp tloop
+
        and #1                  ; $c0 LED on, $c1 off
        tay
        lda ledcol,y
        sta bgcolour+LED_POS
        jmp tloop

tchar   jmp tput                ; one character (or line feed) a frame: it
tnl     jmp tnewl               ; prints like a terminal, and costs little

; char A at the cursor, which moves on; wraps and scrolls
tput    pha
        jsr tcursor
        pla
        ldy tcol
        jsr tpoke
        inc tcol
        lda tcol
        cmp #TERM_W
        bcc tpx
tnewl   lda #0
        sta tcol
        inc trow
        lda trow
        cmp #TERM_H
        bcc tpx
        dec trow
        ldx #0                  ; scroll up one line
-       .for r = 0, r < TERM_H-1, r += 1
        lda bgscreen+(TERM_Y+r+1)*40+TERM_X,x
        sta bgscreen+(TERM_Y+r)*40+TERM_X,x
        .next
        lda #32
        sta bgscreen+(TERM_Y+TERM_H-1)*40+TERM_X,x
        inx
        cpx #TERM_W
        bne -
        lda #1
        ora tdirty
        sta tdirty
tpx     rts

tclear  ldx #TERM_W-1
        lda #32
-       .for r = 0, r < TERM_H, r += 1
        sta bgscreen+(TERM_Y+r)*40+TERM_X,x
        .next
        dex
        bpl -
        lda #0
        sta trow
        sta tcol
        lda #1
        ora tdirty
        sta tdirty
        jmp tloop

ledcol  .byte RED, DGREY
trowlo  .byte <(bgscreen+(TERM_Y+range(TERM_H))*40+TERM_X)
trowhi  .byte >(bgscreen+(TERM_Y+range(TERM_H))*40+TERM_X)

; ------------------------------------------------------------------ stars
stars   lda state               ; (not while the player flies past the window)
        cmp #S_ARC
        beq +
        lda frame
        and #7
        bne +
        jsr rnd
        and #7
        cmp #NSTARS
        bcs +
        asl a
        tax
        lda starpos,x
        sta p1
        lda starpos+1,x
        clc
        adc #>COLRAM
        sta p1+1
        jsr rnd
        and #7
        tax
        lda starcol,x
        ldy #0
        sta (p1),y
+       rts

starcol .byte WHITE, LGREY, GREY, YELLOW, WHITE, BLUE, LGREY, WHITE

; ------------------------------------------------------------------ feeder
feeder  lda food
        bne kibble
        lda ftl                 ; count down to the next meal
        bne +
        dec fth
+       dec ftl
        lda ftl
        ora fth
        bne kibble
        lda #<FEED_EVERY
        sta ftl
        lda #>FEED_EVERY
        sta fth
        lda #FOOD
        sta food
        lda #FX_DING
        jsr sfx_play
        ldx #1                  ; call the grey cat (sleepers wake up hungry)
        stx cat
        lda state,x
        cmp #S_HISS
        bcs ++                  ; hiss/meow/roam...: they come when done
        cmp #S_SLEEP            ; sleepers wake up hungry
        beq +
        cmp #S_TOBED
        beq ++
        jsr drop_if_owner
+       lda #S_GOEAT
        sta state,x
+

kibble  lda food                ; pile height 0-3
        beq +
        clc
        adc #7
        ldy #0
-       iny
        sec
        sbc #8
        cmp #8
        bcs -
        tya
        cmp #4
        bcc +
        lda #3
+       cmp flevel
        beq feedout
        sta flevel
        tay
        lda kibrow,y            ; table offset for this level
        tay
        ldx #0
-       lda kibtab,y
        cmp #$ff
        bne +
        lda kiborig,x           ; $ff = what was there
        sta SCREEN+KIBBLE_POS,x
        sta bgscreen+KIBBLE_POS,x
        lda kibocol,x
        jmp ++
+       sta SCREEN+KIBBLE_POS,x
        sta bgscreen+KIBBLE_POS,x
        lda #ORANGE
+       sta COLRAM+KIBBLE_POS,x
        sta bgcolour+KIBBLE_POS,x
        iny
        inx
        cpx #3
        bne -
        lda flevel              ; light: green while there's food
        beq +
        lda #GREEN
        .byte $2c
+       lda #DGREY
        sta COLRAM+FEED_LIGHT
        sta bgcolour+FEED_LIGHT
feedout rts

kibrow  .byte 0, 3, 6, 9
kibtab  .byte $ff, $ff, $ff
        .byte $ff, $62, $ff
        .byte $6c, $62, $7b
        .byte $e9, $a0, $df
kiborig .fill 3
kibocol .fill 3

; ------------------------------------------------------------------ SFX
; A tiny script player, one script per voice, run once per frame from the
; bottom IRQ. Every effect starts with a hard restart (gate off, ADSR 0 for a
; frame) to dodge the SID ADSR bug. Slides run on their own while the script
; waits, so pitch, pulse width and filter can glide together.
;
;   voice 1: kick, bounce, grab, ding (triangle; the ding ring-modulates
;            against voice 3's oscillator for a bell)
;   voice 2: meow (pulse through the resonant lowpass, cutoff swept
;            closed-open-closed: "m-e-ow")
;   voice 3: hiss (noise)

SX_END   = 0              ; gate off, stop
SX_ADSR  = 1              ; ad, sr
SX_FREQ  = 2              ; lo, hi
SX_CTRL  = 3              ; control register
SX_WAIT  = 4              ; frames
SX_PW    = 5              ; lo, hi
SX_CUT   = 6              ; cutoff high byte
SX_PSLIDE = 7             ; dlo, dhi (signed), frames
SX_WSLIDE = 8             ; pulse width slide dlo, dhi, frames
SX_CSLIDE = 9             ; cutoff slide d (signed), frames
SX_MODF  = 10             ; lo, hi: frequency of the ring-mod source voice
SX_JUMP  = 11             ; lo, hi: continue at address (loops)
SX_ROUTE = 12             ; $D417: resonance + filtered voices
SX_CHOP  = 13             ; 1: switch the waveform off every other frame (25 Hz)
SX_CALL  = 14             ; lo, hi: run the script there; its SX_END comes back
SX_POKE  = 15             ; zero page address, value

HRESTART .macro
        .byte SX_CTRL, $00, SX_ADSR, $00, $00, SX_WAIT, 1
        .endm

; A = FX_xxx; keeps X and Y
sfx_play
        php
        sei
        stx sfxx
        sty sfxy
        tay
        ldx fxvoice,y
        lda fxlo,y
        sta sptrl,x
        lda fxhi,y
        sta sptrh,x
        lda #0
        sta swait,x
        sta pslc,x
        sta wslc,x
        sta cslc,x
        sta chop,x
        ldx sfxx
        ldy sfxy
        plp
        rts

sfx     ldx #2
sfxloop stx sfxv
        lda sidoff,x
        sta rofs
        lda pslc,x              ; pitch slide
        beq +
        dec pslc,x
        ldy rofs
        clc
        lda flo,x
        adc pdl,x
        sta flo,x
        sta $d400,y
        lda fhi,x
        adc pdh,x
        sta fhi,x
        sta $d401,y
+       lda wslc,x              ; pulse width slide
        beq +
        dec wslc,x
        ldy rofs
        clc
        lda pwl,x
        adc wdl,x
        sta pwl,x
        sta $d402,y
        lda pwh,x
        adc wdh,x
        sta pwh,x
        sta $d403,y
+       lda cslc,x              ; filter slide
        beq +
        dec cslc,x
        clc
        lda cutoff
        adc cdl,x
        jsr wcut
+       lda chop,x              ; 25 Hz chop: waveform off on odd frames,
        beq +                   ; gate untouched so the envelope runs on
        ldy rofs
        lda frame
        lsr a                   ; C = frame bit 0
        lda ctl,x
        bcc chopon
        and #$0f
chopon  sta $d404,y
+       lda swait,x
        beq +
        dec swait,x
        bne sfxnext
+       lda sptrh,x
        beq sfxnext             ; idle
        sta sp+1
        lda sptrl,x
        sta sp
        jsr sfxrun
        ldx sfxv
        lda sp
        sta sptrl,x
        lda sp+1
        sta sptrh,x
sfxnext dex
        bmi +
        jmp sfxloop
+       rts

; run commands until a wait or the end; X = voice
sfxrun  ldy #0
        lda (sp),y
        asl a
        tay
        lda sxcmds+1,y
        pha
        lda sxcmds,y
        pha
        ldy #1                  ; Y = first argument
        rts

sxcmds  .word sx_end-1, sx_adsr-1, sx_freq-1, sx_ctrl-1, sx_wait-1, sx_pw-1
        .word sx_cut-1, sx_pslide-1, sx_wslide-1, sx_cslide-1, sx_modf-1
        .word sx_jump-1, sx_route-1, sx_chop-1, sx_call-1, sx_poke-1

sx_call clc                     ; return to the next command
        lda sp
        adc #3
        sta retl,x
        lda sp+1
        adc #0
        sta reth,x
        jmp sx_jump

sx_poke lda (sp),y
        sta sfxy
        iny
        lda (sp),y
        ldy sfxy
        sta $00,y
        lda #3
        jmp sxadv

sx_chop lda (sp),y
        sta chop,x
        lda #2
        jmp sxadv

sx_jump lda (sp),y
        pha
        iny
        lda (sp),y
        sta sp+1
        pla
        sta sp
        jmp sfxrun

sx_route
        lda (sp),y
        jsr wroute
        lda #2
        jmp sxadv

sx_end  lda #0
        sta chop,x
        lda ctl,x
        and #$fe
        ldy rofs
        sta $d404,y
        lda reth,x              ; the end of a called script: go back
        beq +
        sta sp+1
        lda retl,x
        sta sp
        lda #0
        sta reth,x
        jmp sfxrun
+       sta sp+1                ; pointer hi 0 = idle
        rts

sx_adsr lda (sp),y
        pha
        iny
        lda (sp),y
        ldy rofs
        sta $d406,y
        pla
        sta $d405,y
        lda #3
        jmp sxadv

sx_freq lda (sp),y
        sta flo,x
        iny
        lda (sp),y
        sta fhi,x
        ldy rofs
        sta $d401,y
        lda flo,x
        sta $d400,y
        lda #3
        jmp sxadv

sx_ctrl lda (sp),y
        sta ctl,x
        ldy rofs
        sta $d404,y
        lda #2
        jmp sxadv

sx_wait lda (sp),y
        sta swait,x
        dec swait,x             ; this frame counts as the first
        lda #2
        clc
        adc sp
        sta sp
        bcc +
        inc sp+1
+       rts

sx_pw   lda (sp),y
        sta pwl,x
        iny
        lda (sp),y
        sta pwh,x
        ldy rofs
        sta $d403,y
        lda pwl,x
        sta $d402,y
        lda #3
        jmp sxadv

sx_cut  lda (sp),y
        sec                     ; darker for the title's echoes
        sbc cdark
        bcs +
        lda #0
+       jsr wcut
        lda #2
        jmp sxadv

sx_pslide
        lda (sp),y
        sta pdl,x
        iny
        lda (sp),y
        sta pdh,x
        iny
        lda (sp),y
        sta pslc,x
        lda #4
        jmp sxadv

sx_wslide
        lda (sp),y
        sta wdl,x
        iny
        lda (sp),y
        sta wdh,x
        iny
        lda (sp),y
        sta wslc,x
        lda #4
        jmp sxadv

sx_cslide
        lda (sp),y
        sta cdl,x
        iny
        lda (sp),y
        sta cslc,x
        lda #3
        jmp sxadv

sx_modf ldy modoff,x
        sty sfxy
        ldy #1
        lda (sp),y
        pha
        iny
        lda (sp),y
        ldy sfxy
        sta $d401,y
        pla
        sta $d400,y
        lda #3

sxadv   clc                     ; skip A bytes, next command
        adc sp
        sta sp
        bcc +
        inc sp+1
+       jmp sfxrun

; cutoff A (8580 scale) -> $D416, remapped on a 6581; uses Y
wcut    sta cutoff
        ldy sidmodel
        bne +
        tay
        lda cut6581,y
+       sta $d416
        rts

; $D417 = A, with the resonance toned down on a 6581 (it squeals)
wroute  ldy sidmodel
        bne +
        and #$0f
        ora #$70
+       sta $d417
        rts

nmi_off rti

sid_init
        ldx #$18
        lda #0
-       sta $d400,x
        dex
        bpl -
        jsr sid_detect
        lda #$1f                ; lowpass, full volume
        sta $d418
        lda #$a2                ; resonance 10, filter voice 2 (the meow)
        jsr wroute
        lda #$10
        jmp wcut

; Which SID? Triangle+sawtooth combined reads back strongly on an 8580 and
; almost always 0 on a 6581 (measured on the C64U: 227 vs 1 non-zero reads
; out of 256). sidmodel = 1 if at least 64 reads are non-zero.
sid_detect
        lda #$08                ; test bit: reset oscillator 3
        sta $d412
        lda #$00
        sta $d40e
        lda #$10
        sta $d40f
        lda #$30                ; triangle + sawtooth, no gate
        sta $d412
        ldx #0
        ldy #0
-       lda $d41b
        beq +
        iny
+       dex
        bne -
        lda #0
        sta sidmodel
        cpy #64
        bcc +
        inc sidmodel
+       lda #$08
        sta $d412
        lda #0
        sta $d412
        rts

sidoff  .byte 0, 7, 14
modoff  .byte 14, 0, 7          ; ring-mod source of each voice
sptrl   .fill 3
sptrh   .fill 3
swait   .fill 3
ctl     .fill 3
flo     .fill 3
fhi     .fill 3
pwl     .fill 3
pwh     .fill 3
pdl     .fill 3
pdh     .fill 3
pslc    .fill 3
wdl     .fill 3
wdh     .fill 3
wslc    .fill 3
cdl     .fill 3
cslc    .fill 3
chop    .fill 3
retl    .fill 3
reth    .fill 3
sfxstate_end

FX_KICK  = 0
FX_BOUNCE = 1
FX_GRAB  = 2
FX_DING  = 3
FX_MEOW  = 4              ; 8 variants (gen.py): cat*4 + kind
FX_HISS  = 12
FX_PURR  = 13
FX_PURROFF = 14
FX_CRASH = 15
FX_TINKLE = 16
FX_SCRATCH = 17
FX_PIANO = 18
FX_PIANO2 = 19
FX_HINT  = 20             ; "go right to enter the next room", in meows (gen.py)
fxvoice .byte 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 0, 0, 0, 1, 1
fxlo    .byte <fx_kick, <fx_bounce, <fx_grab, <fx_ding
        .byte <meow0, <meow1, <meow2, <meow3, <meow4, <meow5, <meow6, <meow7, <fx_hiss
        .byte <fx_purr, <fx_purroff, <fx_crash, <fx_tinkle, <fx_scratch, <fx_piano, <fx_piano2, <hintfx
fxhi    .byte >fx_kick, >fx_bounce, >fx_grab, >fx_ding
        .byte >meow0, >meow1, >meow2, >meow3, >meow4, >meow5, >meow6, >meow7, >fx_hiss
        .byte >fx_purr, >fx_purroff, >fx_crash, >fx_tinkle, >fx_scratch, >fx_piano, >fx_piano2, >hintfx

; the lamp shade hits the floor: bright noise falling to a rumble (voice 3)...
fx_crash #HRESTART
        .byte SX_ROUTE, $a2
        .byte SX_ADSR, $0a, $00
        .byte SX_FREQ, $00, $c8, SX_CTRL, $81
        .byte SX_PSLIDE, <-$0b00, >-$0b00, 14, SX_WAIT, 14
        .byte SX_FREQ, $00, $14, SX_WAIT, 22, SX_END

; ...and shards: four high blips (voice 1)
fx_tinkle #HRESTART
        .byte SX_ADSR, $04, $00
        .byte SX_FREQ, $00, $e0, SX_CTRL, $11, SX_WAIT, 3
        .byte SX_CTRL, $10, SX_FREQ, $00, $b4, SX_CTRL, $11, SX_WAIT, 3
        .byte SX_CTRL, $10, SX_FREQ, $00, $f4, SX_CTRL, $11, SX_WAIT, 4
        .byte SX_CTRL, $10, SX_FREQ, $00, $c8, SX_CTRL, $11, SX_WAIT, 8, SX_END

; claws in the upholstery: a short rasp, noise chopped at 25 Hz, rising
fx_scratch #HRESTART
        .byte SX_ADSR, $00, $90
        .byte SX_FREQ, $00, $30, SX_CTRL, $81, SX_CHOP, 1
        .byte SX_PSLIDE, $00, $05, 7, SX_WAIT, 7, SX_END

; a piano key: the caller has set the frequency. Pulse, struck hard, falling
; quickly to a low sustain, then a long release. No hard restart (the notes
; come every other frame when a cat runs along the keys) and no filter, so
; both SID models play it alike.
fx_piano
        .byte SX_CTRL, $40, SX_ADSR, $08, $49, SX_PW, $00, $08
        .byte SX_CTRL, $41, SX_WAIT, 7, SX_CTRL, $40, SX_WAIT, 30, SX_END
fx_piano2
        .byte SX_ROUTE, $a0
        .byte SX_CTRL, $40, SX_ADSR, $08, $49, SX_PW, $00, $05
        .byte SX_CTRL, $41, SX_WAIT, 7, SX_CTRL, $40, SX_WAIT, 30, SX_END

; purr: a cat's purr is a ~25 Hz flutter, too low to play as a pitch (the C64
; output stage and TV speakers lose it). So dark noise (Fn $0600: the noise
; LFSR clocks at ~16 x 84 Hz, a low rumbly hiss) is chopped on/off every frame
; = 25 Hz at 50 fps. Loops a breath: a fuller exhale, a softer, darker inhale,
; a short pause with the gate off.
fx_purr #HRESTART
purrloop
        .byte SX_ADSR, $60, $a6, SX_FREQ, $00, $06, SX_CTRL, $81, SX_CHOP, 1, SX_WAIT, 40
        .byte SX_ADSR, $60, $66, SX_FREQ, $00, $05, SX_WAIT, 25
        .byte SX_CHOP, 0, SX_CTRL, $80, SX_WAIT, 8
        .byte SX_JUMP, <purrloop, >purrloop
fx_purroff
        .byte SX_ROUTE, $a2, SX_END

; purr while any cat sleeps (and restart it after a hiss borrowed voice 3)
purr    lda state
        cmp #S_SLEEP
        beq +
        lda state+1
        cmp #S_SLEEP
        beq +
        lda purring
        beq ++
        lda #0
        sta purring
        lda #FX_PURROFF
        jmp sfx_play
+       lda sptrh+2
        bne +
        lda #FX_PURR
        jsr sfx_play
        lda #1
        sta purring
+       rts

; swat: a plain wooden "tock": low triangle, very short decay, tiny drop
fx_kick #HRESTART
        .byte SX_ADSR, $03, $00
        .byte SX_FREQ, $00, $1c, SX_CTRL, $11
        .byte SX_PSLIDE, <-$0300, >-$0300, 3, SX_WAIT, 6, SX_END

; bounce: the same tock, lower and shorter
fx_bounce #HRESTART
        .byte SX_ADSR, $02, $00
        .byte SX_FREQ, $00, $14, SX_CTRL, $11
        .byte SX_PSLIDE, <-$0200, >-$0200, 2, SX_WAIT, 4, SX_END

; grab: two quick blips a major third apart
fx_grab #HRESTART
        .byte SX_ADSR, $05, $00
        .byte SX_FREQ, $9e, $15, SX_CTRL, $11, SX_WAIT, 3
        .byte SX_CTRL, $10, SX_FREQ, $3a, $1b, SX_CTRL, $11, SX_WAIT, 9, SX_END

; feeder: a two-note ring-modulated bell, E6 then C6, long decay
fx_ding #HRESTART
        .byte SX_ADSR, $0a, $00
        .byte SX_MODF, $00, $7b, SX_FREQ, $b0, $57, SX_CTRL, $15, SX_WAIT, 14
        .byte SX_CTRL, $14, SX_WAIT, 1
        .byte SX_MODF, $00, $62, SX_FREQ, $9e, $45, SX_CTRL, $15, SX_WAIT, 70, SX_END

; hiss: a breathy noise swell that rises a little, then releases
fx_hiss #HRESTART
        .byte SX_ROUTE, $a2     ; unfiltered (the purr may have routed voice 3)
        .byte SX_ADSR, $40, $98
        .byte SX_FREQ, $00, $60, SX_CTRL, $81
        .byte SX_PSLIDE, $00, $02, 12, SX_WAIT, 18, SX_END

; ------------------------------------------------------------------ tables
rowlo   .byte <(range(25)*40)
rowhi   .byte >(range(25)*40)

code_end
        .cerror code_end > $2000, "code overlaps the sprites"

        * = $2000
        .include "catspr.inc"
        .cerror spritedata_end > $2800, "sprites run into the charset"

        * = $2800               ; RAM charset (ROM copy + the cats' chars)
charset .fill $800

        .include "catsim.inc"

; more code after the data: only sprites and the VIC need bank 0 below $4000
        .include "player.asm"
        .include "rooms.asm"
        .include "title.asm"
        .cerror * > $a000, "code runs into the left-facing frames"

        * = $a000               ; RAM under the BASIC ROM ($01 = $36)
        .include "catleft.inc"
        .cerror * > $d000, "left-facing frames run into I/O"

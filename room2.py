#!/usr/bin/env python3
"""Room 2 of Cat Simulator 64: the music room next door.

Same technique as room 1 (gen.draw_room): pixel art on a 320x200 canvas,
converted to ROM PETSCII by gen.room_cells - one character and one colour
per 8x8 cell over the region background. Rows 0-14 (wall) are dark red,
rows 15-24 (floor) orange; the raster split stays at row 15.

The wallpaper IS the wall background (red, with sparse pinstripes), the
sofa's upholstery and the piano's panels are that same red inside coloured
frames, and the wall below the dado rail (rows 11-14) is plain: a cat's
custom chars show the region background round its pixels, so here they
leave next to no halo. Nearly everything sits on the 4 px quarter-block
grid so the PETSCII match is exact.

Left to right: door frame back to room 1 (purple wallpaper showing), an
upright saloon piano, a potted palm, free wall (the scratching spots), a
camel-back sofa under a desert-sunset painting. A rug lies before the sofa.

`python3 room2.py` writes room2_preview.png / room2_preview2.png and prints
the character budget. Nothing here is wired into the game yet.
"""
import os

import gen
from gen import (BLACK, WHITE, RED, CYAN, PURPLE, GREEN, BLUE, YELLOW, ORANGE, BROWN,
                 LRED, DGREY, GREY, LGREEN, LBLUE, LGREY, Canvas)

HERE = os.path.dirname(os.path.abspath(__file__))

# ------------------------------------------------------------ constants
WALL_BG2 = RED            # $d021 for rows 0-14
FLOOR_BG2 = ORANGE        # $d021 for rows 15-24
SPLIT_ROW2 = gen.SPLIT_ROW

# Cat positions use the game's units: cx = box x in 2 px steps (box is 64 px
# wide, the cat drawing 56 px of it), cy = top cell row of the 5-row box;
# the cat's ground line is y = cy*8+39. Facing: 0 = right, 1 = left.

# upright piano, cells 4..14 x rows 5..14
PIANO_X0, PIANO_X1 = 32, 120          # px
PIANO_TOP_Y = 40                      # px: flat lid
PIANO_KEYS_Y = 88                     # px: top of the key row (cell row 11)
PIANO_TOP_CY = 0                      # cat on the lid: box rows 0-4, ground y 39
PIANO_KEYS_CY = 6                     # cat on the fallboard/keys: rows 6-10, ground y 87
PIANO_CX_MIN, PIANO_CX_MAX = 16, 30   # both ledges: box x 32..60
PIANO_KEYS = (5, 11, 9)               # white key cells: col, row, count (for a "plink" effect)
PIANO_SHARPS = "110111010"            # black sharps in the row above (row 10), per key cell

# sofa, cells 28..39 x rows 7..14
SOFA2_X0, SOFA2_X1 = 224, 320         # px
SOFA2_CY = 8                          # sitting/sleeping cat: rows 8-12, ground y 103
SOFA2_CX_MIN, SOFA2_CX_MAX = 118, 124  # box x 236..248 (the seat between the arms)
SOFA2_SCRATCH_CX = 88                 # cat on the floor left of the left arm,
SOFA2_SCRATCH_CY = 12                 # facing right ("bat" pose), paw on the arm
SOFA2_SCRATCH_FACING = 0

# potted palm
PLANT_BOX = (16, 4, 6, 11)            # col, row, width, height in cells
PLANT_POT = (17, 12, 4, 3)            # the pot alone (an obstacle to jump over)
PLANT_CROWN = ["..ab..",              # leaf crown, one letter per cell (see draw_room2)
               "B.##.A",
               "DB##AC",
               ".D##C.",
               "db##ac",
               ".dbac."]
PLANT_SCRATCH_CX = 78                 # cat on the floor right of the pot,
PLANT_SCRATCH_CY = 12                 # facing left, paw on the pot
PLANT_SCRATCH_FACING = 1

# door back to room 1: cells 0..2 x rows 1..14 (cats enter at the left edge)
DOOR_BOX = (0, 1, 3, 14)
# rug outline on the floor: col, row, width, height
RUG_BOX = (21, 18, 18, 4)

# the wool ball (two sprites: strands over a disc; shadow stays black)
BALL2_STRAND = BLUE
BALL2_DISC = LBLUE
# cats: black + white socks as ever; the second cat stays light grey here
# (an orange cat would vanish on the orange floor)
CAT2_COLOURS = [(BLACK, WHITE), (LGREY, WHITE)]


# ------------------------------------------------------------ the room
def region_bg2(row):
    return WALL_BG2 if row < SPLIT_ROW2 else FLOOR_BG2


def leaf(cv, x0, y0, x1, y1, w, c):
    """Lens-shaped leaf from the stem (x0,y0) to the tip (x1,y1), w px wide."""
    dx, dy = x1 - x0, y1 - y0
    ll = dx * dx + dy * dy

    def t(x, y):
        u = ((x - x0) * dx + (y - y0) * dy) / ll
        if not 0 <= u <= 1:
            return False
        d = abs((x - x0) * dy - (y - y0) * dx) / ll ** 0.5
        v = (u - 0.35) / (0.65 if u > 0.35 else 0.35)       # widest a third of the way up
        return d <= w / 2 * max(0, 1 - v * v) ** 0.5 + 0.3
    cv.area(t, c, (min(x0, x1) - w, min(y0, y1) - w, max(x0, x1) + w, max(y0, y1) + w))


def draw_room2():
    cv = Canvas(320, 200, None)       # None = region background
    # wall: the red background with gold/pink pinstripes down to a dado rail;
    # below the rail (rows 11-14, where cats walk past) it stays plain
    for i, x in enumerate(range(12, 320, 16)):
        cv.rect(x - 1, 0, x + 1, 84, ORANGE if i % 2 else LRED)   # 2 px: the ROM's line width
    cv.rect(0, 84, 320, 88, LRED)     # dado rail
    cv.rect(0, 116, 320, 120, BROWN)  # skirting board
    # floor: orange boards, 16 px deep, staggered joints
    cv.rect(0, 120, 320, 122, BROWN)
    for k, y in enumerate(range(120, 200, 16)):
        cv.rect(0, y + 15, 320, y + 16, BROWN)
        for x in range((k * 56 + 28) % 96, 320, 96):
            cv.rect(x, y + (2 if k == 0 else 0), x + 2, y + 15, BROWN)

    # door frame on the left edge: room 1's purple wallpaper shows through
    cv.rect(0, 16, 16, 120, PURPLE)
    cv.rect(4, 16, 5, 112, DGREY)
    cv.rect(0, 112, 16, 120, DGREY)
    cv.rect(16, 8, 22, 120, LGREY)                  # jamb
    cv.rect(0, 8, 22, 16, LGREY)                    # lintel

    # upright saloon piano: light wood frame, panels of the red background
    px0, px1 = PIANO_X0, PIANO_X1
    cv.rect(px0, 40, px1, 80, ORANGE)
    cv.rect(px0, 46, px1, 48, None)                 # shadow line under the lid
    cv.rect(px0 + 8, 48, px0 + 24, 72, None)        # left panel
    cv.rect(px0 + 32, 48, px0 + 56, 72, None)       # centre panel
    cv.rect(px0 + 64, 48, px0 + 80, 72, None)       # right panel
    for sx in (px0 + 12, px0 + 72):                 # candle sconces
        cv.rect(sx, 52, sx + 4, 56, YELLOW)         # flame
        cv.rect(sx, 56, sx + 4, 64, WHITE)          # candle
        cv.rect(sx - 4, 64, sx + 8, 68, YELLOW)     # brass bracket
    cv.rect(px0 + 34, 56, px0 + 43, 72, WHITE)      # sheet music, two pages
    cv.rect(px0 + 45, 56, px0 + 54, 72, WHITE)
    # keyboard: a row of black sharps (row 10) over a row of white keys (row 11)
    cv.rect(px0 + 8, 80, px1 - 8, 96, None)
    cv.rect(px0, 80, px0 + 8, 96, ORANGE)           # cheek blocks
    cv.rect(px1 - 8, 80, px1, 96, ORANGE)
    for i, k in enumerate(PIANO_SHARPS):
        kx = px0 + 8 + i * 8
        cv.rect(kx, 88, kx + 6, 96, WHITE)          # one white key per cell
        if k == "1":
            cv.rect(kx + 4, 80, kx + 8, 88, BLACK)  # sharp over the gap to the next key
    # keybed, legs, lower cabinet with one panel and the pedal recess
    cv.rect(px0, 96, px1, 100, ORANGE)
    for lx in (px0, px1 - 4):
        cv.rect(lx, 100, lx + 4, 112, ORANGE)       # legs
    cv.rect(px0, 112, px0 + 8, 120, ORANGE)         # feet
    cv.rect(px1 - 8, 112, px1, 120, ORANGE)
    cv.rect(px0 + 12, 100, px1 - 12, 120, ORANGE)
    cv.rect(px0 + 16, 104, px1 - 16, 112, None)
    cv.rect(px0 + 36, 112, px0 + 52, 120, None)
    cv.rect(px0 + 40, 116, px0 + 43, 120, YELLOW)   # pedals
    cv.rect(px0 + 45, 116, px0 + 48, 120, YELLOW)

    # potted plant, a cell clear of the piano. The crown is laid out on the
    # cell grid with the ROM's four triangles: a/b = lower right/left half,
    # c/d = upper left/right half, # = full cell; capitals are light green
    pc, pr = PLANT_BOX[0], PLANT_BOX[1]
    tri = {"a": [(8, 0), (8, 8), (0, 8)], "b": [(0, 0), (8, 8), (0, 8)],
           "c": [(0, 0), (8, 0), (0, 8)], "d": [(0, 0), (8, 0), (8, 8)],
           "#": [(0, 0), (8, 0), (8, 8), (0, 8)]}
    for r, row in enumerate(PLANT_CROWN):
        for c, ch in enumerate(row):
            if ch != ".":
                ox, oy = (pc + c) * 8, (pr + r) * 8
                cv.poly([(ox + x, oy + y) for x, y in tri[ch.lower()]], LGREEN if ch.isupper() else GREEN)
    mx = (pc + 3) * 8                               # the plant's axis (a cell boundary)
    cv.rect(mx - 2, 80, mx + 2, 100, GREEN)         # stem
    cv.rect(mx - 12, 100, mx + 12, 104, WHITE)      # pot rim
    cv.rect(mx - 8, 104, mx + 8, 120, WHITE)        # pot

    # sofa: red upholstery (the background) in a pink frame, camel back
    sx0, sx1 = SOFA2_X0, SOFA2_X1
    cv.rect(sx0 + 12, 56, sx1 - 12, 112, None)
    cv.rect(sx0 + 12, 64, sx1 - 12, 68, LRED)       # crest rail
    cv.poly([(sx0 + 24, 64), (sx0 + 32, 56), (sx1 - 32, 56), (sx1 - 24, 64)], LRED)   # hump
    for x in (sx0 + 35, sx0 + 59):
        cv.rect(x, 68, x + 2, 104, LRED)            # cushion seams
    cv.rect(sx0 + 12, 68, sx0 + 14, 84, LRED)       # sides of the back
    cv.rect(sx1 - 14, 68, sx1 - 12, 84, LRED)
    cv.rect(sx0 + 12, 96, sx1 - 12, 98, LRED)       # seat line
    cv.rect(sx0 + 12, 104, sx1 - 12, 108, LRED)     # front rail
    for ax in (sx0, sx1 - 12):                      # rolled arms
        cv.rect(ax, 84, ax + 12, 112, LRED)
        cv.ellipse(ax + 6, 82, 7, 6, LRED)
    cv.rect(sx0, 112, sx0 + 4, 120, BLACK)          # legs
    cv.rect(sx1 - 4, 112, sx1, 120, BLACK)
    cv.poly([(296, 80), (304, 88), (296, 96), (288, 88)], CYAN)   # scatter cushion

    # painting above the sofa: desert sunset (the sky is the red background)
    fx0, fy0, fx1, fy1 = 244, 12, 300, 44
    cv.rect(fx0, fy0, fx1, fy1, YELLOW)             # gilt frame
    cv.rect(fx0 + 4, fy0 + 4, fx1 - 4, fy1 - 4, None)
    cv.rect(248, 32, 296, 40, ORANGE)               # desert floor
    cv.ellipse(276, 32, 8, 8, YELLOW)               # setting sun
    cv.rect(264, 32, 288, 40, ORANGE)
    cv.rect(256, 20, 260, 32, GREEN)                # cactus
    cv.rect(252, 24, 256, 28, GREEN)
    cv.rect(260, 28, 264, 32, GREEN)
    cv.rect(288, 24, 296, 32, PURPLE)               # mesa

    # rug before the sofa: just a border and three lozenges, so a cat on it
    # (showing the floor colour round itself) leaves no hole
    rc, rr, rw, rh = RUG_BOX
    rx0, ry0, rx1, ry1 = rc * 8, rr * 8, (rc + rw) * 8, (rr + rh) * 8
    cv.rect(rx0, ry0, rx1, ry1, None)
    cv.rect(rx0, ry0, rx1, ry0 + 2, RED)
    cv.rect(rx0, ry1 - 2, rx1, ry1, RED)
    cv.rect(rx0, ry0, rx0 + 2, ry1, RED)
    cv.rect(rx1 - 2, ry0, rx1, ry1, RED)
    for mx in (208, 240, 272):
        cv.poly([(mx, 152), (mx + 8, 160), (mx, 168), (mx - 8, 160)], RED)
    return cv


def room2_cells(cv=None):
    """gen.room_cells with this room's backgrounds: (screen codes, colours)."""
    cv = cv or draw_room2()
    saved = gen.WALL_BG, gen.FLOOR_BG
    gen.WALL_BG, gen.FLOOR_BG = WALL_BG2, FLOOR_BG2
    try:
        return gen.room_cells(cv)
    finally:
        gen.WALL_BG, gen.FLOOR_BG = saved


# ------------------------------------------------------------ preview
def _sprite_pixels(data):
    return [(x, y) for y in range(21) for x in range(24) if data[y * 3 + x // 8] >> (7 - x % 8) & 1]


def preview(scr, col, cats, stamps, ball, name, scale=2):
    """stamps: (cat 0/1, pose, facing, cx in 2 px units, cy); ball: (x, y) px."""
    from PIL import Image
    img = Image.new("RGB", (320 * scale, 200 * scale))
    over = {}
    for i, pose, facing, cx, cy in stamps:
        cellx, ph = divmod(cx, 4)
        if pose == "meow":
            ph = 0
        for idx, pal, rows in cats[(gen.POSES.index(pose) * 2 + facing) * gen.PHASES + ph]:
            r, c = divmod(idx, gen.CAT_W)
            if 0 <= cellx + c < 40 and 0 <= cy + r < 25:
                over[(cy + r) * 40 + cellx + c] = (rows, CAT2_COLOURS[i][pal - 1])

    def dot(x, y, c):
        v = gen.PAL[c]
        for sy in range(scale):
            for sx in range(scale):
                img.putpixel((x * scale + sx, y * scale + sy), (v >> 16, v >> 8 & 255, v & 255))

    for i in range(1000):
        bg = region_bg2(i // 40)
        if i in over:
            rows, fg = over[i]
            for y in range(8):
                for x in range(8):
                    dot(i % 40 * 8 + x, i // 40 * 8 + y, fg if rows[y] >> (7 - x) & 1 else bg)
        else:
            gen.render_cell(img, i % 40, i // 40, scr[i], col[i], bg, scale)
    if ball:                                        # the sprites, roughly
        frames, disc, shadow = gen.ball_frames()
        bx, by = ball
        for x, y in _sprite_pixels(shadow):
            dot(bx - 1 + x, by + 11 + y, BLACK)
        for x, y in _sprite_pixels(disc):
            dot(bx + x, by + y, BALL2_DISC)
        for x, y in _sprite_pixels(frames[3]):
            dot(bx + x, by + y, BALL2_STRAND)
    img.save(os.path.join(HERE, name))


def main():
    scr, col = room2_cells()
    cats = gen.cat_frames()
    preview(scr, col, cats, [
        (0, "run1", 0, 6, 17),                                  # coming in from room 1
        (1, "sit0", 1, SOFA2_CX_MIN + 2, SOFA2_CY),             # on the sofa
        (0, "sit0", 0, PIANO_CX_MIN + 6, PIANO_KEYS_CY),        # on the keyboard
        (1, "bat", PLANT_SCRATCH_FACING, PLANT_SCRATCH_CX, PLANT_SCRATCH_CY),   # scratching the palm
    ], (150, 172), "room2_preview.png")
    preview(scr, col, cats, [
        (0, "sit1", 0, PIANO_CX_MIN + 4, PIANO_TOP_CY),         # on top of the piano
        (1, "sleep0", 0, SOFA2_CX_MIN, SOFA2_CY),               # asleep on the sofa
        (0, "bat", SOFA2_SCRATCH_FACING, SOFA2_SCRATCH_CX, SOFA2_SCRATCH_CY),   # scratching the sofa
        (1, "run2", 1, 40, 12),                                 # walking along the back wall
        (1, "meow", 0, 16, 18),
    ], (262, 150), "room2_preview2.png")
    preview(scr, col, cats, [], None, "room2_room.png")

    # character budget
    s1, _ = gen.room_cells(gen.draw_room())
    room1 = set(s1) | {ch for _, _, ch in gen.STARS} | {0x62, 0x51}
    room2 = set(scr)
    print("room 2 screen codes: %d, of which room 1 does not use: %d" % (len(room2), len(room2 - room1)))
    print("  new:", " ".join("$%02x" % c for c in sorted(room2 - room1)))
    used = room1 | room2 | {0x20, 0xa0, 0x2e, 0x2a, 0x51, 0x62, 0x6c, 0x7b, 0xe9, 0xdf}   # as gen.dyn_codes
    used |= set(gen.LOADER_STRIPES) | {b for b in gen.term_script() if b < gen.NL}
    used |= set(range(0x01, 0x1b)) | set(range(0x30, 0x3a))
    print("codes left for the cats if one charset serves both rooms: %d (80 needed)" % (256 - len(used)))


if __name__ == "__main__":
    main()

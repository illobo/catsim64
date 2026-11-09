#!/usr/bin/env python3
"""PETSCII cats: two ROM-font cats chasing a sprite wool ball in an 80s living room.

Everything is drawn as pixel art and converted to ROM PETSCII: each 8x8 cell
gets the ROM character (graphics subset) with the smallest Hamming distance to
the pixels and the majority colour. Pixels the cell can't show fall back to the
region background - the classic PETSCII outline.

Rows 0-14 (wall) have a blue background, rows 15-24 (floor) brown; cat.asm
splits $D021 with a raster IRQ. The couch body and monitor glass are "made of"
the blue background, so a cat sleeping on the couch has no halo.

Cats are rendered procedurally (run cycle, sit, blink, bat, sleep, hiss, jump),
facing both ways, at 4 sub-cell x phases (2 px steps).

Outputs catsim.inc (64tass data) plus preview.png and catsheet.png.
"""
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def _chargen():
    """The C64 character ROM (4 KB; not part of the sources): $CHARGEN, or
    tools/chargen.bin, or VICE's copy."""
    for p in [os.environ.get("CHARGEN", ""), os.path.join(HERE, "tools", "chargen.bin"),
              "/opt/homebrew/share/vice/C64/chargen-901225-01.bin",
              "/usr/local/share/vice/C64/chargen-901225-01.bin",
              "/usr/share/vice/C64/chargen-901225-01.bin",
              "/usr/lib/vice/C64/chargen-901225-01.bin",
              "/usr/share/vice/C64/chargen", "/usr/lib/vice/C64/chargen"]:
        if p and os.path.isfile(p):
            return open(p, "rb").read()
    sys.exit("gen.py: no C64 character ROM: set CHARGEN=/path/to/chargen (VICE has one)")


CHARGEN = _chargen()

BLACK, WHITE, RED, CYAN, PURPLE, GREEN, BLUE, YELLOW = range(8)
ORANGE, BROWN, LRED, DGREY, GREY, LGREEN, LBLUE, LGREY = range(8, 16)
PAL = [0x000000, 0xffffff, 0x880000, 0xaaffee, 0xcc44cc, 0x00cc55, 0x0000aa, 0xeeee77,
       0xdd8855, 0x664400, 0xff7777, 0x333333, 0x777777, 0xaaff66, 0x0088ff, 0xbbbbbb]

WALL_BG = BLUE
FLOOR_BG = BROWN
SPLIT_ROW = 15            # first floor row

CAT_W, CAT_H = 8, 5       # cat box in cells
CAT_PX_W = 56             # cat drawing width inside the 64 px box
PHASES = 4                # x phases of 2 px
POSES = ["run0", "run1", "run2", "run3", "sit0", "sit1", "bat", "sleep0", "sleep1", "hiss", "jump", "meow", "eat0", "eat1"]
MOUTH = (55, 25)          # ball centre when carried, local coords facing right

# text area of the monitor (cells)
TERM_X, TERM_Y, TERM_W, TERM_H = 28, 4, 9, 4


# ------------------------------------------------------------ char matching
def char_bits(code):
    rows = CHARGEN[(code & 127) * 8:(code & 127) * 8 + 8]
    v = 0
    for r in rows:
        v = v << 8 | (r ^ (0xff if code & 128 else 0))
    return v


EXCLUDE = {0x41, 0x53, 0x58, 0x5a, 0x5e, 0x5b, 0x56, 0x57, 0x51, 0xc1, 0xd3, 0xd8, 0xda, 0xde,
           0xdb, 0xd6, 0xd7, 0xd1, 0x7e + 0x80}
CANDS = [c for c in [32, 160] + list(range(64, 128)) + list(range(192, 256)) if c not in EXCLUDE]
CANDBITS = [(c, char_bits(c)) for c in CANDS]
_seen = set()
CANDBITS = [(c, b) for c, b in CANDBITS if not (b in _seen or _seen.add(b))]


CAT_CANDS = [(c, char_bits(c)) for c in
             [32, 97, 98, 108, 123, 124, 126, 127, 160, 225, 226, 236, 251, 252, 254, 255, 0x5f, 0x69, 0xdf, 0xe9]]


def best_char(bits, heavy=0, cands=CANDBITS):
    best = None
    for code, cb in cands:
        d = bits ^ cb
        cost = bin(d).count("1") + 2 * bin(d & heavy).count("1")
        if best is None or cost < best[0]:
            best = (cost, code)
    return best[1]


# ------------------------------------------------------------ pixel canvas
class Canvas:
    def __init__(self, w, h, fill=None):
        self.w, self.h = w, h
        self.p = [fill] * (w * h)
        self.heavy = [False] * (w * h)

    def put(self, x, y, c):
        if 0 <= x < self.w and 0 <= y < self.h:
            self.p[y * self.w + x] = c

    def get(self, x, y):
        return self.p[y * self.w + x]

    def area(self, test, c, box=None):
        x0, y0, x1, y1 = box or (0, 0, self.w, self.h)
        for y in range(max(0, int(y0)), min(self.h, int(math.ceil(y1)) + 1)):
            for x in range(max(0, int(x0)), min(self.w, int(math.ceil(x1)) + 1)):
                if test(x + 0.5, y + 0.5):
                    self.put(x, y, c)

    def ellipse(self, cx, cy, rx, ry, c):
        self.area(lambda x, y: ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1, c,
                  (cx - rx - 1, cy - ry - 1, cx + rx + 1, cy + ry + 1))

    def rect(self, x0, y0, x1, y1, c):
        for y in range(y0, y1):
            for x in range(x0, x1):
                self.put(x, y, c)

    def capsule(self, x0, y0, x1, y1, r, c):
        dx, dy = x1 - x0, y1 - y0
        ll = dx * dx + dy * dy or 1

        def t(x, y):
            u = max(0, min(1, ((x - x0) * dx + (y - y0) * dy) / ll))
            return (x - x0 - u * dx) ** 2 + (y - y0 - u * dy) ** 2 <= r * r
        self.area(t, c, (min(x0, x1) - r - 1, min(y0, y1) - r - 1, max(x0, x1) + r + 1, max(y0, y1) + r + 1))

    def poly(self, pts, c):
        def inside(x, y):
            n, j, ins = len(pts), len(pts) - 1, False
            for i in range(n):
                xi, yi = pts[i]
                xj, yj = pts[j]
                if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi:
                    ins = not ins
                j = i
            return ins
        xs, ys = [p[0] for p in pts], [p[1] for p in pts]
        self.area(inside, c, (min(xs), min(ys), max(xs), max(ys)))

    def curve(self, pts, r0, r1, c, steps=24):
        """Thick quadratic/cubic Bezier, radius tapering r0 -> r1."""
        n = len(pts) - 1
        for i in range(steps + 1):
            t = i / steps
            x = y = 0
            for k, (px, py) in enumerate(pts):
                b = math.comb(n, k) * t ** k * (1 - t) ** (n - k)
                x += b * px
                y += b * py
            r = r0 + (r1 - r0) * t
            self.ellipse(x, y, r, r, c)


# ------------------------------------------------------------ cats
BODY, LIGHT, HOLE = 1, 2, 3


def leg(cv, x0, y0, x1, y1, r=2.4):
    cv.capsule(x0, y0, x1, y1, r, BODY)
    cv.ellipse(x1, y1 - 0.5, r + 0.4, r * 0.8, LIGHT)


def head(cv, cx, cy, eye=True, ears=True, tilt=0):
    if ears:
        cv.poly([(cx - 7, cy - 3), (cx - 4.5 + tilt, cy - 12), (cx + 1, cy - 6)], BODY)
        cv.poly([(cx + 1, cy - 6), (cx + 6 + tilt, cy - 12), (cx + 8, cy - 2)], BODY)
    cv.ellipse(cx, cy, 8, 7, BODY)
    cv.ellipse(cx + 7, cy + 5, 3, 2, LIGHT)
    if eye:
        cv.ellipse(cx + 3.5, cy - 1.5, 1.6, 1.8, HOLE)
        cv.eye = (cx + 3.5, cy - 1.5)
    else:
        cv.rect(int(cx + 2), int(cy - 1), int(cx + 6), int(cy), HOLE)


# crouched over the bowl, facing right: tail up, haunches high, back sloping
# down to a lowered head with pricked ears; frame 1 dips the head into the bowl
EAT_GRID = [
    ["..#...........",
     ".#............",
     ".#.####.......",
     "..######......",
     "..#######..#.#",
     "..########.###",
     "..############",
     "..##########WW",
     "..###.....#.WW",
     "..##.....##..."],
    ["..#...........",
     "..#...........",
     ".#.####.......",
     "..######......",
     "..#######.....",
     "..#######..#.#",
     "..########.###",
     "..############",
     "..###.....##WW",
     "..##.....##.WW"],
]


def draw_cat(pose):
    cv = Canvas(CAT_PX_W, 40, 0)
    g = 39  # ground
    if pose.startswith("run"):
        f = int(pose[3])
        bob = [0, -1, -2, -1][f]
        bx, by = 26, 25 + bob
        stretch = [19, 18, 16, 18][f]
        cv.curve([(bx - stretch + 3, by - 3), (bx - stretch - 6, by - 6 - f), (bx - stretch - 4, by - 16 + f)],
                 2.4, 1.6, BODY)
        fl = [((38, by + 3), (51, g - 5)), ((38, by + 3), (40, g)), ((37, by + 3), (34, g)), ((38, by + 3), (46, g))][f]
        bl = [((15, by + 3), (2, g - 4)), ((15, by + 3), (18, g)), ((17, by + 3), (22, g)), ((15, by + 3), (8, g))][f]
        leg(cv, *bl[0], bl[1][0] + 2, bl[1][1])
        leg(cv, *fl[0], fl[1][0] - 2, fl[1][1])
        cv.ellipse(bx, by, stretch, 7.5, BODY)
        cv.ellipse(bx + stretch - 7, by + 3, 6, 4, LIGHT)
        leg(cv, *bl[0], *bl[1])
        leg(cv, *fl[0], *fl[1])
        head(cv, 45, 16 + bob)
    elif pose.startswith("sit"):
        f = int(pose[3])
        cv.curve([(14, g - 2), (2, g - 1), (4 if f == 0 else 1, g - 9 - 3 * f)], 2.6, 1.8, BODY)
        cv.ellipse(22, g - 9, 12, 9, BODY)
        cv.ellipse(30, g - 17, 9, 12, BODY)
        cv.ellipse(36, g - 14, 4.5, 7, LIGHT)
        leg(cv, 36, g - 12, 37, g, 2.6)
        leg(cv, 31, g - 12, 33, g, 2.6)
        head(cv, 37, 14, eye=(f == 0), tilt=f)
    elif pose == "bat":
        cv.curve([(14, g - 2), (2, g - 3), (3, g - 12)], 2.6, 1.8, BODY)
        cv.ellipse(22, g - 8, 12, 8, BODY)
        cv.ellipse(31, g - 15, 9, 11, BODY)
        leg(cv, 33, g - 12, 34, g, 2.6)
        cv.capsule(36, g - 18, 47, g - 26, 2.4, BODY)
        cv.ellipse(49, g - 27, 3, 2.6, LIGHT)
        head(cv, 39, 13, tilt=1)
    elif pose.startswith("sleep"):
        f = int(pose[5])
        cv.ellipse(27, g - 6 - f * 0.6, 19, 6.5 + f * 0.8, BODY)
        cv.curve([(9, g - 2), (20, g + 1), (42, g - 1)], 2.6, 2.0, BODY)
        cv.ellipse(40, g - 2, 4, 2.5, LIGHT)
        head(cv, 45, g - 7, eye=False, tilt=-2)
    elif pose == "hiss":
        cv.curve([(10, g - 18), (2, g - 26), (8, g - 36)], 2.8, 2.0, BODY)
        cv.ellipse(25, g - 20, 16, 7, BODY)
        cv.ellipse(25, g - 23, 12, 6, BODY)
        leg(cv, 14, g - 18, 11, g)
        leg(cv, 18, g - 18, 19, g)
        leg(cv, 34, g - 18, 36, g)
        leg(cv, 38, g - 18, 43, g)
        head(cv, 45, g - 21, tilt=-2)
        cv.rect(48, g - 17, 52, g - 15, HOLE)
    elif pose.startswith("eat"):
        # drawn on the 4 px quarter-block grid so the shape survives conversion
        for y, row in enumerate(EAT_GRID[int(pose[3])]):
            for x, ch in enumerate(row):
                if ch != ".":
                    cv.rect(x * 4, y * 4, x * 4 + 4, y * 4 + 4, LIGHT if ch == "W" else BODY)
    elif pose == "jump":
        cv.curve([(10, 19), (2, 14), (0, 6)], 2.4, 1.6, BODY)
        cv.capsule(14, 24, 2, 31, 2.4, BODY)
        cv.capsule(37, 22, 52, 15, 2.4, BODY)
        cv.ellipse(52, 15, 3, 2.6, LIGHT)
        cv.ellipse(26, 20, 18, 6.5, BODY)
        head(cv, 45, 11)
    return cv


# front view, looking at the viewer and meowing. Hand-placed: the engine snaps
# cx to a whole cell first. (char, palette index) with 3 = eye colour.
B, L_, E_, T = BODY, LIGHT, 3, None
MEOW_FRONT = [
    [None, None, (0xe9, B), None, None, (0xdf, B), None, None],
    [None, None, (0xa0, B), (0x51, E_), (0x51, E_), (0xa0, B), None, None],
    [None, None, (0x5f, B), (0xec, L_), (0xfb, L_), (0x69, B), None, None],
    [None, (0xe9, B), (0xa0, B), (0xa0, L_), (0xa0, L_), (0xa0, B), None, (0x6c, B)],
    [None, (0x6c, B), (0xa0, B), (0xa0, L_), (0xa0, L_), (0xa0, B), (0x62, B), (0xe1, B)],
]


def cat_cells(pose, facing, phase):
    """40 (char, palette index) cells for the 8x5 box; index 0 = transparent."""
    if pose == "meow":
        return [c or (32, 0) for row in MEOW_FRONT for c in row]
    src = draw_cat(pose)
    box = Canvas(CAT_W * 8, CAT_H * 8, 0)
    ox = phase * 2
    for y in range(src.h):
        for x in range(src.w):
            sx = x if facing == 0 else src.w - 1 - x
            box.put(ox + x, y, src.get(sx, y))
    eye = getattr(src, "eye", None)
    eyecell = None
    if eye:
        ex = ox + (eye[0] if facing == 0 else src.w - 1 - eye[0])
        eyecell = int(eye[1]) // 8 * CAT_W + int(ex) // 8
    cells = []
    for r in range(CAT_H):
        for c in range(CAT_W):
            bits = heavy = 0
            count = [0, 0, 0]
            for y in range(8):
                for x in range(8):
                    v = box.get(c * 8 + x, r * 8 + y)
                    bits <<= 1
                    heavy <<= 1
                    if v in (BODY, LIGHT):
                        bits |= 1
                        count[v] += 1
                    elif v == HOLE:
                        heavy |= 1
            if bits == 0:
                cells.append((32, 0))
                continue
            ch = best_char(bits, heavy, CAT_CANDS)
            if len(cells) == eyecell and ch == 160:
                ch = 0xd1           # full block with a round hole: the eye
            col = BODY if count[BODY] >= count[LIGHT] else LIGHT
            cells.append((ch, 0 if ch == 32 else col))
    return cells


# ------------------------------------------------------------ the room
def region_bg(row):
    return WALL_BG if row < SPLIT_ROW else FLOOR_BG


def draw_room():
    cv = Canvas(320, 200, None)       # None = region background
    # wall: purple with darker vertical pinstripes
    for y in range(0, 120):
        for x in range(320):
            cv.put(x, y, PURPLE)
    for x in range(4, 320, 16):
        cv.rect(x, 0, x + 1, 112, DGREY)
    cv.rect(0, 112, 320, 120, DGREY)  # skirting board (no light grey: it cut the grey cat)
    cv.rect(0, 112, 320, 113, GREY)
    # floor planks
    for y in range(120, 200, 10):
        cv.rect(0, y + 8, 320, y + 9, BLACK)
        off = (y // 10 * 53) % 90
        for x in range(off, 320, 90):
            cv.rect(x, y, x + 1, y + 8, BLACK)

    # window above the couch: night sky is the blue background
    wx0, wy0, wx1, wy1 = 40, 8, 112, 56
    cv.rect(wx0 - 4, wy0 - 4, wx1 + 4, wy1 + 4, LGREY)
    cv.rect(wx0, wy0, wx1, wy1, None)
    cv.rect(wx0 + 34, wy0, wx0 + 38, wy1, LGREY)   # mullion
    cv.rect(wx0, wy0 + 22, wx1, wy0 + 26, LGREY)   # transom
    cv.ellipse(96, 20, 7, 7, YELLOW)                # moon
    cv.ellipse(100, 17, 5.5, 5.5, None)
    cv.rect(wx0 - 8, wy1 + 4, wx1 + 8, wy1 + 7, WHITE)  # sill

    # couch: body is background blue, outlined in light blue
    x0, x1 = 8, 136
    cv.rect(x0 + 10, 70, x1 - 10, 104, None)       # back + seat
    cv.rect(x0 + 10, 70, x1 - 10, 72, LBLUE)        # top of back
    for cx in range(x0 + 10, x1 - 10, 38):
        cv.rect(cx, 72, cx + 1, 96, LBLUE)          # back cushion seams
    cv.rect(x0 + 10, 96, x1 - 10, 97, LBLUE)        # seat line
    cv.rect(x0 + 10, 104, x1 - 10, 112, LBLUE)      # front rail
    for ax in (x0, x1 - 16):                        # armrests
        cv.ellipse(ax + 8, 84, 8, 6, LBLUE)
        cv.rect(ax, 84, ax + 16, 112, LBLUE)
    cv.rect(x0 + 2, 112, x0 + 6, 122, BLACK)        # legs
    cv.rect(x1 - 6, 112, x1 - 2, 122, BLACK)

    # floor lamp between couch and desk
    cv.poly([(148, 26), (168, 26), (174, 44), (142, 44)], YELLOW)
    cv.rect(157, 44, 159, 114, GREY)
    cv.ellipse(158, 116, 8, 2.5, DGREY)

    # desk
    dx0, dx1 = 180, 318
    cv.rect(dx0, 88, dx1, 94, ORANGE)
    cv.rect(dx0 + 2, 94, dx0 + 8, 121, BROWN)
    cv.rect(dx1 - 8, 94, dx1 - 2, 121, BROWN)
    cv.rect(dx0 + 2, 94, dx1 - 2, 96, BROWN)
    # floppy drive with slot; LED cell is animated
    cv.rect(186, 68, 218, 88, LGREY)
    cv.rect(190, 75, 214, 77, BLACK)
    cv.rect(201, 73, 203, 79, DGREY)
    # monitor: bezel grey around the text area (background = glass)
    tx0, ty0 = TERM_X * 8, TERM_Y * 8
    tx1, ty1 = tx0 + TERM_W * 8, ty0 + TERM_H * 8
    cv.rect(tx0 - 8, ty0 - 8, tx1 + 8, ty1 + 10, GREY)
    cv.rect(tx0 - 8, ty0 - 8, tx1 + 8, ty0 - 7, LGREY)
    cv.rect(tx0, ty0, tx1, ty1, None)
    cv.rect(tx1, ty1 + 4, tx1 + 3, ty1 + 6, RED)    # power light
    cv.rect(tx0 + 20, ty1 + 10, tx1 - 20, ty1 + 16, DGREY)  # stand
    # automatic cat feeder under the desk, bowl on the floor in front of it
    cv.rect(FEED_X0, 98, FEED_X0 + 24, 118, CYAN)
    cv.rect(FEED_X0, 98, FEED_X0 + 24, 100, LGREY)
    cv.rect(FEED_X0 + 8, 102, FEED_X0 + 16, 112, DGREY)   # hopper window
    cv.rect(FEED_X0 + 9, 112, FEED_X0 + 15, 118, DGREY)   # chute
    cv.rect(FEED_X0 - 6, 128, FEED_X0 + 30, 131, RED)     # bowl rim
    cv.rect(FEED_X0 - 3, 131, FEED_X0 + 27, 135, RED)
    # breadbin keyboard
    cv.poly([(226, 82), (304, 82), (308, 88), (222, 88)], BROWN)
    for kx in range(230, 302, 4):
        cv.rect(kx, 83, kx + 2, 85, DGREY)
    cv.rect(240, 86, 288, 87, DGREY)
    return cv


def room_cells(cv):
    scr, col = [], []
    for r in range(25):
        bg = region_bg(r)
        for c in range(40):
            bits, count = 0, {}
            for y in range(8):
                for x in range(8):
                    v = cv.get(c * 8 + x, r * 8 + y)
                    bits <<= 1
                    if v is not None and v != bg:
                        bits |= 1
                        count[v] = count.get(v, 0) + 1
            if not bits:
                scr.append(32)
                col.append(bg)
                continue
            fg = max(count, key=count.get)
            # pixels of other colours become background, keep the majority's shape
            bits = 0
            for y in range(8):
                for x in range(8):
                    bits = bits << 1 | (cv.get(c * 8 + x, r * 8 + y) == fg)
            ch = best_char(bits)
            scr.append(ch)
            col.append(fg)
    return scr, col


FEED_X0 = 216                 # feeder hopper x (cell aligned)
KIBBLE = (27, 15)             # 3 kibble cells above the bowl (row 16)
FEED_LIGHT = (29, 12)
STARS = [(6, 1, 0x2e), (8, 2, 0x2a), (12, 1, 0x2e), (7, 5, 0x2e), (10, 4, 0x2e), (13, 5, 0x2a)]
LED = (24, 9)   # floppy LED cell


def sc(text):
    out = []
    for ch in text:
        o = ord(ch)
        out.append(o - 64 if 65 <= o <= 90 else o)
    return out


NL = 0x60     # newline; screen code $0d is the letter M


def term_script():
    """Bytes: <$80 char, $60 newline, $80+n wait n frames, $c0/$c1 LED on/off, $c2 clear, $c3/$c4 loader stripes on/off, $ff loop."""
    s = []

    def wait(n):
        while n > 0:
            s.append(0x80 + min(n, 63))
            n -= 63

    def typ(text, speed=7):
        for code in sc(text):
            s.append(code)
            wait(speed + (code * 7) % 5)

    def out(text):
        s.extend(sc(text))

    s.append(0xc2)
    out("CATSIM 64")
    s.append(NL)
    out("READY.")
    s.append(NL)
    wait(150)
    typ('LOAD"*",8')   # 9 chars: the line wraps by itself
    wait(20)
    out("SEARCHING")
    s.append(0xc0)
    wait(90)
    s.append(NL)
    out("LOADING")
    wait(40)
    s.append(0xc3)     # loader stripes
    wait(250)
    s.append(0xc4)     # stripes off, monitor cleared
    s.append(0xc1)
    out("READY.")
    s.append(NL)
    wait(80)
    typ("RUN")
    wait(15)
    s.append(NL)
    for _ in range(6):
        wait(30)
        out("MEOW!")
        s.append(NL)
    out("PURRRRRRR")
    s.append(NL)
    wait(120)
    out("BREAK")
    s.append(NL)
    out("READY.")
    s.append(NL)
    wait(200)
    s.append(0xff)
    return s


# ------------------------------------------------------------ sprites
FONT = {
    "M": ["10001", "11011", "10101", "10001", "10001"],
    "E": ["1111", "1000", "1110", "1000", "1111"],
    "O": ["0110", "1001", "1001", "1001", "0110"],
    "W": ["10001", "10001", "10101", "11011", "10001"],
    "H": ["1001", "1001", "1111", "1001", "1001"],
    "I": ["111", "010", "010", "010", "111"],
    "S": ["0111", "1000", "0110", "0001", "1110"],
}


def bubble_shape():
    """Cartoon speech balloon (rounded box + tail pointing down) as a mask."""
    shape = blank()
    for y in range(11):
        for x in range(24):
            cut = [2, 1] + [0] * 7 + [1, 2]
            if cut[y] <= x <= 23 - cut[y]:
                shape[y][x] = True
    for y in range(11, 15):
        for x in range(23):
            if 9 + (y - 10) <= x <= 13 - (y - 10) * 1.2 + 0.5:
                shape[y][x] = True
    return shape


def sprite_bytes(pix):
    """pix: 21 rows of 24 booleans -> 64 bytes."""
    out = []
    for y in range(21):
        for b in range(3):
            v = 0
            for x in range(8):
                v = v << 1 | (1 if pix[y][b * 8 + x] else 0)
            out.append(v)
    return out + [0]


def blank():
    return [[False] * 24 for _ in range(21)]


BALL_R = 5.6
BALL_C = 6.0


def ball_frames():
    """16 rolling frames of yarn strands + the base disc."""
    norms = []
    for a, b in [(0, 90), (60, 70), (120, 50), (30, 20), (100, 10)]:
        ar, br = math.radians(a), math.radians(b)
        norms.append((math.cos(ar) * math.cos(br), math.sin(ar) * math.cos(br), math.sin(br)))
    frames = []
    for f in range(16):
        ang = f * 2 * math.pi / 16
        pix = blank()
        for y in range(12):
            for x in range(12):
                dx, dy = (x + 0.5 - BALL_C) / BALL_R, (y + 0.5 - BALL_C) / BALL_R
                rr = dx * dx + dy * dy
                if rr > 1:
                    continue
                dz = math.sqrt(1 - rr)
                # roll: rotate around the view axis (screen plane)
                px = dx * math.cos(ang) + dy * math.sin(ang)
                py = -dx * math.sin(ang) + dy * math.cos(ang)
                # tilt a little so it reads as a sphere
                qy = py * math.cos(0.5) - dz * math.sin(0.5)
                qz = py * math.sin(0.5) + dz * math.cos(0.5)
                strand = any(abs(px * n[0] + qy * n[1] + qz * n[2]) < 0.13 for n in norms)
                edge = rr > 0.72 and (dx + dy) > 0.3
                pix[y][x] = strand or edge
        frames.append(sprite_bytes(pix))
    disc = blank()
    for y in range(12):
        for x in range(12):
            if ((x + 0.5 - BALL_C) ** 2 + (y + 0.5 - BALL_C) ** 2) <= BALL_R ** 2 + 0.6:
                disc[y][x] = True
    shadow = blank()
    for y in range(3):
        for x in range(14):
            if ((x + 0.5 - 7) / 7) ** 2 + ((y + 0.5 - 1.5) / 1.6) ** 2 <= 1:
                shadow[y][x] = True
    return frames, sprite_bytes(disc), sprite_bytes(shadow)


def zzz_frames():
    out = []
    for size in (3, 4, 5):
        pix = blank()
        for x in range(size):
            pix[0][x] = pix[size - 1][x] = True
        for i in range(size):
            pix[i][size - 1 - i] = True
        out.append(sprite_bytes(pix))
    return out


def word_sprite(word):
    """Balloon outline plus text; the filled balloon is a separate sprite behind it."""
    shape = bubble_shape()
    pix = blank()
    for y in range(21):
        for x in range(24):
            if shape[y][x] and any(not (0 <= y + dy < 21 and 0 <= x + dx < 24 and shape[y + dy][x + dx])
                                   for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                pix[y][x] = True
    width = sum(len(FONT[ch][0]) + 1 for ch in word) - 1
    x0 = (24 - width) // 2
    for ch in word:
        for y, row in enumerate(FONT[ch]):
            for x, b in enumerate(row):
                if b == "1":
                    pix[3 + y][x0 + x] = True
        x0 += len(FONT[ch][0]) + 1
    return sprite_bytes(pix)


# ------------------------------------------------------------ meows
# A meow, after the phonetics research (Schötz et al.): f0 of a few hundred
# Hz in a rise-fall arch (rising endings sound friendly/asking, falling ones
# plaintive) and a vowel glide "i-a-u" driven mostly by F1, i.e. the jaw
# opening and closing. On the SID: a pulse wave for the voice, the resonant
# lowpass cutoff as F1 (closed "m", open "a", closing "ow"), frame by frame.
PAL_HZ = 985248 / 16777216      # Hz per frequency register step

#            frames  start  peak  end   peak-at  F1 open  vibrato
MEOW_KINDS = [(22,   -2,    +3,   0,    0.35,   0x48,    0),     # short "mew"
              (36,   -3,    +2,   -4,   0.35,   0x60,    0),     # normal "meow"
              (52,   -2,    +1,   -6,   0.25,   0x58,    0.45),  # long plaintive "meeoooow"
              (34,   -4,    0,    +3,   0.45,   0x50,    0)]     # questioning "mrr-ow?"
MEOW_BASE = [470, 600]          # Hz: the orange cat's voice is lower than the grey's


def meow_script(base, kind):
    n, s0, sp, s1, tp, f1, vib = kind
    out = [3, 0, 1, 0, 0, 4, 1]                       # hard restart
    out += [1, 0x36, 0xa9, 5, 0x00, 0x06, 6, 0x0c]    # ADSR, pulse width, closed filter
    for i in range(n):
        t = i / (n - 1)
        if t < tp:                                     # pitch arch (semitones)
            semi = s0 + (sp - s0) * math.sin(t / tp * math.pi / 2)
        else:
            semi = sp + (s1 - sp) * (1 - math.cos((t - tp) / (1 - tp) * math.pi / 2))
        if vib and t > 0.3:                            # ~5.5 Hz vibrato on the held part
            semi += vib * math.sin(i * 2 * math.pi / 9)
        fn = int(base * 2 ** (semi / 12) / PAL_HZ)
        if t < tp:                                     # F1: jaw opens, then closes
            cut = 0x0c + (f1 - 0x0c) * math.sin(t / tp * math.pi / 2)
        else:
            cut = f1 + (0x0c - f1) * ((t - tp) / (1 - tp)) ** 0.8   # ends low: the purr shares it
        out += [2, fn & 255, fn >> 8, 6, int(cut)]
        if i == 0:
            out += [3, 0x41]                           # gate on with the first note
        out += [4, 1]
    return out + [0]


# ------------------------------------------------------------ output
def byte_lines(data, per=16):
    return ["        .byte " + ",".join("$%02x" % b for b in data[i:i + per]) for i in range(0, len(data), per)]


def main():
    room = draw_room()
    scr, col = room_cells(room)
    for x, y, ch in STARS:
        scr[y * 40 + x] = ch
        col[y * 40 + x] = WHITE
    scr[LED[1] * 40 + LED[0]] = 0x62 + 0x80 - 0x80   # small block, colour animated
    col[LED[1] * 40 + LED[0]] = DGREY
    scr[FEED_LIGHT[1] * 40 + FEED_LIGHT[0]] = 0x51
    col[FEED_LIGHT[1] * 40 + FEED_LIGHT[0]] = DGREY

    cats = cat_frames()
    dyn = dyn_codes(scr)

    balls, disc, shadow = ball_frames()
    zz = zzz_frames()
    words = [word_sprite("MEOW"), word_sprite("HISS"), sprite_bytes(bubble_shape())]

    L = ["; generated by gen.py - do not edit", ""]
    names = "BLACK WHITE RED CYAN PURPLE GREEN BLUE YELLOW ORANGE BROWN LRED DGREY GREY LGREEN LBLUE LGREY"
    for i, n in enumerate(names.split()):
        L.append("%s = %d" % (n, i))
    L.append("SPLIT_ROW = %d" % SPLIT_ROW)
    L.append("WALL_BG = %d" % WALL_BG)
    L.append("FLOOR_BG = %d" % FLOOR_BG)
    L.append("TERM_X = %d" % TERM_X)
    L.append("TERM_Y = %d" % TERM_Y)
    L.append("TERM_W = %d" % TERM_W)
    L.append("TERM_H = %d" % TERM_H)
    L.append("LED_POS = %d" % (LED[1] * 40 + LED[0]))
    L.append("NSTARS = %d" % len(STARS))
    L.append("KIBBLE_POS = %d" % (KIBBLE[1] * 40 + KIBBLE[0]))
    L.append("FEED_LIGHT = %d" % (FEED_LIGHT[1] * 40 + FEED_LIGHT[0]))
    # eating spots: mouth (local x 52 facing right) at the bowl's edges
    L.append("FEED_LX = %d" % ((FEED_X0 - 4 - 52) // 2))
    L.append("FEED_RX = %d" % ((FEED_X0 + 28 - 3) // 2))
    L.append("FEED_CY = 12")
    L.append("FEED_X0 = %d" % FEED_X0)
    L.append("NL = $%02x" % NL)
    L.append("MOUTH_X = %d" % MOUTH[0])
    L.append("MOUTH_Y = %d" % MOUTH[1])
    L.append("NPOSES = %d" % len(POSES))
    for i, p in enumerate(POSES):
        L.append("P_%s = %d" % (p.upper(), i))
    L.append("")
    L.append("")
    L.append("; sprites, 64 bytes each, starting at SPRITES")
    L.append("SPR_BALL = 0")
    L.append("SPR_DISC = 16")
    L.append("SPR_SHADOW = 17")
    L.append("SPR_Z = 18")
    L.append("SPR_MEOW = 21")
    L.append("SPR_HISS = 22")
    L.append("SPR_BUBBLE = 23")
    L.append("DYNCODES = [%s]" % ", ".join("$%02x" % c for c in dyn))
    sprite_data = sum(balls, []) + disc + shadow + sum(zz, []) + sum(words, [])
    S = ["; generated by gen.py - do not edit", "spritedata"]
    S += byte_lines(sprite_data)
    S.append("spritedata_end")
    open(os.path.join(HERE, "catspr.inc"), "w").write("\n".join(S) + "\n")
    L.append("stripes")
    L += byte_lines(LOADER_STRIPES)
    L.append("starpos .word " + ",".join(str(y * 40 + x) for x, y, _ in STARS))
    L.append("bgscreen")
    L += byte_lines(scr)
    L.append("bgcolour")
    L += byte_lines(col)
    L.append("termscript")
    L += byte_lines(term_script())
    # cat frames, (pose*2+facing)*4+phase: a cell count, then per cell its
    # box index (row*8+col), screen offset in the box, palette index and 8
    # bitmap bytes. Meow has a single (cell aligned, front) frame. The
    # left-facing frames go to catleft.inc (RAM under the BASIC ROM).
    first = {}
    for i, cells in enumerate(cats):
        first.setdefault(id(cells), i)
    L.append("framelo .byte " + ", ".join("<cf%d" % first[id(c)] for c in cats))
    L.append("framehi .byte " + ", ".join(">cf%d" % first[id(c)] for c in cats))
    size, R = 0, ["; generated by gen.py - do not edit: left-facing cat frames"]
    for i, cells in enumerate(cats):
        if first[id(cells)] != i:
            continue
        out = R if (i // PHASES) % 2 else L
        out.append("cf%d" % i)
        data = [len(cells)]
        for idx, pal, rows in cells:
            data += [idx, idx // CAT_W * 40 + idx % CAT_W, pal] + list(rows)
        size += len(data)
        out += byte_lines(data)
    open(os.path.join(HERE, "catleft.inc"), "w").write("\n".join(R) + "\n")
    # 6581 filter: its cutoff curve sits much higher on the register scale
    # than the 8580's linear one, so the scripts' (8580) values are remapped
    L.append("cut6581")
    L += byte_lines([min(255, int(0x38 + v * 0.9)) for v in range(256)])
    L.append("; meow variants: cat*4 + kind (mew, meow, plaintive, questioning)")
    for c, base in enumerate(MEOW_BASE):
        for k, kind in enumerate(MEOW_KINDS):
            L.append("meow%d" % (c * 4 + k))
            L += byte_lines(meow_script(base, kind))
    open(os.path.join(HERE, "catsim.inc"), "w").write("\n".join(L) + "\n")
    print("cat frames:", len(cats), "bytes:", size, "free codes:", len(dyn), "sprites:", len(sprite_data) // 64)

    import title
    title.build(sys.modules[__name__], cats)

    if "--preview" in sys.argv:
        preview(scr, col, cats)


# tape-loader stripes on the monitor: ROM chars made only of full-width rows
LOADER_STRIPES = [0x40, 0x43, 0x44, 0x45, 0x46, 0x52, 0x62, 0x63, 0x64, 0x6f, 0x77, 0x78, 0x79,
                  0xc0, 0xc4, 0xc5, 0xc6, 0xd2, 0xe2, 0xe3, 0xe4, 0xef, 0xf7, 0xf8, 0xf9,
                  0x62, 0xe2, 0x78, 0xf9, 0xc4, 0xa0, 0x20]


def cat_frames():
    """Hi-res cat frames from art/art2.py (C3 style: white socks, tabby holes),
    POSES x facing x PHASES. Each is a list of (box index, palette index,
    8 bitmap rows) for the non-empty cells; a cell is white (palette 2) only
    when at least 3/4 of its pixels are light."""
    sys.path.insert(0, os.path.join(HERE, "art"))
    import art2
    art2.SOCKS = True
    frames, cache = [], {}
    for pose in POSES:
      for facing in (0, 1):
        for ph in range(PHASES):
            if pose == "meow":
                ph = facing = 0
            if (pose, facing, ph) not in cache:
                box = art2.placed(pose, facing, ph)
                cells = []
                for r in range(CAT_H):
                    for c in range(CAT_W):
                        rows, nb, nl = [], 0, 0
                        for y in range(8):
                            v = 0
                            for x in range(8):
                                px = box.get(c * 8 + x, r * 8 + y)
                                v <<= 1
                                if px in (art2.BODY, art2.LIGHT):
                                    v |= 1
                                    nl += px == art2.LIGHT
                                    nb += px == art2.BODY
                            rows.append(v)
                        if any(rows):
                            cells.append((r * CAT_W + c, 2 if nl >= 0.75 * (nl + nb) else 1, tuple(rows)))
                cache[pose, facing, ph] = cells
            frames.append(cache[pose, facing, ph])
    return frames


def dyn_codes(scr):
    """80 screen codes the room never shows: 40 per cat, one per box cell,
    redefined on the fly in the RAM charset."""
    used = set(scr) | {0x20, 0xa0, 0x2e, 0x2a, 0x51, 0x62, 0x6c, 0x7b, 0xe9, 0xdf}
    used |= set(LOADER_STRIPES)
    used |= {b for b in term_script() if b < NL}
    used |= set(range(0x01, 0x1b)) | set(range(0x30, 0x3a))
    free = [c for c in range(256) if c not in used]
    assert len(free) >= 2 * CAT_W * CAT_H, len(free)
    return free[:2 * CAT_W * CAT_H]


def render_cell(img, cx, cy, code, fg, bg, scale=2):
    bits = char_bits(code)
    for y in range(8):
        for x in range(8):
            on = bits >> (63 - (y * 8 + x)) & 1
            v = PAL[fg if on else bg]
            rgb = (v >> 16, v >> 8 & 255, v & 255)
            for sy in range(scale):
                for sx in range(scale):
                    img.putpixel(((cx * 8 + x) * scale + sx, (cy * 8 + y) * scale + sy), rgb)


def preview(scr, col, cats):
    from PIL import Image
    img = Image.new("RGB", (640, 400))
    catpal = [[0, BLACK, WHITE], [0, LGREY, WHITE]]
    over = {}

    def stamp(i, pose, facing, ph, cx, cy):
        for idx, pal, rows in cats[(POSES.index(pose) * 2 + facing) * PHASES + ph]:
            r, c = divmod(idx, CAT_W)
            over[(cy + r) * 40 + cx + c] = (rows, catpal[i][pal])
    stamp(0, "sleep0", 0, 0, 4, 8)
    stamp(1, "run1", 1, 2, 20, 17)
    stamp(0, "bat", 0, 1, 6, 19)
    stamp(1, "meow", 0, 0, 30, 18)
    for i in range(1000):
        if i in over:
            rows, fg = over[i]
            for y in range(8):
                for x in range(8):
                    v = PAL[fg if rows[y] >> (7 - x) & 1 else region_bg(i // 40)]
                    for sy in range(2):
                        for sx in range(2):
                            img.putpixel((((i % 40) * 8 + x) * 2 + sx, ((i // 40) * 8 + y) * 2 + sy),
                                         (v >> 16, v >> 8 & 255, v & 255))
        else:
            render_cell(img, i % 40, i // 40, scr[i], col[i], region_bg(i // 40))
    img.save(os.path.join(HERE, "preview.png"))


if __name__ == "__main__":
    main()

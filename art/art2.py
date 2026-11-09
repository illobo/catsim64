"""Round-2 master art (C2/D2): 1 px, 64x40 box, facing right.

Changes from art.py (v1):
- near legs are cut free from the far legs and the belly by a 1 px gap
  (background shows through), so the run cycle reads in one colour;
- "socks": every leg pixel in the bottom cell row (y >= 32) is LIGHT. That
  row is fixed by cy, so the white paws land in whole cells at every x phase;
- inner ear = a small hole in the near ear, eye options E1/E2/E3;
- sleep is a curled loaf with the tail wrapped round the front (cut free);
- the front view is laid out on the cell grid: white muzzle + bib occupy
  exactly cells 3-4, rows 2-4 (a tuxedo front), so they survive hi-res.
Colour indices as in art.py: 0 T, 1 BODY, 2 LIGHT, 3 EYE, 4 DARK, 5 ACC.
EYE and DARK are holes in hi-res."""
import art
from art import Canvas, T, BODY, LIGHT, EYE, DARK, ACC

W, H = 64, 40
G = 39
SOCK_Y = 32
SOCKS = False             # C3: white socks (leg pixels in the bottom cell row)
EYE_STYLE = "E3"          # E1 hole, E2 none, E3 hole with a glint pixel (chosen)
FRONT_PRECISE = False
BIB = False               # side-view chest bib: only multicolour can show it     # MC: muzzle + bib as shapes instead of the cell-aligned tuxedo
STRIPES = True
POSES = art.POSES
STATIC = {"sit0", "sit1", "sleep0", "sleep1", "meow", "eat0", "eat1", "bat"}


class Cv(Canvas):
    def fill_if(self, test, c, only=(BODY,)):
        for y in range(self.h):
            for x in range(self.w):
                if self.get(x, y) in only and test(x, y):
                    self.put(x, y, c)


def leg(cv, x0, y0, x1, y1, r=1.9, cut=False):
    """Leg from hip/shoulder (x0,y0) to paw (x1,y1). cut: 1 px gap round the
    lower part so it separates from whatever is behind it."""
    if cut:
        # start the gap a little below the joint so the body outline stays whole
        t0 = 0.35
        sx, sy = x0 + (x1 - x0) * t0, y0 + (y1 - y0) * t0
        cv.capsule(sx, sy, x1, y1, r + 1.0, T)
    c = Cv(cv.w, cv.h, T)
    c.capsule(x0, y0, x1, y1, r, BODY)
    c.ellipse(x1 + 0.8, y1 - 0.6, r + 0.5, 1.2, BODY)      # paw
    for y in range(cv.h):
        for x in range(cv.w):
            if c.get(x, y) == BODY:
                cv.put(x, y, LIGHT if SOCKS and y >= SOCK_Y else BODY)


def socks(cv):
    pass                  # socks are painted per leg in leg()


def stripes(cv, xs, y0, y1):
    if not STRIPES:
        return
    for x in xs:
        for y in range(int(y0), int(y1)):
            if cv.get(x, y) == BODY and cv.get(x, y - 1) in (BODY, DARK):
                cv.put(x, y, DARK)


def eye(cv, x, y):
    x, y = int(round(x)), int(round(y))
    if EYE_STYLE == "E1":
        cv.rect(x, y, x + 2, y + 2, EYE)
    elif EYE_STYLE == "E3":
        cv.rect(x, y - 1, x + 3, y + 2, EYE)
        cv.put(x + 2, y - 1, BODY)            # glint, top front corner
    cv.eye = (x, y)


def head(cv, cx, cy, look="open", ear_back=0, mouth=False):
    """Side head facing right; cx,cy = skull centre. ear_back tilts ears back."""
    e = ear_back
    # far ear, then near ear (with inner-ear hole)
    cv.poly([(cx - 6.5, cy - 1.5), (cx - 5.5 - e, cy - 11), (cx - 1, cy - 4.5)], BODY)
    cv.poly([(cx - 1.5, cy - 4.5), (cx + 2.5 - e, cy - 11.5), (cx + 5.5, cy - 3)], BODY)
    cv.ellipse(cx, cy - 0.3, 6.6, 5.8, BODY)              # skull
    cv.ellipse(cx - 0.5, cy + 2.0, 7.0, 4.2, BODY)        # cheeks
    cv.ellipse(cx + 5.2, cy + 2.3, 3.0, 2.3, BODY)        # short muzzle
    cv.put(int(cx + 1.5 - e), int(cy - 7), ACC)          # inner ear (2 px)
    cv.put(int(cx + 1.5 - e), int(cy - 6), ACC)
    cv.put(int(cx + 8), int(cy + 1), DARK)                # nose notch
    if mouth:
        cv.poly([(cx + 4, cy + 3), (cx + 9, cy + 2), (cx + 9, cy + 6)], DARK)
    if look == "open":
        eye(cv, cx + 2.5, cy - 1.5)
    elif look == "closed":
        cv.rect(int(cx + 2), int(cy), int(cx + 6), int(cy + 1), DARK)
        cv.put(int(cx + 1), int(cy - 1), DARK)
    elif look == "squint":
        cv.rect(int(cx + 2), int(cy - 1), int(cx + 6), int(cy), DARK)


def tail(cv, pts, r0=1.9, r1=1.2, cut=False):
    if cut:
        cv.curve(pts, r0 + 1, r1 + 1, T, steps=48)
    cv.curve(pts, r0, r1, BODY, steps=48)


def draw_cat(pose):
    cv = Cv(W, H, T)
    g = G
    if pose.startswith("run"):
        f = int(pose[3])
        # 0 full stretch, 1 front legs land, 2 full gather (back arched), 3 push-off
        bob = [0, -1, -2, -1][f]
        by = 25 + bob
        stretch = [17, 15.5, 12.5, 15][f]
        bx = 25
        arch = [0, 1, 3, 1][f]
        tail(cv, [(bx - stretch + 3, by - 2), (bx - stretch - 6, by - 4 + f), (bx - stretch - 8, by - 13 + 2 * f)])
        # far legs (behind), offset in time
        far_f = [((35, by + 3), (44, g)), ((34, by + 3), (35, g)), ((34, by + 2), (40, g - 2)), ((35, by + 3), (48, g - 2))][f]
        far_b = [((16, by + 3), (9, g)), ((16, by + 3), (4, g - 2)), ((18, by + 2), (20, g)), ((16, by + 3), (13, g))][f]
        leg(cv, *far_b[0], *far_b[1])
        leg(cv, *far_f[0], *far_f[1])
        cv.ellipse(bx, by, stretch, 6.3, BODY)
        cv.ellipse(bx - 1, by - arch, stretch - 4, 6.3, BODY)      # back line / arch
        cv.ellipse(bx - stretch + 6, by + 1, 6, 6, BODY)            # haunch
        cv.ellipse(bx + stretch - 5, by + 1.5, 5, 5.3, BODY)        # chest
        near_f = [((37, by + 3), (51, g - 3)), ((37, by + 3), (42, g)), ((36, by + 3), (31, g)), ((37, by + 3), (38, g))][f]
        near_b = [((15, by + 3), (3, g - 3)), ((15, by + 3), (12, g)), ((17, by + 3), (25, g)), ((15, by + 3), (7, g))][f]
        leg(cv, *near_b[0], *near_b[1], r=2.1, cut=True)
        leg(cv, *near_f[0], *near_f[1], cut=True)
        stripes(cv, [bx - 9, bx - 5, bx - 1], by - 7 - arch, by - 3 - arch)
        hx, hy = 44 - (2 if f == 2 else 0), 15 + bob
        cv.capsule(bx + stretch - 5, by - 1, hx - 2, hy + 2, 4.6, BODY)   # neck
        head(cv, hx, hy, ear_back=1)
        socks(cv)
    elif pose.startswith("sit"):
        f = int(pose[3])
        if f == 0:                                                   # tail wrapped round the paws
            tail(cv, [(14, g - 1.5), (32, g + 1.5), (45, g - 4)], 1.8, 1.3)
        else:                                                        # tail flick behind
            tail(cv, [(13, g - 2), (5, g - 2), (5, g - 11)], 1.9, 1.3)
        cv.ellipse(22, g - 7.5, 11, 7.5, BODY)                       # haunch
        cv.poly([(15, g - 3), (25, g - 24), (35, g - 22), (37, g - 3)], BODY)
        cv.ellipse(30, g - 19, 6.5, 6, BODY)                         # shoulders
        leg(cv, 33, g - 13, 34, g - 0.5, 1.9, cut=True)
        leg(cv, 29, g - 13, 30, g - 0.5)
        if BIB:
            cv.ellipse(36, g - 14, 2.5, 5, LIGHT)                    # bib (MC only)
        stripes(cv, [16, 20, 24], g - 13, g - 9)
        head(cv, 33, 12, "open" if f == 0 else "closed")
    elif pose == "bat":
        tail(cv, [(13, g - 2), (5, g - 3), (4, g - 13)], 1.9, 1.3)
        cv.ellipse(22, g - 7.5, 11, 7.5, BODY)
        cv.poly([(15, g - 3), (25, g - 23), (35, g - 21), (37, g - 3)], BODY)
        cv.ellipse(30, g - 18, 6.5, 6, BODY)
        leg(cv, 31, g - 12, 32, g, 1.9, cut=True)
        cv.capsule(34, g - 19, 46, g - 26, 1.9, BODY)                # raised paw
        cv.ellipse(47, g - 26, 2.2, 2.0, BODY)
        stripes(cv, [16, 20, 24], g - 13, g - 9)
        head(cv, 36, 13)
        socks(cv)
    elif pose.startswith("sleep"):
        f = int(pose[5])
        b = f * 0.8                                                  # breathing
        cv.ellipse(25, g - 7 - b / 2, 16.5, 7.5 + b, BODY)           # curled body
        cv.ellipse(15, g - 6, 8, 6, BODY)                            # rump
        head(cv, 41, g - 9, "closed", ear_back=-1)
        cv.ellipse(42, g - 2, 5, 2.2, BODY)                          # chin on paws
        tail(cv, [(8, g - 4), (20, g + 1.5), (35, g - 4)], 1.9, 1.4)
        cv.ellipse(35, g - 4, 1.6, 1.6, BODY)
        stripes(cv, [17, 22, 27], g - 15 - b, g - 10 - b)
    elif pose == "hiss":
        tail(cv, [(12, g - 20), (4, g - 27), (8, g - 38)], 2.8, 2.2)  # bottle brush
        cv.ellipse(25, g - 19, 14, 6.5, BODY)
        cv.ellipse(24, g - 24, 10, 6.5, BODY)                        # arched back
        leg(cv, 14, g - 17, 11, g, 2.0)
        leg(cv, 33, g - 17, 35, g, 2.0)
        leg(cv, 18, g - 17, 20, g, 2.2, cut=True)
        leg(cv, 37, g - 17, 40, g, 2.2, cut=True)
        stripes(cv, [18, 22, 26], g - 30, g - 26)
        head(cv, 42, g - 18, "squint", ear_back=3, mouth=True)
        socks(cv)
    elif pose.startswith("eat"):
        f = int(pose[3])
        d = 2 * f
        tail(cv, [(10, 18), (5, 10), (8, 2)], 1.9, 1.3)
        cv.ellipse(20, 24, 11, 8.5, BODY)                            # haunches high
        cv.ellipse(31, 26 + d / 2, 9, 6, BODY)
        leg(cv, 14, 28, 13, g, 2.0)
        leg(cv, 22, 28, 22, g, 2.0, cut=True)
        leg(cv, 33, 29 + d / 2, 34, g, 1.9, cut=True)
        stripes(cv, [16, 20, 24], 16, 20)
        head(cv, 43, 29 + d, "closed")
        socks(cv)
    elif pose == "jump":
        tail(cv, [(10, 19), (3, 15), (1, 6)], 1.9, 1.3)
        leg(cv, 15, 22, 4, 28)
        leg(cv, 36, 21, 50, 15)
        cv.ellipse(26, 20, 17, 6.3, BODY)
        leg(cv, 14, 24, 2, 31, 2.1, cut=True)
        leg(cv, 37, 23, 52, 19, cut=True)
        stripes(cv, [18, 22, 26], 14, 17)
        head(cv, 45, 12, ear_back=2)
    elif pose == "meow":
        draw_front(cv)
    return cv


def draw_front(cv):
    """Front view in box coordinates (cell-snapped by the engine): the white
    muzzle and bib are exactly cells 3-4 (x 24-39), rows 2-4 (y 16-39)."""
    g = G
    cx = 32
    tail(cv, [(40, g - 1), (52, g - 2), (51, g - 14)], 1.9, 1.3)
    cv.ellipse(cx, g - 9, 10.5, 9, BODY)                  # body
    cv.ellipse(cx, g - 15, 8, 8, BODY)
    for lx in (cx - 4, cx + 3):
        cv.capsule(lx + 0.5, g - 12, lx + 0.5, g - 1, 2.0, BODY)
        cv.ellipse(lx + 0.5, g - 1, 2.6, 1.3, BODY)
    cv.rect(cx - 1, g - 9, cx, g + 1, DARK)               # line between the front legs
    hy = 12
    cv.poly([(cx - 10, hy), (cx - 9, hy - 11), (cx - 2, hy - 6)], BODY)   # ears
    cv.poly([(cx + 10, hy), (cx + 9, hy - 11), (cx + 2, hy - 6)], BODY)
    cv.poly([(cx - 8, hy - 3), (cx - 8, hy - 7.5), (cx - 5, hy - 5)], ACC)
    cv.poly([(cx + 8, hy - 3), (cx + 8, hy - 7.5), (cx + 5, hy - 5)], ACC)
    cv.ellipse(cx, hy + 0.5, 10, 7.5, BODY)
    cv.ellipse(cx, hy + 3.5, 11.5, 4.5, BODY)             # cheeks
    for ex in (cx - 5, cx + 3):                           # eyes: 3x3 holes, glint top-outer
        cv.rect(ex, hy - 1, ex + 3, hy + 2, EYE)
        cv.put(ex + (0 if ex < cx else 2), hy - 1, BODY)
    cv.rect(cx - 1, hy + 3, cx + 1, hy + 4, DARK)         # nose
    cv.poly([(cx - 3, hy + 6), (cx + 3, hy + 6), (cx, hy + 9)], DARK)   # open mouth
    stripes(cv, [cx - 2, cx, cx + 2], hy - 6, hy - 4)
    if FRONT_PRECISE:     # multicolour: white muzzle and a bib, pixel-exact
        cv.fill_if(lambda x, y: ((x - cx) / 4.5) ** 2 + ((y - hy - 5) / 2.6) ** 2 <= 1, LIGHT)
        cv.fill_if(lambda x, y: ((x - cx) / 4.5) ** 2 + ((y - g + 13) / 6) ** 2 <= 1, LIGHT)
    else:                 # tuxedo: everything of the body inside cells 3-4, rows 2-4 is white
        cv.fill_if(lambda x, y: 24 <= x < 40 and y >= 16, LIGHT)


def placed(pose, facing, phase):
    src = draw_cat(pose)
    box = Canvas(64, 40, T)
    ox = phase * 2 if pose != "meow" else 0
    for y in range(40):
        for x in range(64):
            sx = x - ox
            if not 0 <= sx < 64:
                continue
            if pose != "meow" and facing:
                sx = 55 - sx                  # mirror the 56 px drawing area
                if not 0 <= sx < 64:
                    continue
            box.put(x, y, src.get(sx, y))
    return box

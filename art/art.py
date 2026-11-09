"""New master cat art for the mockups (1 px, 56x40, facing right).

Colour indices: 0 transparent, 1 body, 2 light (chest/muzzle/paws/tail tip),
3 eye, 4 dark (nose, inner ear, pupil, tabby marks), 5 accent (other cat's
register in the multicolour option: pink-ish nose/inner ear).

Proportions after the CC0 references (refs/SOURCES.md): short muzzle, compact
head with two upright ears, small eye, long thin tail, upright sit, loaf sleep.
"""
import importlib.util
import math
import os

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("gen", os.path.join(HERE, "..", "gen.py"))
gen = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(gen)

Canvas = gen.Canvas
T, BODY, LIGHT, EYE, DARK, ACC = 0, 1, 2, 3, 4, 5
W, H = 56, 40
G = 39            # ground row

POSES = gen.POSES


def leg(cv, x0, y0, x1, y1, r=2.0, paw=True):
    cv.capsule(x0, y0, x1, y1, r, BODY)
    if paw:
        cv.ellipse(x1 + 0.6, y1 - 0.4, r + 0.3, 1.3, LIGHT)


def head(cv, cx, cy, eye="open", ears=True, tilt=0, mouth=False):
    """Side head facing right. cx,cy = skull centre."""
    if ears:
        # far ear (behind), near ear (front); upright, slightly forward
        cv.poly([(cx - 6.5, cy - 2), (cx - 5 + tilt, cy - 11.5), (cx - 0.5, cy - 5)], BODY)
        cv.poly([(cx - 0.5, cy - 5), (cx + 3.5 + tilt, cy - 12), (cx + 6, cy - 3)], BODY)
        cv.poly([(cx + 1.2, cy - 5.5), (cx + 3.4 + tilt, cy - 9.5), (cx + 4.6, cy - 5)], ACC)
    cv.ellipse(cx, cy - 0.5, 6.8, 6.0, BODY)          # skull
    cv.ellipse(cx - 0.5, cy + 2.0, 7.2, 4.3, BODY)    # cheeks
    cv.ellipse(cx + 5.0, cy + 2.6, 3.4, 2.4, BODY)    # short muzzle
    cv.ellipse(cx + 4.6, cy + 3.6, 3.0, 1.8, LIGHT)   # chin / muzzle light
    cv.rect(int(cx + 7), int(cy + 1), int(cx + 9), int(cy + 2), ACC)   # nose
    if mouth:
        cv.rect(int(cx + 5), int(cy + 3), int(cx + 9), int(cy + 6), DARK)
    if eye == "open":
        cv.rect(int(cx + 2), int(cy - 2), int(cx + 5), int(cy + 1), EYE)
        cv.rect(int(cx + 3), int(cy - 2), int(cx + 4), int(cy + 1), DARK)
        cv.eye = (cx + 3.5, cy - 0.5)
    elif eye == "closed":
        cv.rect(int(cx + 2), int(cy), int(cx + 6), int(cy + 1), DARK)
    elif eye == "squint":
        cv.rect(int(cx + 2), int(cy - 1), int(cx + 5), int(cy + 1), DARK)


def tail(cv, pts, r0=2.2, r1=1.4, tip=True):
    cv.curve(pts, r0, r1, BODY, steps=40)
    if tip:
        x, y = pts[-1]
        cv.ellipse(x, y, r1 + 0.4, r1 + 0.4, BODY)


STRIPES = True


def stripes(cv, xs, y0, y1):
    """Tabby marks: short vertical dark dashes on existing body pixels."""
    if not STRIPES:
        return
    for x in xs:
        for y in range(y0, y1):
            if 0 <= x < cv.w and 0 <= y < cv.h and cv.get(x, y) == BODY:
                cv.put(x, y, DARK)


def draw_cat(pose):
    cv = Canvas(W, H, T)
    g = G
    if pose.startswith("run"):
        f = int(pose[3])
        # gallop: 0 extended, 1 front reach, 2 gathered, 3 push off
        bob = [0, -1, -2, -1][f]
        by = 25 + bob
        stretch = [17, 16, 13, 15][f]
        bx = 25
        # tail streams out behind, waving
        tail(cv, [(bx - stretch + 3, by - 2), (bx - stretch - 7, by - 5 + f), (bx - stretch - 9, by - 14 + 2 * f)])
        fl = [((37, by + 3), (50, g - 3)), ((37, by + 3), (44, g)), ((36, by + 3), (33, g)), ((37, by + 3), (40, g))][f]
        bl = [((15, by + 3), (3, g - 2)), ((15, by + 3), (13, g)), ((16, by + 3), (24, g)), ((15, by + 3), (8, g))][f]
        # far legs (behind the body), offset
        leg(cv, bl[0][0] + 3, bl[0][1], bl[1][0] + 4, bl[1][1] - (1 if f in (0, 2) else 0), paw=False)
        leg(cv, fl[0][0] - 2, fl[0][1], fl[1][0] - 4, fl[1][1] - (1 if f in (0, 2) else 0), paw=False)
        # mark far legs darker so they separate (only MC/hires-with-dark uses it)
        cv.ellipse(bx, by, stretch, 6.5, BODY)
        cv.ellipse(bx - stretch + 6, by + 1, 6, 6.2, BODY)        # haunch
        leg(cv, *bl[0], *bl[1], r=2.2)
        leg(cv, *fl[0], *fl[1])
        stripes(cv, [bx - 8, bx - 4, bx], int(by - 6), int(by - 3))
        head(cv, 44 - (2 if f == 2 else 0), 15 + bob)
    elif pose.startswith("sit"):
        f = int(pose[3])
        # tail wraps round the front paws; sit1 = blink + tail flick
        if f == 0:
            tail(cv, [(16, g - 2), (26, g + 1), (40, g - 1)], 2.2, 1.6)
        else:
            tail(cv, [(16, g - 2), (6, g - 1), (5, g - 10)], 2.2, 1.6)
        cv.ellipse(22, g - 8, 11, 8, BODY)                 # haunch
        cv.poly([(16, g - 4), (26, g - 25), (36, g - 22), (37, g - 4)], BODY)   # upright chest
        cv.ellipse(29, g - 20, 7, 6, BODY)                 # shoulders
        cv.ellipse(34, g - 15, 3.5, 6, LIGHT)              # chest bib
        leg(cv, 33, g - 12, 34, g, 2.1)
        leg(cv, 29, g - 12, 30, g, 2.1)
        cv.ellipse(18, g - 3, 4, 2, LIGHT)                 # hind paw
        stripes(cv, [17, 21], g - 14, g - 9)
        head(cv, 33, 12, eye="open" if f == 0 else "closed", tilt=f)
    elif pose == "bat":
        tail(cv, [(14, g - 2), (4, g - 3), (4, g - 13)], 2.2, 1.6)
        cv.ellipse(22, g - 8, 11, 8, BODY)
        cv.poly([(16, g - 4), (26, g - 24), (36, g - 21), (37, g - 4)], BODY)
        cv.ellipse(29, g - 19, 7, 6, BODY)
        leg(cv, 31, g - 12, 32, g, 2.1)
        cv.capsule(34, g - 18, 46, g - 25, 2.1, BODY)       # raised paw
        cv.ellipse(47, g - 25.5, 2.4, 2.0, LIGHT)
        stripes(cv, [17, 21], g - 14, g - 9)
        head(cv, 36, 13, tilt=1)
    elif pose.startswith("sleep"):
        f = int(pose[5])
        breathe = f * 0.7
        cv.ellipse(26, g - 6 - breathe / 2, 17, 6.5 + breathe, BODY)      # loaf
        tail(cv, [(10, g - 2), (20, g + 1), (36, g - 0.5)], 2.2, 1.8)
        cv.ellipse(36, g - 1.4, 3, 1.3, LIGHT)                            # tucked paws
        stripes(cv, [18, 23, 28], int(g - 12 - breathe), int(g - 8))
        head(cv, 42, g - 8, eye="closed", tilt=-1)
    elif pose == "hiss":
        # Halloween cat: high arched back, bottle-brush tail, stiff legs
        tail(cv, [(12, g - 20), (4, g - 26), (7, g - 37)], 3.0, 2.4)
        cv.ellipse(25, g - 20, 14, 7, BODY)
        cv.ellipse(24, g - 25, 10, 6.5, BODY)                              # arch
        leg(cv, 14, g - 17, 12, g, 2.4)
        leg(cv, 18, g - 17, 19, g, 2.4)
        leg(cv, 32, g - 17, 33, g, 2.4)
        leg(cv, 36, g - 17, 39, g, 2.4)
        stripes(cv, [19, 23, 27], g - 30, g - 26)
        head(cv, 42, g - 18, eye="squint", tilt=-3, mouth=True)
    elif pose.startswith("eat"):
        f = int(pose[3])
        d = 2 * f
        tail(cv, [(10, 18), (5, 10), (7, 2)], 2.2, 1.5)
        cv.ellipse(20, 24, 11, 9, BODY)                    # haunches high
        cv.ellipse(31, 26 + d / 2, 9, 6, BODY)
        leg(cv, 14, 28, 13, g, 2.2)
        leg(cv, 22, 28, 22, g, 2.2)
        leg(cv, 33, 29 + d / 2, 34, g, 2.1)
        stripes(cv, [17, 21, 25], 16, 20)
        head(cv, 43, 29 + d, eye="closed")
    elif pose == "jump":
        tail(cv, [(10, 19), (3, 15), (1, 6)], 2.2, 1.5)
        leg(cv, 14, 24, 3, 31, paw=True)
        leg(cv, 37, 22, 51, 15)
        cv.ellipse(26, 20, 17, 6.5, BODY)
        cv.ellipse(38, 23.5, 3.5, 2.4, LIGHT)
        stripes(cv, [18, 22, 26], 14, 17)
        head(cv, 44, 11)
    elif pose == "meow":
        draw_front(cv)
    return cv


def draw_front(cv):
    """Front view, looking at the viewer, mouth open. Centred in the box."""
    g = G
    cx = 28
    # tail curling up on the right side
    tail(cv, [(36, g - 2), (47, g - 3), (46, g - 15)], 2.2, 1.5)
    # body: pear shape, front legs
    cv.ellipse(cx, g - 9, 10, 9, BODY)
    cv.ellipse(cx, g - 14, 7.5, 8, BODY)
    cv.ellipse(cx, g - 12, 4.2, 7, LIGHT)                 # bib
    leg(cv, cx - 3.5, g - 9, cx - 3.5, g, 2.0)
    leg(cv, cx + 3.5, g - 9, cx + 3.5, g, 2.0)
    # head
    hy = 13
    cv.poly([(cx - 9, hy - 1), (cx - 8, hy - 12), (cx - 2, hy - 6)], BODY)
    cv.poly([(cx + 9, hy - 1), (cx + 8, hy - 12), (cx + 2, hy - 6)], BODY)
    cv.poly([(cx - 7.5, hy - 3), (cx - 7, hy - 9.5), (cx - 4, hy - 6)], ACC)
    cv.poly([(cx + 7.5, hy - 3), (cx + 7, hy - 9.5), (cx + 4, hy - 6)], ACC)
    cv.ellipse(cx, hy, 9.5, 7.5, BODY)
    cv.ellipse(cx, hy + 3, 10.5, 4.5, BODY)               # cheeks
    cv.ellipse(cx, hy + 4.5, 4.5, 3.2, LIGHT)             # muzzle
    for ex in (cx - 4.5, cx + 4.5):                       # eyes
        cv.ellipse(ex, hy - 1, 2.2, 2.4, EYE)
        cv.rect(int(ex), int(hy - 3), int(ex + 1), int(hy + 1), DARK)
    cv.rect(cx - 1, hy + 2, cx + 1, hy + 3, ACC)          # nose
    cv.ellipse(cx, hy + 6, 2.2, 1.8, DARK)                # open mouth
    stripes(cv, [cx - 1, cx], hy - 7, hy - 5)


def all_frames(fn_cells):
    """fn_cells(pose, facing, phase) for every frame, in engine order."""
    out = []
    for pose in POSES:
        for facing in (0, 1):
            for ph in range(gen.PHASES):
                out.append(fn_cells(pose, facing, ph))
    return out


def placed(pose, facing, phase):
    """64x40 box canvas with the art shifted by the phase and mirrored."""
    src = draw_cat(pose)
    box = Canvas(64, 40, T)
    ox = phase * 2 if pose != "meow" else 4
    for y in range(src.h):
        for x in range(src.w):
            sx = x if facing == 0 else src.w - 1 - x
            box.put(ox + x, y, src.get(sx, y))
    return box

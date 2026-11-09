"""The title screen and its dub tune, for gen.py: writes title.inc.

Screen: RR64's look - a quad-block logo over raster bars, the name spaced
out, the author and version, a box with the controls, the start prompt, and
the two cats sitting on a strip of floor. The lowercase ROM font is copied
into the RAM charset; codes $80-$ff (reverse video, never shown) become the
cats' cells and the 16 quad blocks of the logo.

Music: a one-drop riddim at 94 bpm on the SFX player's scripts. Voice 1 is
the bass, voice 3 the drums and the offbeat skank, voice 2 the cats: the
game's meows, each followed by two dub echoes, darker (SX_POKE cdark, which
sx_cut subtracts) and quieter (lower sustain). SX_POKE smark tells the title
which cat is meowing so it can show the meow pose.
"""
import os

QUAD0 = 0xf0              # quad block n: bit 0 TL, 1 TR, 2 BL, 3 BR
CATCODE0 = 0x80
FLOOR_ROW = 20
BOX_COL = (3, 29)         # cat boxes
BAR_TOP, BAR_END = 20, 51 + 9 * 8   # raster lines: top border down to the logo's end
FLOOR_LINE = 51 + FLOOR_ROW * 8 - 1
BARS = [6, 14, 3, 15, 3, 14, 6, 4, 2, 10, 8, 7, 8, 10, 2, 9, 11, 12, 5, 13, 5, 12, 11, 0]  # RR64's

GLYPHS = {
    "C": [".#######", "########", "########"] + ["###....."] * 10 + ["########", "########", ".#######"],
    "A": [".######.", "########", "########"] + ["###..###"] * 4 + ["########"] * 3 + ["###..###"] * 6,
    "T": ["########"] * 3 + ["..####.."] * 13,
    "S": [".#######", "########", "########", "###.....", "###.....", "###.....",
          "#######.", "########", ".#######", ".....###", ".....###", ".....###", ".....###",
          "########", "########", "#######."],
    "I": ["###"] * 16,
    "M": ["###....###", "####..####", "##########", "###.##.###", "###.##.###"] + ["###....###"] * 11,
    "6": [".#######", "########", "########", "###.....", "###.....", "###.....",
          "#######.", "########", "########"] + ["###..###"] * 4 + ["########", "########", ".######."],
    "4": ["###..###"] * 8 + ["########"] * 3 + [".....###"] * 5,
    " ": ["...."] * 16,
}


def scl(text):
    """Screen codes for the lowercase ROM font."""
    out = []
    for ch in text:
        o = ord(ch)
        if 97 <= o <= 122:
            out.append(o - 96)
        elif 65 <= o <= 90:
            out.append(o)
        else:
            out.append(o)
    return out


def logo_pixels(word):
    cols = []
    for i, ch in enumerate(word):
        g = GLYPHS[ch]
        for x in range(len(g[0])):
            cols.append([g[y][x] == "#" for y in range(16)])
        if i < len(word) - 1 and ch != " " and word[i + 1] != " ":
            cols.append([False] * 16)
    w = len(cols) + 3
    px = [[False] * w for _ in range(16)]
    for x, col in enumerate(cols):
        for y in range(16):
            if col[y]:
                px[y][x + (15 - y) // 4] = True        # italic, like RR64's logo
    return px


def build(g, cats):
    scr = [32] * 1000
    col = [g.BLACK] * 1000

    def put(x, y, codes, c):
        for i, v in enumerate(codes):
            scr[y * 40 + x + i] = v
            col[y * 40 + x + i] = c

    def centre(y, text, c):
        put((40 - len(text)) // 2, y, scl(text), c)

    # logo, rows 1-8
    px = logo_pixels("CATSIM 64")
    w = (len(px[0]) + 1) // 2
    x0 = (40 - w) // 2
    for cy in range(8):
        for cx in range(w):
            n = 0
            for b, (dx, dy) in enumerate([(0, 0), (1, 0), (0, 1), (1, 1)]):
                x = cx * 2 + dx
                if x < len(px[0]) and px[cy * 2 + dy][x]:
                    n |= 1 << b
            if n:
                scr[(cy + 1) * 40 + x0 + cx] = QUAD0 + n
                col[(cy + 1) * 40 + x0 + cx] = g.WHITE

    version = open(os.path.join(g.HERE, "VERSION")).read().strip()
    centre(10, " ".join("CAT SIMULATOR 64").replace("   ", "   "), g.WHITE)
    centre(11, "by illobo/netmilk   v" + version, g.LGREY)
    # the controls box, rows 13-17
    put(1, 13, [0x70, 0x40] + scl(" How to play ") + [0x40] * 22 + [0x6e], g.LGREY)
    col[13 * 40 + 4:13 * 40 + 15] = [g.WHITE] * 11
    for r in range(14, 17):
        put(1, r, [0x5d], g.LGREY)
        put(38, r, [0x5d], g.LGREY)
    put(1, 17, [0x6d] + [0x40] * 36 + [0x7d], g.LGREY)
    rows = [("Move", "mouse or joystick"),
            ("Play", "left button or fire"),
            ("Nap", "right button or hold fire")]
    for i, (k, v) in enumerate(rows):
        put(4, 14 + i, scl(k), g.WHITE)
        put(11, 14 + i, scl(v), g.GREY)
    centre(18, "Press fire on the joystick in port 2", g.WHITE)
    centre(19, "or a button of the mouse in port 1", g.WHITE)

    # cats: codes from $80 for the cells of sit (right), sit (left), meow
    shapes, chars = {}, []

    def frame(pose, facing):
        cells = cats[(g.POSES.index(pose) * 2 + facing) * g.PHASES]
        out = []
        for idx, pal, rows in cells:
            if rows not in shapes:
                shapes[rows] = CATCODE0 + len(chars)
                chars.append(rows)
            out.append((idx // g.CAT_W * 40 + idx % g.CAT_W, shapes[rows], pal))
        return out

    catcol = [(g.BLACK, g.WHITE), (g.LGREY, g.WHITE)]
    poses = [[frame("sit0", 0), frame("meow", 0)], [frame("sit0", 1), frame("meow", 0)]]
    assert CATCODE0 + len(chars) <= QUAD0, len(chars)
    tframes = []
    for c in range(2):
        for p in range(2):
            codes, cols = [32] * 40, [0] * 40      # the whole box: one pass, no blank frame
            for off, code, pal in poses[c][p]:
                i = off // 40 * g.CAT_W + off % 40
                codes[i], cols[i] = code, catcol[c][pal - 1]
            tframes.append(codes + cols)
            if p == 0:
                for off, code, pal in poses[c][p]:
                    i = FLOOR_ROW * 40 + BOX_COL[c] + off
                    scr[i] = code
                    col[i] = catcol[c][pal - 1]

    charhi = []
    for code in range(0x80, 0x100):
        if code >= QUAD0:
            n = code - QUAD0
            rows = []
            for y in range(8):
                v = (0xf0 if n & (1 << (y // 4 * 2)) else 0) | (0x0f if n & (2 << (y // 4 * 2)) else 0)
                rows.append(v)
        elif code - CATCODE0 < len(chars):
            rows = list(chars[code - CATCODE0])
        else:
            rows = [0] * 8
        charhi += rows

    L = ["; generated by gen.py (title.py) - do not edit", ""]
    L.append("T_BAR_TOP = %d" % BAR_TOP)
    L.append("T_BAR_END = %d" % BAR_END)
    L.append("T_FLOOR_LINE = %d" % FLOOR_LINE)
    L.append("T_PROMPT = %d" % (18 * 40))
    L.append("tboxlo .byte " + ", ".join("<(SCREEN+%d)" % (FLOOR_ROW * 40 + c) for c in BOX_COL))
    L.append("tboxhi .byte " + ", ".join(">(SCREEN+%d)" % (FLOOR_ROW * 40 + c) for c in BOX_COL))
    L.append("tboxoff .byte " + ", ".join(str(r * 40 + c) for r in range(g.CAT_H) for c in range(g.CAT_W)))
    L.append("tfrlo .byte " + ", ".join("<tfr%d" % i for i in range(4)))
    L.append("tfrhi .byte " + ", ".join(">tfr%d" % i for i in range(4)))
    for i, d in enumerate(tframes):
        L.append("tfr%d" % i)
        L += g.byte_lines(d)
    bars = []
    for c in BARS * 3:
        bars += [c] * 3
    L.append("bartab")
    L += g.byte_lines(bars)
    L.append("tscreen")
    L += g.byte_lines(scr)
    L.append("tcolour")
    L += g.byte_lines(col)
    L.append("tcharhi                 ; codes $80-$ff")
    L += g.byte_lines(charhi)
    L += music(g)
    open(os.path.join(g.HERE, "title.inc"), "w").write("\n".join(L) + "\n")
    if "--preview" in __import__("sys").argv:
        preview(g, scr, col, charhi)
    print("title: %d cat chars, logo %d cols" % (len(chars), w))


# ------------------------------------------------------------------ music
SX_END, SX_ADSR, SX_FREQ, SX_CTRL, SX_WAIT, SX_PW = 0, 1, 2, 3, 4, 5
SX_PSLIDE = 7
SX_JUMP, SX_ROUTE = 11, 12
SX_CALL, SX_POKE = 14, 15
STEP = 16                 # frames per 8th note: 94 bpm
BAR = 8 * STEP
BARS_LOOP = 8
MEOW_BODY = 10            # meow scripts: hard restart (7 bytes), ADSR (3), then the body


def freq(note):
    """note: semitones from A4 = 440 Hz"""
    return int(440 * 2 ** (note / 12) * 16777216 / 985248)


NOTE = {"C": -9, "D": -7, "E": -5, "F": -4, "G": -2, "A": 0, "B": 2}


def n(name):
    """'A1', 'C#2', ..."""
    pitch = NOTE[name[0]] + (1 if "#" in name else 0)
    return freq(pitch + (int(name[-1]) - 4) * 12)


class Track:
    def __init__(self, label):
        self.label, self.b, self.t = label, [], 0

    def wait(self, f):
        assert f >= 0
        self.t += f
        while f > 0:                           # SX_WAIT n waits n-1 frames (n > 1)
            k = min(f, 254)
            self.b += [SX_WAIT, k + 1 if k > 1 else 1]
            f -= k

    def skip(self, f):
        """time a called script takes"""
        self.t += f

    def at(self, t):
        self.wait(t - self.t)

    def emit(self, *data):
        self.b += list(data)


def music(g):
    loop = BARS_LOOP * BAR

    # bass: the sleng teng riff in D, a bar of 16ths: C#-D slide, D, D three
    # times, then G, F#. Buzzy narrow pulse. It drops out in bar 7 (dub).
    bass = Track("mbass")
    bass.emit(SX_PW, 0x00, 0x03)
    S16 = STEP // 2
    riff = [("C#2", "D2", 2), ("D2", None, 1), ("D2", None, 1)] * 3 + [("G2", None, 2), ("F#2", None, 2)]

    def bnote(name, to, sixteenths):
        d = sixteenths * S16
        f = n(name)
        bass.emit(SX_ADSR, 0x04, 0xa6, SX_FREQ, f & 255, f >> 8, SX_CTRL, 0x41)
        if to:                                 # slide up over 2 frames
            dl = (n(to) - f + 1) // 2
            bass.emit(SX_PSLIDE, dl & 255, dl >> 8 & 255, 2)
        bass.wait(d - 4)
        bass.emit(SX_CTRL, 0x40)
        bass.wait(3)
        bass.emit(SX_ADSR, 0, 0)               # hard restart
        bass.wait(1)

    for bar in range(BARS_LOOP):
        if bar == 6:
            bass.wait(BAR)
        else:
            for nm, to, l in riff:
                bnote(nm, to, l)
    assert bass.t == loop, bass.t

    # drums: kick on 1 and 3, snare on 2 and 4, hats on the offbeats; a
    # snare roll at the end of the loop
    dr = Track("mdrums")
    dr.emit(SX_PW, 0x00, 0x08)

    def hat(loud):
        dr.emit(SX_ADSR, 0x00, 0x40 if loud else 0x00, SX_FREQ, 0x00, 0xd0, SX_CTRL, 0x81)
        dr.wait(2)
        dr.emit(SX_CTRL, 0x80)
        dr.wait(STEP - 2)

    def kick():
        dr.emit(SX_ADSR, 0x08, 0x00, SX_FREQ, 0x00, 0x12, SX_CTRL, 0x41)
        for hi, w in ((0x09, 1), (0x05, 2), (0x03, 3)):   # pitch drop
            dr.wait(w)
            dr.emit(SX_FREQ, 0x00, hi)
        dr.wait(1)
        dr.emit(SX_CTRL, 0x40)
        dr.wait(STEP - 8)
        dr.emit(SX_ADSR, 0, 0)
        dr.wait(1)

    def snare(f=STEP):
        dr.emit(SX_ADSR, 0x08, 0x00, SX_FREQ, 0x00, 0x0e, SX_CTRL, 0x41)
        dr.wait(1)
        dr.emit(SX_FREQ, 0x00, 0x20, SX_CTRL, 0x81)
        dr.wait(5)
        dr.emit(SX_CTRL, 0x80)
        dr.wait(f - 7)
        dr.emit(SX_ADSR, 0, 0)
        dr.wait(1)

    for bar in range(BARS_LOOP):
        for s in range(8):
            if s in (0, 4):
                kick()
            elif s in (2, 6):
                snare()
            elif bar == BARS_LOOP - 1 and s == 7:
                snare(S16)
                snare(S16)
            else:
                hat(s in (3, 7))
    assert dr.t == loop, dr.t

    # the cats: (bar, 8th, cat, kind); echoes every 3 8ths, darker and quieter
    me = Track("mmeow")
    events = [(0, 1, 0, 1), (2, 1, 1, 3), (4, 1, 0, 2), (6, 1, 1, 0), (6, 6, 0, 0)]
    for bar, s, c, k in events:
        frames = g.MEOW_KINDS[k][0]            # the body: a frame per pitch step
        label = "meow%d" % (c * 4 + k)
        t0 = bar * BAR + s * STEP
        me.at(t0)
        me.emit(SX_POKE, 0x22, c, SX_CALL, "<" + label, ">" + label, SX_POKE, 0x22, 0xff)
        me.skip(frames + 1)                    # the meow's hard restart frame + body
        gap = 3 * STEP if frames < 3 * STEP else 4 * STEP
        for echo, (sr, dark) in enumerate([(0x69, 0x20), (0x39, 0x38)]):
            if bar == 6 and s == 1 and echo:
                break                          # the orange cat answers
            me.at(t0 + (echo + 1) * gap)
            me.emit(SX_CTRL, 0, SX_ADSR, 0, 0)
            me.wait(1)
            me.emit(SX_ADSR, 0x00, sr, SX_POKE, 0x21, dark,
                    SX_CALL, "<(%s+%d)" % (label, MEOW_BODY), ">(%s+%d)" % (label, MEOW_BODY),
                    SX_POKE, 0x21, 0)
            me.skip(frames)
    me.at(loop)
    out = ["; music: voice scripts for the SFX player"]
    for tr in (bass, me, dr):
        out.append(tr.label)
        b = tr.b
        for i in range(0, len(b), 16):
            out.append("        .byte " + ",".join(v if isinstance(v, str) else "$%02x" % v for v in b[i:i + 16]))
        out.append("        .byte %d, <%s, >%s" % (SX_JUMP, tr.label, tr.label))
    out.append("mtrklo .byte <mbass, <mmeow, <mdrums")
    out.append("mtrkhi .byte >mbass, >mmeow, >mdrums")
    return out


def preview(g, scr, col, charhi):
    from PIL import Image
    img = Image.new("RGB", (320, 200))
    lower = g.CHARGEN[0x800:0x1000]
    for i in range(1000):
        code = scr[i]
        rows = charhi[(code - 0x80) * 8:(code - 0x80) * 8 + 8] if code >= 0x80 else lower[code * 8:code * 8 + 8]
        r, cc = divmod(i, 40)
        y0 = 51 + r * 8
        for y in range(8):
            line = y0 + y
            if r >= FLOOR_ROW:
                bg = g.FLOOR_BG
            elif BAR_TOP <= line < BAR_END:
                bg = BARS[((line - BAR_TOP) // 3) % len(BARS)]
            else:
                bg = 0
            for x in range(8):
                v = g.PAL[col[i] if rows[y] >> (7 - x) & 1 else bg]
                img.putpixel((cc * 8 + x, r * 8 + y), (v >> 16, v >> 8 & 255, v & 255))
    img = img.resize((640, 400), Image.NEAREST)
    img.save(os.path.join(g.HERE, "title_preview.png"))

#!/usr/bin/env python3
"""Directory art for the Cat Simulator 64 release disk.

    python3 mkdisk.py catsim64.d64 [VERSION]

Takes a D64 that c1541 has just formatted and written the game to, keeps the
game as the first directory entry (so LOAD"*",8,1 and LOAD"CATSIM64",8,1 still
work) and appends zero-block DEL entries that draw a small PETSCII frame with
a cat, the version (argument, or the VERSION file) and the credits when the
directory is listed (upper case / graphics character set, as after power-on).

The art needs a second directory sector (18/4), which is allocated in the
BAM. The DEL entries point at the directory itself (18/1), so a validate
("V" command, c1541 -validate) follows a valid chain and leaves them and the
BAM alone. Plain Python 3, no dependencies; running it twice is harmless.
"""
import sys

DIR_TRACK, BAM_SECTOR, DIR1, DIR2 = 18, 0, 1, 4
WIDTH = 16                      # a CBM file name
YEAR = "2026"
CREDITS = "ILLOBO/NETMILK"

# Shifted PETSCII graphics (as listed in the upper case / graphics set)
G = {
    "╭": 0xD5, "╮": 0xC9, "╰": 0xCA, "╯": 0xCB,     # round corners
    "─": 0xC0, "│": 0xDD, "├": 0xAB, "┤": 0xB3,     # lines and tees
    "╱": 0xCE, "╲": 0xCD, "_": 0xA4,                # ears, top of the head
    "●": 0xD1, "♥": 0xD3,                           # eyes, nose
}


def art(version):
    def row(text):
        return "│" + text.center(WIDTH - 2)[:WIDTH - 2] + "│"
    bar = "─" * (WIDTH - 2)
    return [
        "╭" + bar + "╮",
        "│  ╱╲_╱╲       │",
        "│ ( ●.● ) MEOW │",
        "│  > ♥ <       │",
        "├" + bar + "┤",
        row("V%s  %s" % (version, YEAR)),
        row(CREDITS),
        "╰" + bar + "╯",
    ]


def petscii(line):
    out = bytes(G[c] if c in G else ord(c) for c in line)
    # $a0 pads (and so ends) a name; anything else below is plain PETSCII
    assert len(out) == WIDTH and 0xA0 not in out, line
    return out


def offset(track, sector):
    """Byte offset of a sector in a 35-track D64."""
    blocks = 0
    for t in range(1, track):
        blocks += 21 if t < 18 else 19 if t < 25 else 18 if t < 31 else 17
    return (blocks + sector) * 256


def allocate(img, track, sector):
    """Mark a sector as used in the BAM (no-op if it already is)."""
    e = offset(DIR_TRACK, BAM_SECTOR) + 4 * track
    byte, bit = e + 1 + sector // 8, 1 << (sector % 8)
    if img[byte] & bit:
        img[byte] &= ~bit & 0xFF
        img[e] -= 1


def main():
    if len(sys.argv) not in (2, 3):
        sys.exit(__doc__)
    path = sys.argv[1]
    version = sys.argv[2] if len(sys.argv) > 2 else open("VERSION").read()
    version = version.strip().upper()
    if len(version) > WIDTH - 2 - len("V  " + YEAR):
        sys.exit("mkdisk: version '%s' does not fit in the frame" % version)

    img = bytearray(open(path, "rb").read())
    if len(img) < 174848:
        sys.exit("mkdisk: %s is not a D64 image" % path)

    d1, d2 = offset(DIR_TRACK, DIR1), offset(DIR_TRACK, DIR2)
    game = bytes(img[d1 + 2:d1 + 32])           # first entry: the game
    if game[0] != 0x82 or (img[d1], img[d1 + 1]) not in ((0, 0xFF), (DIR_TRACK, DIR2)):
        sys.exit("mkdisk: expected a fresh disk with one PRG as its first entry")

    entries = [game]
    for line in art(version):
        e = bytearray(30)
        e[0] = 0x80                             # DEL, closed
        e[1], e[2] = DIR_TRACK, DIR1            # a valid chain for validate
        e[3:19] = petscii(line)
        entries.append(bytes(e))                # 0 blocks
    assert len(entries) <= 16

    for base, chunk, link in ((d1, entries[:8], (DIR_TRACK, DIR2)),
                              (d2, entries[8:], (0, 0xFF))):
        img[base:base + 256] = bytes(256)
        for i, e in enumerate(chunk):
            img[base + 32 * i + 2:base + 32 * i + 32] = e
        img[base], img[base + 1] = link
    allocate(img, DIR_TRACK, DIR2)

    open(path, "wb").write(img)


if __name__ == "__main__":
    main()

# Cat Simulator 64

A Commodore 64 game by illobo/netmilk. Two cats live in an 80s living room
with a ball of yarn, a couch, a food bowl and a computer on the desk. You are
the black tabby with white socks; the grey cat has a mind of its own. Next
door is the piano room, with its own grey cat, a sofa, a plant and a blue
ball of yarn.

- 1351 mouse in port 1, or joystick in port 2.
- Left button / fire: grab, toss or steal the ball, boop the other cat, eat,
  paw the empty bowl, hop onto the couch, the sofa or the piano (walking on
  the keys plays it), scratch the plant or the sofa's arm, or meow.
- Up + button: leap from the couch to the desk (mind the lamp), over the
  plant, or over the sofa's arm. A cat on the desk upsets the computer.
- Next room: keep going right on the desk; go left through the door to come
  back. F1 switches room from anywhere.
- Right button / hold fire: nap. Move or click to wake up.
- Title screen with raster bars and a dub tune sung by the cats.

Runs on a PAL C64, C64 Ultimate or Ultimate 64. See `README.TXT` for the
player's notes.

Website and download: https://illobo.github.io/catsim64/ (from `docs/`).
MIT licence (`LICENSE`).

## Build

| Command | Needs | Makes |
|---|---|---|
| `make` | [64tass](https://sourceforge.net/projects/tass64/) | `catsim.prg` |
| `make gen` | Python 3, the C64 character ROM | the `.inc` files from `gen.py`, `title.py`, `art/` |
| `make release` | exomizer, c1541 (VICE) | `release/catsim64-<VERSION>/` (crunched PRG, D64, README.TXT) and a zip |

The generated `.inc` files are included, so `make` alone builds the game.
`make gen` looks for the character ROM (not included: it is Commodore's) in
VICE's data directory, or takes `CHARGEN=/path/to/chargen`.
`python3 gen.py --preview` also writes PNG previews (needs Pillow).

## Files

- `catsim.asm`: the AI cat, the ball, the monitor, the sound player, the cat
  drawing engine (hi-res frames in RAM chars, redefined when they change)
- `player.asm`: mouse and joystick input, the player's cat
- `rooms.asm`: the packed rooms and switching between them, furniture to
  stand on, leaps, the lamp, scratching, the piano
- `title.asm`: the title screen and the music loop
- `gen.py`: the living room, cat frames, sprites, meows (`catsim.inc`,
  `catspr.inc`, `catleft.inc`); `room2.py`: the piano room; `title.py`: the
  title screen and the tune (`title.inc`)
- `mkdisk.py`: the directory art on the release disk
- `art/`: the pixel-art cats

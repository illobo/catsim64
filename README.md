# Cat Simulator 64

A Commodore 64 game by illobo/netmilk. Two cats live in an 80s living room
with a ball of yarn, a couch, a food bowl and a computer on the desk. You are
the black tabby with white socks; the grey cat has a mind of its own.

- 1351 mouse in port 1, or joystick in port 2.
- Left button / fire: grab, toss or steal the ball, boop the other cat, eat,
  paw the empty bowl, jump onto the couch, or meow.
- Right button / hold fire: nap. Move or click to wake up.
- Title screen with a dub tune sung by the cats.

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

- `catsim.asm`: the room, the AI cat, the ball, the sound player, the cat
  drawing engine (hi-res frames in RAM chars, redefined when they change)
- `player.asm`: mouse and joystick input, the player's cat
- `title.asm`: the title screen and the music loop
- `gen.py`: the room, cat frames, sprites, meows (`catsim.inc`, `catspr.inc`,
  `catleft.inc`); `title.py`: the title screen and the tune (`title.inc`)
- `art/`: the pixel-art cats

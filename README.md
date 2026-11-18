# 80-Force

80-Force is an overhead space shooter for the stock MAX-80. MIT
license, in `LICENSE`. A boot disk with no
OS. A title screen with the high scores, then a stage scrolling at 30
game updates a second, a ship to fly, saucers and bombers in waves, a
mothership after the tenth, explosions, a beeper rhythm for each event,
score, ships, and the initials of a new high score.

## Playing it

- The title shows the logo, the five high scores and PRESS SPACE TO
  PLAY; SPACE starts. The ground holds still on it. The scores are in
  RAM and start again at every boot.
- Arrows, or W A S D: fly the ship in the lower part of the playfield.
  The arrows and SPACE are all in matrix row 6, so no three of them
  held together can read as a fourth key.
- SPACE: fire. A shot every 6 updates while it is held, 4 in flight.
- Saucers come in waves, 10 in turn and round again (`WAVES` in
  `src/game.asm`), up to 4 on the screen: drifters that swing side to
  side (100 points), columns that drop straight down (100), swingers
  that follow a sine (150), divers that steer at the ship (200) and
  bombers that drift and drop round bullets when over the ship (300),
  2 bullets at most. A wave starts 1.5 seconds after the last one's
  saucers have all gone.
- After the tenth wave, the mothership: 32 x 25 dots, four sprites. It
  comes down, patrols side to side and drops bullets, takes 24 hits,
  50 points each, blinking at each, and explodes in four for 5000
  points and 1000 for each ship left. That wins the game: MISSION
  COMPLETE across the playfield in letters twice the size, 4 rows of
  the middle, for 4 seconds while the ground holds still, then the high
  scores. Its 27 glyphs take the top of the sprite pool meanwhile.
- A shot that touches a saucer goes and the saucer explodes, 3 frames,
  and scores. A saucer or a bullet that touches the ship costs one of
  its 3 ships; the saucer explodes, and the ship blinks for 3 seconds
  and cannot be hit. With none left the ship explodes and the game is
  over: GAME OVER shows for 2 seconds. Once the game is over, lost or
  won, nothing hits anything: shots still climbing score nothing, and
  bullets still falling cost no ship. Each thing is hit on its own
  dots' box, a bomber on its shorter one. A score that makes the table
  goes to NEW HIGH SCORE: UP and DOWN change the letter, A to Z, SPACE
  or RIGHT keeps it, three letters. Then the title.
- The beeper has one tone, so each event has a rhythm: one beep for a
  saucer shot down, three for a ship lost, five for the game's end.
- The stage, 128 rows of the map: open space, an asteroid belt, space,
  a planet's surface with craters, space again, and round. It is the
  same every game, made by `tools/gfx.py` from a fixed seed.
- The waves come in the same order, but drifters and divers enter at
  random places across, and drifters swing off either way. Each time
  the keys held change, the frame count is mixed into the random seed,
  so the player's own timing makes every game different. The
  self-playing test builds always press the same keys at the same
  time, so their games repeat.

Under the playfield, one row of 80-column text:

```
80-FORCE  SCORE 003800  SHIPS 2  WAVE 009    FREE A 110 B 071 C 043
```

FREE is the fewest picture lines left in the last second in frames A
and B and in the copy window C (below). Channel A sends the counts
every 2 seconds at 9600, 8N1, as
`N 006 U 043 A 069 B 040 C 041 H 024 O 0 S 003400`: objects drawn,
cells, the three FREE counts, saucers hit, the game over, the score.

## The budget

`tools/cost.c` times 2000 updates, four times round the map, of the
`-DSTRESS` build, which keeps every shot and saucer slot full and makes
every collision test, and of the self-playing build, on the emulator's
Z80 core with no video stretch. The most:

| Objects | Frame A | Frame B | Copy window |
| --- | --- | --- | --- |
| Ship, 4 shots, 4 saucers, 2 bullets | 161 lines | 146 lines | 43 lines |
| Ship, 4 shots, 5 saucers, 1 bullet | 169 lines, over | 157 lines | 47 lines |

Frames A and B have about 172 picture lines for work and `test.sh`
wants 8 of them spare; the copy window has 75. The draw list (saucers,
the ship, then the shots) is split between the frames by each object's
cost, read from `COSTTAB` by its image, shift and line in the row (7
units of about 100 T, and 5 a row and 5 a cell), with each frame's own
work counted (`FIXA`, `FIXB` in `src/game.asm`). A new saucer only
enters while both frames had at least 16 lines to spare in the last
update, so a slower machine shows fewer instead of breaking the
picture.

## How it works

Two CRTC frames make each monitor frame of 264 lines, by rupture:

- P, the playfield: row 0 is L lines tall (R9 = L - 1, L 1 to 8), its
  24 glyphs the bottom L lines of the tiles above row 1, rewritten each
  update. Then 22 rows of 8 lines, then 10 - L blank adjust lines, 186
  lines in all, so at least 2 blank lines come before the score row:
  time to see the gap and turn 40 columns off before its first line. R9 goes back to 7 on line L. As L counts up the ground
  moves down a line. Past 8 the start address moves up a row, 80
  bytes, in video RAM's 2K ring, as Lobo's BIOS scrolls.
- S, the score row: 80 columns, one row shown, the vsync at its row 6,
  line 234 as Lobo's, 78 lines. The score row sits at the start
  address + 1920 and is copied ahead of each row move. The new row 0
  goes where the old score row was, so the copy window waits for the
  score row to be drawn before it writes it.

A game update takes two frames. In frame A's picture the ground moves,
the game moves (`src/game.asm`) and builds the draw list, and frame A's
share of it is merged. In frame B's picture the rest is merged and row
0's glyphs are made. Merging an object
makes a glyph in RAM for each cell it touches: the tile under it, its
outline cleared, its dots set, from copies pre-shifted 0 to 7 dots,
over as many cells as its width and height cover. A cell two objects
touch shares one glyph. The glyphs are 112 slots,
codes 30h-7Fh and A0h-BFh, taken from opposite ends of the pool in
turn, so most of a new update's slots are not on the screen and go
into font RAM during frame B. In the copy window, from S's first line
to P's next, the update goes on the screen at once: the old cells get
their tiles back, a row move writes its two rows, the new cells get
their codes, the slots still on show and row 0's glyphs are copied.
Interrupts stay off. Every CRTC write is at a counted line, as in the
demo.

Time left is counted by polling the display enable until the gap after
each frame: picture lines in A and B, and in the copy window the lines
until P starts.

## Build and run

The emulator is lobo_max80's. `test.sh`, which also needs gcc, and the commands below take
it from a lobo_max80 checkout beside this repo, or from where `MAX80`
points, with `make` run in its `emu/`. The build reads `font.bin`,
xcpmz80's 8 x 8 font, or the file `FONT` names.

`sh build.sh` needs Python 3 and sjasmplus:

- `build/proto.imd`: the game, 8-inch, `../lobo_max80/emu/max80 -B -a
  build/proto.imd`. In the emulator's window the keys are held as on
  the machine.
- `build/proto_525.imd`: 5.25-inch, add `-D 1`.
- `build/play.imd`: `-DAUTOPLAY`, the game playing itself from the key
  script in `src/game.asm`, the same every run.
- `build/die.imd`: `-DAUTOPLAY -DDIE`, one ship that never moves but
  fires, and a low table, so the game ends, its initials are typed
  (CPU) and the title comes back.
- `build/boss.imd`: `-DAUTOPLAY -DBOSSFIRST`, the mothership first,
  shot down. `build/bosslose.imd`: with `-DDIE` too, one ship that
  loses to it and types its initials.
- `build/stress.sys`: `-DSTRESS`, every slot full, for `tools/cost.c`.

The emulator needs `-B` to show the two frames. `sh test.sh` builds,
checks that the stress and self-playing builds fit over 2000 updates
with `tools/cost.c`, checks what hits what with `tools/hits.c`,
checks row 0 and every
playfield dot of 512 self-played updates with `tools/screens.c` and
`tools/checkscreens.py`, runs the self-playing disk in the emulator at
`-V 0`, 2 and 5 (a video access 1 to 1, 3 or 6 T, the measured
1.02 T included) for 40 seconds and checks that channel A reports
saucers shot down with lines to spare and that two frames pass
`tools/checkframe.py`, counts at least a beep for each saucer shot
down, runs the one-ship disk until the game ends and
starts again, checks that the score row's title survives a row move
over 20 frames in a row, and boots both game disks.

## On a real MAX-80

Boot the disk with the DIP switches at 2 for 8-inch, 1 for 5.25-inch,
and play.

## Files

- `LICENSE`: MIT.
- `build.sh`, `test.sh`: build, and test in the emulator.
- `src/proto.asm`: the program: the frames, the scroll, the merge and
  the copy window. `src/title.asm` the title, the high scores and their
  initials, and the job that draws a page or the map back into the
  playfield a few rows a copy window. The images, map and tables from `build/gfx.inc` are
  assembled for 9000h in A2 and follow the program on the disk, and
  the boot sector loads them there. `src/game.asm` the game: keys, ship, shots, saucers,
  collisions and the draw list. `src/boot.asm` the boot sector, the
  demo's loader. `src/hw.inc` the addresses, the I/O block at 7000h.
- `font.bin`: xcpmz80's 8 x 8 font, for the score row and the title.
- `tools/gfx.py`: the tiles, the test map, the ship, saucer and shot
  pre-shifted with their sizes, and the score row's glyphs from
  xcpmz80's font. The tiles, map and sprites are our own.
- `tools/mkdisk.py`: the disks.
- `tools/cost.c`: times the work of each update of the stress build on
  `emu/z80.c`.
- `tools/hits.c`: places the ship, shots, saucers, a bomber, a bullet
  and the mothership by hand and runs the game's `hit` on `emu/z80.c`:
  each box one dot in and one dot out, nothing hit after GAME OVER or
  MISSION COMPLETE, and no ship bonus counted from 0 ships.
- `tools/screens.c`: runs the updates on `emu/z80.c` with video and
  font RAM banked as on the machine and saves each screen.
  `tools/checkscreens.py` draws the map and the draw list itself and
  checks every playfield dot of each against them.
- `tools/checkframe.py`: checks two frames from the emulator.
  `tools/countbeeps.py` counts the beeps in a sound the emulator
  recorded with `-s`. `tools/checkmenu.py` draws the title's page and
  checks every dot of it in a frame.
  `tools/checktitle.py` checks that the score row's title stays the
  same over frames in a row.

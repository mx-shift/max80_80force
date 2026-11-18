#!/usr/bin/env python3
"""Make the 80-Force prototype's graphics and map.

Usage: gfx.py FONT.bin OUT.inc

Writes sjasmplus source with:

- TILEGFX: 16 ground tiles, 8 bytes each, tile 0 blank. Codes 00h-0Fh
  in font RAM 1 are these tiles.
- MAP: MAPROWS rows of 24 tile codes, the stage (make_map), then rows
  0 and 1 again. SINT: a sine for the saucers that swing. MAPROW, page aligned:
  the address of each row.
- IMG0, IMG1, IMG2: the ship, a saucer and a shot, pre-shifted 0 to 7
  dots right. For shift s, column c (0-2) and line l (0-15) the bytes
  at s * 96 + c * 32 + l * 2 are the AND mask (the sprite's outline
  cleared) and the dots. IMGTAB: the address of each image and shift.
  IMGINFO: each image's width in glyph dots and height in lines, its
  outline included. OBJTAB, page aligned: for each image and shift,
  the image's address at that shift, the cells across it covers and its
  height, 4 bytes, for the merge, 2 pages. COSTTAB, 2 pages, and
  CELLTAB 2 pages on: the draw list's cost of each image at each shift
  and pair of lines in its row, and the cells it covers.
- LOGOGFX: the title's logo glyphs, NLOGO of them, codes 30h on while
  the title shows. LOGO: "80-FORCE", 4 rows of 24 of those codes, each
  font dot 3 glyph dots across and 4 lines down.
- BANGFX: the MISSION COMPLETE banner's glyphs, NBAN of them, codes
  0C0h - NBAN on, the top sprite slots, given up while it shows.
  BANNER: 4 rows of 24 codes, MISSION and COMPLETE each font dot 2
  glyph dots across and 2 lines down.
- TEXTGFX: the text's glyphs from FONT.bin (xcpmz80's 8 x 8 font),
  the first 32 for codes 80h on in font RAM 2, the rest for codes
  TEXT2 on in font RAM 1. ASC2CODE: ASCII 20h-5Fh to those codes, a
  missing character as a space.

The tiles, the map and the sprites are our own.
"""
import random
import sys

COLS = 24
MAPROWS = 128
# The text: the first 32 are codes 80h-9Fh in font RAM 2, the rest
# codes 20h on in font RAM 1, which the game does not otherwise use
TEXT = ' 0123456789-ABCDEFGHIJKLMNOPQRSTUVWXYZ'
TEXT2 = 0x20

# 8 x 8 tiles, '#' a dot. Tile 0 is blank.
TILES = [
    ['........'] * 8,
    # 1-3: stars
    ['........', '........', '........', '....#...',
     '........', '........', '........', '........'],
    ['........', '........', '...#....', '..###...',
     '...#....', '........', '........', '........'],
    ['........', '.#...#..', '..#.#...', '...#....',
     '..#.#...', '.#...#..', '........', '........'],
    # 4: the planet's top edge, a horizon with dither under it
    ['........', '........', '........', '###.####',
     '########', '.#.#.#.#', '#.#.#.#.', '.#.#.#.#'],
    # 5: surface, dither
    ['#.#.#.#.', '.#.#.#.#', '#.#.#.#.', '.#.#.#.#',
     '#.#.#.#.', '.#.#.#.#', '#.#.#.#.', '.#.#.#.#'],
    # 6: surface, sparse
    ['#...#...', '........', '..#...#.', '........',
     '#...#...', '........', '..#...#.', '........'],
    # 7-10: a crater, 2 x 2 tiles
    ['#.#..###', '.#.##...', '#.#.....', '.#.#....',
     '#.#.....', '.##.....', '#.#.....', '.#.#....'],
    ['###..#.#', '...##.#.', '.....#.#', '....#.#.',
     '.....#.#', '.....##.', '.....#.#', '....#.#.'],
    ['#.#.....', '.#.#....', '#.#.....', '.#.#....',
     '#.#.#...', '.#.#.##.', '#.#.#.##', '.#.#.#.#'],
    ['.....#.#', '....#.#.', '.....#.#', '....#.#.',
     '...#.#.#', '.##.#.#.', '##.#.#.#', '#.#.#.#.'],
    # 11: rocks
    ['#.#.#.#.', '.###.#.#', '#####.#.', '.###.#.#',
     '#.#.###.', '.#.#####', '#.#.###.', '.#.#.#.#'],
    # 12: a small rock, grey with a bright rim, wider than tall on the
    # screen (a glyph dot is 2 dots wide)
    ['........', '..####..', '.#.#.##.', '#.#.#.##',
     '##.#.#.#', '.#.#.##.', '..###...', '........'],
    # 13: the planet's bottom edge
    ['#.#.#.#.', '.#.#.#.#', '#.#.#.#.', '########',
     '###.####', '........', '........', '........'],
    # 14, 15: a big rock's left and right halves, the same grey and rim
    ['....####', '..##.#.#', '.#.#.#.#', '##.#.##.',
     '#.#.#.#.', '.#.#.#.#', '..###.#.', '....####'],
    ['####....', '.#.###..', '#.#.##..', '#.#.#.##',
     '.#.#.###', '#.#.###.', '#.####..', '###.....'],
]

# 16 x 16 sprites, our own. A ship pointing up and a saucer.
SHIP = [
    '.......##.......',
    '.......##.......',
    '......####......',
    '......####......',
    '.....##..##.....',
    '.....######.....',
    '....########....',
    '#...##.##.##...#',
    '#..##########..#',
    '#.############.#',
    '################',
    '###.########.###',
    '##...######...##',
    '#.....####.....#',
    '......#..#......',
    '.....##..##.....',
]
# A shot: 2 dots wide, 6 lines, its outline 4 x 8
SHOT = [
    '................',
    '.##.............',
    '.##.............',
    '.##.............',
    '.##.............',
    '.##.............',
    '.##.............',
    '................',
] + ['................'] * 8
SAUCER = [
    '................',
    '................',
    '......####......',
    '.....######.....',
    '....##.##.##....',
    '....########....',
    '..############..',
    '.##.##.##.##.##.',
    '################',
    '.##############.',
    '...##########...',
    '....##....##....',
    '...##......##...',
    '................',
    '................',
    '................',
]


def size(rows):
    """Width and height of the image with its outline: the merge does
    the cells these cover, from the top left."""
    m = outline(bits(rows))
    w = max((16 - ((v & -v).bit_length() - 1) for v in m if v), default=0)
    h = max((y + 1 for y, v in enumerate(m) if v), default=0)
    return w, h


def bits(rows):
    return [int(r.replace('#', '1').replace('.', '0'), 2) for r in rows]


def outline(rows16):
    """The sprite's dots and every dot next to one: the mask, so a
    sprite has a dark rim over the ground."""
    m = []
    for y in range(16):
        v = 0
        for dy in (-1, 0, 1):
            if 0 <= y + dy < 16:
                r = rows16[y + dy]
                v |= r | (r << 1) | (r >> 1)
        m.append(v & 0xFFFF)
    return m


def shifted(rows):
    d = bits(rows)
    m = outline(d)
    out = []
    for s in range(8):
        for c in range(3):
            for l in range(16):
                dv = (d[l] << 8) >> s
                mv = (m[l] << 8) >> s
                sh = 16 - 8 * c
                out.append(~(mv >> sh) & 0xFF)
                out.append((dv >> sh) & 0xFF)
    return out


# Three frames of an explosion, a bomber and an enemy bullet
EXPL1 = [
    '................',
    '................',
    '................',
    '................',
    '.......##.......',
    '.....#.##.#.....',
    '......####......',
    '....########....',
    '......####......',
    '.....#.##.#.....',
    '.......##.......',
] + ['................'] * 5
EXPL2 = [
    '................',
    '...#...#...#....',
    '....#..#..#.....',
    '.....#.#.#......',
    '..#...###...#...',
    '...#.##.##.#....',
    '.######.######..',
    '...#.##.##.#....',
    '..#...###...#...',
    '.....#.#.#......',
    '....#..#..#.....',
    '...#...#...#....',
] + ['................'] * 4
EXPL3 = [
    '.#.....#.....#..',
    '................',
    '...#.........#..',
    '#.......#.......',
    '.....#......#...',
    '..#.........#...',
    '#..............#',
    '..........#.....',
    '...#..#.........',
    '.#..........#...',
    '.....#...#......',
    '#..#..........#.',
] + ['................'] * 4
BOMBER = [
    '................',
    '.####......####.',
    '##..##....##..##',
    '################',
    '.##.########.##.',
    '..############..',
    '....##.##.##....',
    '.......##.......',
    '.......##.......',
] + ['................'] * 7
EBULLET = [
    '................',
    '..#.............',
    '.###............',
    '..#.............',
] + ['................'] * 12

# The mothership, the final boss: 32 x 28, drawn as four 16-dot sprites,
# its left half as written and its right half the mirror
BOSSL = [
    '..........######',
    '.......#########',
    '.....###.#.#.#.#',
    '....####.#.#.#.#',
    '...#############',
    '..##..##########',
    '.###..###....###',
    '####..###.##.###',
    '##########....##',
    '################',
    '#.#.#.#.#.#.#.##',
    '################',
    '.###....########',
    '..##....###.....',
    '...##..###......',
    '....######......',
    '.....##.##..####',
    '....##...##.#..#',
    '...##.....######',
    '..##.........##.',
    '.##.........##..',
    '##..........#...',
    '#...........#...',
    '............#...',
]
BOSSR = [r[::-1] for r in BOSSL]
BOSS_TL, BOSS_TR = BOSSL[:16], BOSSR[:16]
BOSS_BL = BOSSL[16:] + ['................'] * 8
BOSS_BR = BOSSR[16:] + ['................'] * 8

IMAGES = [SHIP, SAUCER, SHOT, EXPL1, EXPL2, EXPL3, BOMBER, EBULLET,
          BOSS_TL, BOSS_TR, BOSS_BL, BOSS_BR]


def logo(font, word='80-FORCE'):
    """WORD in the font, each dot 3 glyph dots across and 4 lines down,
    so 8 letters fill the 24 cells: 4 rows of 24 cells. Returns the
    rows of codes, each cell's glyph its own from 30h, blank cells 0, and
    the glyphs, 8 bytes each."""
    bm = [[0] * 192 for _ in range(32)]
    for i, ch in enumerate(word):
        g = font[ord(ch) * 8:ord(ch) * 8 + 8]
        for y in range(8):
            for x in range(8):
                if g[y] >> (7 - x) & 1:
                    for dy in range(4):
                        for dx in range(3):
                            bm[4 * y + dy][24 * i + 3 * x + dx] = 1
    codes, glyphs = [], {}
    for r in range(4):
        row = []
        for c in range(24):
            gl = bytes(int(''.join(str(bm[8 * r + j][8 * c + b]) for b in range(8)), 2)
                       for j in range(8))
            if not any(gl):
                row.append(0)
                continue
            if gl not in glyphs:
                glyphs[gl] = 0x30 + len(glyphs)
            row.append(glyphs[gl])
        codes.append(row)
    return codes, sorted(glyphs, key=glyphs.get)


BANROWS = 4


def banner(font, lines=('MISSION', 'COMPLETE')):
    """LINES in the font, each dot 2 glyph dots across and 2 lines down,
    so a letter is 2 cells by 2 rows, centred in 24 cells: BANROWS rows
    of codes, blank cells 0, and the
    glyphs, 8 bytes each, their codes from 0C0h less their number."""
    bm = [[0] * 192 for _ in range(8 * BANROWS)]
    for n, word in enumerate(lines):
        x0 = 8 * ((COLS - 2 * len(word)) // 2)
        for i, ch in enumerate(word):
            g = font[ord(ch) * 8:ord(ch) * 8 + 8]
            for y in range(16):
                for x in range(16):
                    if g[y // 2] >> (7 - x // 2) & 1:
                        bm[16 * n + y][x0 + 16 * i + x] = 1
    cells, glyphs = [], {}
    for r in range(BANROWS):
        row = []
        for c in range(COLS):
            gl = bytes(int(''.join(str(bm[8 * r + j][8 * c + b]) for b in range(8)), 2)
                       for j in range(8))
            if not any(gl):
                row.append(None)
                continue
            glyphs.setdefault(gl, len(glyphs))
            row.append(glyphs[gl])
        cells.append(row)
    base = 0xC0 - len(glyphs)
    codes = [[0 if g is None else base + g for g in row] for row in cells]
    return codes, sorted(glyphs, key=glyphs.get)


def stars(rnd, row):
    for c in range(COLS):
        x = rnd.random()
        row[c] = 3 if x < 0.02 else 2 if x < 0.05 else 1 if x < 0.11 else 0


def make_map():
    """The stage, MAPROWS rows. Built in the order it is flown, then
    turned over: the ship flies toward the map's lower rows, so the
    screen's top shows the rows ahead. 0-23 open space, 24-51 an
    asteroid belt, 52-56 space, 57-94 a planet's surface with craters,
    95-127 space again, and round to the start."""
    rnd = random.Random(80)
    flight = []
    for r in range(MAPROWS):
        row = [0] * COLS
        stars(rnd, row)
        flight.append(row)
    for r in range(24, 52):                     # the asteroid belt:
        c = 0                                   # big rocks, 2 tiles wide,
        while c < COLS:                         # and small ones
            x = rnd.random()
            dense = 0.06 + 0.04 * (r - 24 < 14)
            if x < dense and c + 1 < COLS:
                flight[r][c], flight[r][c + 1] = 14, 15
                c += 2
                continue
            if x < 2 * dense:
                flight[r][c] = 12
            c += 1
    top, bottom = 57, 94                        # the planet, top edge first
    for c in range(COLS):
        flight[top][c] = 13
        flight[bottom][c] = 4
    for r in range(top + 1, bottom):
        for c in range(COLS):
            flight[r][c] = rnd.choice((5, 5, 6, 6, 6, 11, 11))
    for (r, c) in ((60, 3), (64, 15), (69, 8), (73, 19), (77, 1), (82, 11),
                   (86, 5), (89, 17)):
        # a crater, flown bottom row first: 9 10 under 7 8
        flight[r][c], flight[r][c + 1] = 9, 10
        flight[r + 1][c], flight[r + 1][c + 1] = 7, 8
    return flight[::-1]


def db(out, label, data, per=16):
    out.append('%s:' % label)
    for i in range(0, len(data), per):
        out.append('\tdb\t' + ', '.join('%03Xh' % b for b in data[i:i + per]))


def main():
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    font = open(sys.argv[1], 'rb').read()
    out = ['; Made by tools/gfx.py, do not edit.',
           'MAPROWS\tequ\t%d' % MAPROWS,
           'NTEXT\tequ\t%d' % min(32, len(TEXT)),
           'NTEXT2\tequ\t%d' % max(0, len(TEXT) - 32),
           'TEXT2\tequ\t%02Xh' % TEXT2]
    tiles = []
    for t in TILES:
        assert len(t) == 8 and all(len(r) == 8 for r in t)
        tiles += bits(t)
    out.append('\talign\t256')
    db(out, 'TILEGFX', tiles)
    text = []
    for ch in TEXT:
        text += font[ord(ch) * 8:ord(ch) * 8 + 8]
    db(out, 'TEXTGFX', text)
    assert len(TEXT) - 32 <= 8         # codes 20h-27h
    asc = []
    for a in range(0x20, 0x60):
        ch = chr(a)
        i = TEXT.index(ch) if ch in TEXT else 0
        asc.append(0x80 + i if i < 32 else TEXT2 + i - 32)
    db(out, 'ASC2CODE', asc)
    # the title's logo: its glyphs, codes 30h on then, and its codes
    rows, glyphs = logo(font)
    assert len(glyphs) <= 80
    out.append('NLOGO\tequ\t%d' % len(glyphs))
    db(out, 'LOGOGFX', [b for g in glyphs for b in g])
    db(out, 'LOGO', [c for r in rows for c in r], 24)
    # the banner when the game is won
    rows, glyphs = banner(font)
    assert len(glyphs) <= 32           # in font RAM 2's slots
    out.append('NBAN\tequ\t%d' % len(glyphs))
    out.append('BANROWS\tequ\t%d' % BANROWS)
    db(out, 'BANGFX', [b for g in glyphs for b in g])
    db(out, 'BANNER', [c for r in rows for c in r], 24)
    m = make_map()
    out.append('\talign\t256')
    out.append('MAPROW:')
    for r in range(MAPROWS):
        out.append('\tdw\tMAP+%d' % (r * COLS))
    # a sine of 64 steps, 40 dots round 0, for the swingers
    import math
    db(out, 'SINT', [round(40 * math.sin(2 * math.pi * i / 64)) & 0xFF for i in range(64)])
    # rows 0 and 1 again after the end: a sprite's three rows of
    # tiles are then always in a line, with no wrap
    db(out, 'MAP', [t for row in m + m[:2] for t in row], COLS)
    out.append('IMGINFO:')
    for img in IMAGES:
        out.append('\tdb\t%d, %d' % size(img))
    assert len(IMAGES) <= 16
    out.append('\talign\t256')
    out.append('OBJTAB:')       # 2 pages for 16 images
    for i, img in enumerate(IMAGES):
        w, h = size(img)
        for sh in range(8):
            out.append('\tdw\tIMG%d+%d' % (i, sh * 96))
            out.append('\tdb\t%d, %d' % ((sh + w + 7) // 8, h))
    # the draw list's cost of each image at each shift and line in its
    # row, in units of about 100 T, then a page on its cells: by image *
    # 32 + shift * 4 + line / 2, the more of the two lines
    cost, cells = [], []
    for img in IMAGES:
        w, h = size(img)
        for sh in range(8):
            for half in range(4):
                worst = (0, 0)
                for dy in (2 * half, 2 * half + 1):
                    across, rows = (sh + w + 7) // 8, (dy + h + 7) // 8
                    worst = max(worst, (7 + 5 * (rows + across * rows), across * rows))
                cost.append(worst[0])
                cells.append(worst[1])
    out.append('\talign\t256')
    db(out, 'COSTTAB', cost + [0] * (512 - len(cost)))      # 2 pages
    db(out, 'CELLTAB', cells + [0] * (512 - len(cells)))
    out.append('IMGTAB:')
    for i in range(len(IMAGES)):
        for s in range(8):
            out.append('\tdw\tIMG%d+%d' % (i, s * 96))
    out.append('\talign\t256')
    for i, img in enumerate(IMAGES):
        db(out, 'IMG%d' % i, shifted(img))
    open(sys.argv[2], 'w').write('\n'.join(out) + '\n')


if __name__ == '__main__':
    main()

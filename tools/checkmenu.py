#!/usr/bin/env python3
"""Check 80-Force's title screen in a frame from the emulator.

Usage: checkmenu.py [--logo | --banner] FONT.bin FRAME.pgm

With --logo only the logo's rows 3-6 and HIGH SCORES are checked, for
the entry screen, whose table and help differ: a frame of the title
page, every row as it is at boot, fails. With --banner only rows
9-12, the MISSION COMPLETE banner from tools/gfx.py, every cell of
them, for a frame taken while it shows.

FRAME.pgm is a frame saved with -B -p while the title shows. The page
src/title.asm makes is drawn here too: the logo from tools/gfx.py in
rows 3-6, HIGH SCORES in row 9, the table at boot in rows 11-15, the
two lines of help in rows 18 and 19, each line in the
middle of the 24 cells, every other cell blank. Each glyph dot is 2 of
the frame's. Row 0, L lines, is blank; rows 1 on are 8 lines from line
L of the playfield, L the one that matches. Exits 1 if any dot differs.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import gfx  # noqa: E402

OX, COLS, ROWS = 8, 24, 22
TABLE = [('ACE', '010000'), ('MAX', '008000'), ('PIX', '006000'),
         ('ZAP', '004000'), ('BIT', '002000')]


def page(font):
    """The page as 22 rows of 24 glyphs, each 8 bytes."""
    blank = bytes(8)
    rows = [[blank] * COLS for _ in range(ROWS)]

    def text(k, s):
        c = (COLS - len(s)) // 2
        for i, ch in enumerate(s):
            if ch != ' ':
                rows[k - 1][c + i] = font[ord(ch) * 8:ord(ch) * 8 + 8]

    codes, glyphs = gfx.logo(font)
    for r, row in enumerate(codes):
        for c, code in enumerate(row):
            if code:
                rows[2 + r][c] = glyphs[code - 0x30]
    text(9, 'HIGH SCORES')
    for i, (who, score) in enumerate(TABLE):
        text(11 + i, '%d  %s  %s' % (i + 1, who, score))
    text(18, 'PRESS SPACE TO PLAY')
    text(19, 'ARROWS MOVE SPACE FIRES')
    return rows


BANTOP = 9                             # src/title.asm


def banpage(font):
    """The banner's rows of 24 glyphs, the rest blank."""
    blank = bytes(8)
    rows = [[blank] * COLS for _ in range(ROWS)]
    codes, glyphs = gfx.banner(font)
    base = 0xC0 - len(glyphs)
    for r, row in enumerate(codes):
        for c, code in enumerate(row):
            if code:
                rows[BANTOP - 1 + r][c] = glyphs[code - base]
    return rows


def compare(font, path, what):
    """(row 0's lines, the cells that differ) for what, 'title', 'logo'
    or 'banner', in the frame at path; None with no playfield"""
    logo, banner = what == 'logo', what == 'banner'
    d = open(path, 'rb').read().split(b'\n', 4)
    x0 = int(d[1].split()[2])
    w, h = map(int, d[2].split())
    px = d[4]
    ex = x0 + 16 * (OX - 1) + 14       # the playfield's left edge line
    top = next((y for y in range(h) if px[y * w + ex]), None)
    if top is None:
        return None
    want = banpage(font) if banner else page(font)
    best = None
    for L in range(1, 9):
        bad = set()
        for k in (range(3, 10) if logo else
                  range(BANTOP, BANTOP + gfx.BANROWS) if banner else
                  range(1, ROWS + 1)):
            for j in range(8):
                y = top + L + 8 * (k - 1) + j
                if y >= h:
                    bad.add((k, -1))
                    continue
                for c in range(COLS):
                    g = want[k - 1][c][j]
                    for b in range(8):
                        x = x0 + 16 * (OX + c) + 2 * b
                        if bool(px[y * w + x]) != bool(g >> (7 - b) & 1):
                            bad.add((k, c))
        if best is None or len(bad) < len(best[1]):
            best = (L, bad)
    return best


def shows_logo(font, path):
    """the logo and HIGH SCORES of the title or entry page, dot for dot"""
    r = compare(font, path, 'logo')
    return r is not None and not r[1]


def main():
    args = sys.argv[1:]
    logo = args[:1] == ['--logo']
    banner = args[:1] == ['--banner']
    if logo or banner:
        args = args[1:]
    if len(args) != 2:
        raise SystemExit(__doc__)
    font = open(args[0], 'rb').read()
    what = 'logo' if logo else 'banner' if banner else 'title'
    r = compare(font, args[1], what)
    if r is None:
        print('FAIL no playfield in the frame')
        return 1
    L, bad = r
    if logo and not bad:               # the entry screen, not the title
        t = compare(font, args[1], 'title')
        if not t[1]:
            print('FAIL the title page, not the entry screen: its table and help')
            return 1
    if bad:
        print('FAIL the title: cells (row, column) differ: %s' % sorted(bad)[:10])
        return 1
    print('ok   the %s, row 0 %d lines'
          % ('logo, every dot of rows 3-9' if logo
             else 'banner, every dot of rows %d-%d' % (BANTOP, BANTOP + gfx.BANROWS - 1)
             if banner else 'title, every dot of its 22 rows', L))
    return 0


if __name__ == '__main__':
    sys.exit(main())

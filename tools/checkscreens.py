#!/usr/bin/env python3
"""Check the 80-Force prototype's screens from tools/screens.c.

Usage: checkscreens.py SCREENS.bin

For each update of the game played (the title's are left out), row 0's L lines must be the bottom L lines of the
tiles above row 1. Then the playfield's 22 full rows are drawn twice, 192 x 176
dots: once from video and font RAM as the CRTC would show them, once
from the map's tiles with everything in the draw list drawn over them,
its outline cleared and its dots set, in the list's order, which is
the order the program merges them, and the MISSION COMPLETE banner in
rows 9-12 over them all while it shows. The two must match dot for dot. Prints the
first few updates that differ, with the cells, and exits 1 if any does.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import gfx  # noqa: E402

OX, COLS, ROWS = 8, 24, 22
REC = 2048 + 1024 + 1024 + 4 + 16 * 4 + 1 + 1 + 1
BANTOP = 9                             # src/title.asm


def main():
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    data = open(sys.argv[1], 'rb').read()
    tiles = [gfx.bits(t) for t in gfx.TILES]
    rows = gfx.make_map()
    images = []
    for img in gfx.IMAGES:
        dots = gfx.bits(img)
        images.append((dots, gfx.outline(dots)))
    font = open(os.path.join(os.path.dirname(__file__),
                             '../build/font.bin'), 'rb').read()
    bcodes, bglyphs = gfx.banner(font)
    bbase = 0xC0 - len(bglyphs)
    bad = 0
    count = len(data) // REC
    played = 0
    for u in range(count):
        r = data[u * REC:(u + 1) * REC]
        if r[4165] != 1:                # the title, not the game
            continue
        played += 1
        vid, f1, f2 = r[:2048], r[2048:3072], r[3072:4096]
        sad = r[4096] | r[4097] << 8
        L, t1 = r[4098], r[4099]
        draw, n = r[4100:4100 + 64], r[4164]
        got = [[0] * (8 * COLS) for _ in range(8 * ROWS)]
        want = [[0] * (8 * COLS) for _ in range(8 * ROWS)]
        for k in range(1, ROWS + 1):
            for c in range(COLS):
                code = vid[(sad + 80 * k + 2 * (OX + c)) & 0x7FF]
                g = f1[code * 8:code * 8 + 8] if code < 0x80 else f2[(code - 0x80) * 8:(code - 0x80) * 8 + 8]
                t = tiles[rows[(t1 + k - 1) % gfx.MAPROWS][c]]
                for j in range(8):
                    y = 8 * (k - 1) + j
                    for b in range(8):
                        got[y][8 * c + b] = g[j] >> (7 - b) & 1
                        want[y][8 * c + b] = t[j] >> (7 - b) & 1
        top = []                        # row 0, L lines: the tiles above row 1
        for c in range(COLS):
            code = vid[(sad + 2 * (OX + c)) & 0x7FF]
            g = f1[code * 8:code * 8 + 8] if code < 0x80 else f2[(code - 0x80) * 8:(code - 0x80) * 8 + 8]
            t = tiles[rows[(t1 - 1) % gfx.MAPROWS][c]]
            if any(g[j] != t[8 - L + j] for j in range(L)):
                top.append(c)
        if top:
            bad += 1
            if bad <= 5:
                print('FAIL update %d, L %d: row 0, columns %s' % (u, L, top[:8]))
            continue
        for i in range(n):
            x, y, img = draw[4 * i], draw[4 * i + 1] - L, draw[4 * i + 2]
            dots, mask = images[img]
            for line in range(16):
                for b in range(16):
                    if mask[line] >> (15 - b) & 1:
                        want[y + line][x + b] = 0
                    if dots[line] >> (15 - b) & 1:
                        want[y + line][x + b] = 1
        if r[4166] == 3:                # the banner over them
            for k, row in enumerate(bcodes):
                for c, code in enumerate(row):
                    g = bglyphs[code - bbase] if code else bytes(8)
                    for j in range(8):
                        for b in range(8):
                            want[8 * (BANTOP - 1 + k) + j][8 * c + b] = g[j] >> (7 - b) & 1
        cells = sorted({(y // 8 + 1, x // 8) for y in range(8 * ROWS) for x in range(8 * COLS)
                        if got[y][x] != want[y][x]})
        if cells:
            bad += 1
            if bad <= 5:
                print('FAIL update %d, L %d: cells (row, column) %s' % (u, L, cells[:8]))
    if bad:
        print('FAIL %d of %d updates differ from the map and sprites' % (bad, count))
        return 1
    if not played:
        print('FAIL no update of the game in %d' % count)
        return 1
    print('ok   %d updates played of %d, every playfield dot as the map and draw list say' % (played, count))
    return 0


if __name__ == '__main__':
    sys.exit(main())

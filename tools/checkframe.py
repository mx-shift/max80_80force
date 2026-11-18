#!/usr/bin/env python3
"""Check frames of the 80-Force prototype from the emulator.

Usage: checkframe.py [--font FONT.bin] FRAME1.pgm FRAME2.pgm

The frames are saved with -B and -p a moment apart. Each must be the
whole monitor frame, 248 lines. The playfield's left edge, a line of
2 dots at wide cell 7, must start on the same line in both frames (row
0's short row keeps the top still while the ground scrolls) and run on
with no gap for at least 177 lines (no row lost or torn). Every lit run
in the playfield is whole wide dots, an even run from an even dot. The
score row is 80-column text 186 lines below the top: runs of dots
that start or end on an odd dot, which wide cells cannot make. The playfield
differs between the frames (the ground and the sprites move). With
--font, neither frame may show the logo and HIGH SCORES of the title or
entry page (checkmenu.py), whose layout is the game's. Exits 1
on a failure.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import checkmenu  # noqa: E402


def read(path):
    d = open(path, 'rb').read().split(b'\n', 4)
    f = d[1].split()
    x0 = int(f[2])
    w, h = map(int, d[2].split())
    return x0, w, h, d[4]


def main():
    args = sys.argv[1:]
    font = None
    if args[:1] == ['--font']:
        font = open(args[1], 'rb').read()
        args = args[2:]
    if len(args) != 2:
        raise SystemExit(__doc__)
    frames = [read(p) for p in args]
    bad = 0
    for n, p in enumerate(args, 1):
        if font and checkmenu.shows_logo(font, p):
            print('FAIL frame %d is the title or entry page, not the game' % n)
            bad = 1
    tops, fields = [], []
    for n, (x0, w, h, px) in enumerate(frames, 1):
        if h != 248:
            print('FAIL frame %d is %d lines, not 248' % (n, h))
            bad = 1
            continue
        ex = x0 + 16 * 7 + 14
        lit = [y for y in range(h) if px[y * w + ex] and px[y * w + ex + 1]]
        if not lit:
            print('FAIL frame %d: no playfield edge' % n)
            bad = 1
            continue
        top = lit[0]
        run = 0
        while top + run < h and px[(top + run) * w + ex]:
            run += 1
        if run < 177:
            print('FAIL frame %d: the edge stops after %d lines' % (n, run))
            bad = 1
        tops.append(top)
        odd = 0
        for y in range(top, top + 176):
            row = px[y * w:(y + 1) * w]
            x = x0
            while x < x0 + 640:
                if row[x]:
                    s = x
                    while x < x0 + 640 and row[x]:
                        x += 1
                    if (s - x0) % 2 or (x - s) % 2:
                        odd += 1
                x += 1
        if odd:
            print('FAIL frame %d: %d runs not whole wide dots' % (n, odd))
            bad = 1
        text = [y for y in range(top + 186, min(h, top + 194))
                if any(px[y * w + x0:y * w + x0 + 640])]
        narrow = 0                      # runs wide cells cannot make
        for y in text:
            row = px[y * w:(y + 1) * w]
            x = x0
            while x < x0 + 640:
                if row[x]:
                    s = x
                    while x < x0 + 640 and row[x]:
                        x += 1
                    if (s - x0) % 2 or (x - s) % 2:
                        narrow += 1
                x += 1
        if len(text) < 5 or narrow < 10:
            print('FAIL frame %d: no score row 186 lines down' % n)
            bad = 1
        fields.append(b''.join(px[y * w + x0:y * w + x0 + 640] for y in range(top, top + 176)))
    if len(tops) == 2 and tops[0] != tops[1]:
        print('FAIL the playfield top moved: line %d, then %d' % tuple(tops))
        bad = 1
    if len(fields) == 2 and fields[0] == fields[1]:
        print('FAIL the playfield did not change')
        bad = 1
    if not bad:
        print('ok   the frames: top at line %d, edge whole, wide dots, score row' % tops[0])
    return bad


if __name__ == '__main__':
    sys.exit(main())

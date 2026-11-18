#!/usr/bin/env python3
"""Check that the score row's title never changes across frames.

Usage: checktitle.py [--font FONT.bin] FRAME.pgm [FRAME.pgm ...]

The frames are consecutive frames from the emulator's -B -p. The first
160 dots of the score row, the last 8 lit lines of each frame, hold
the title, which never changes: a row move must not write the new row
0 over the score row while it is drawn. Exits 1 if the title differs in
any frame, or if the playfield above it is the same in the first and
last, so not the game moving. With --font, a frame that shows the logo
of the title or entry page (checkmenu.py) fails too.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import checkmenu  # noqa: E402


def title(path):
    d = open(path, 'rb').read().split(b'\n', 4)
    x0 = int(d[1].split()[2])
    w, h = map(int, d[2].split())
    px = d[4]
    lit = [y for y in range(h) if any(px[y * w + x0:y * w + x0 + 640])]
    y0 = lit[-1] - 7
    return b''.join(px[(y0 + j) * w + x0:(y0 + j) * w + x0 + 160] for j in range(8))


def field(path):
    """everything above the score row"""
    d = open(path, 'rb').read().split(b'\n', 4)
    x0 = int(d[1].split()[2])
    w, h = map(int, d[2].split())
    px = d[4]
    lit = [y for y in range(h) if any(px[y * w + x0:y * w + x0 + 640])]
    return px[:(lit[-1] - 7) * w]


def main():
    args = sys.argv[1:]
    font = None
    if args[:1] == ['--font']:
        font = open(args[1], 'rb').read()
        args = args[2:]
    if len(args) < 2:
        raise SystemExit(__doc__)
    if font:
        page = [i for i, p in enumerate(args) if checkmenu.shows_logo(font, p)]
        if page:
            print('FAIL frames %s of %d show the title or entry page' % (page, len(args)))
            return 1
    if field(args[0]) == field(args[-1]):
        print('FAIL the playfield is the same in the first and last frame')
        return 1
    titles = [title(p) for p in args]
    odd = [i for i, t in enumerate(titles) if t != titles[0]]
    if odd:
        print('FAIL the score row\'s title differs in frames %s of %d' % (odd, len(titles)))
        return 1
    print('ok   the score row\'s title the same in %d frames' % len(titles))
    return 0


if __name__ == '__main__':
    sys.exit(main())

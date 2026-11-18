#!/usr/bin/env python3
"""Make 80-Force's boot disk.

Usage: mkdisk.py PROTO.sys OUT.imd [--525]

PROTO.sys is the boot sector and the program after it. The disk is
diag's and the demo's: one sided, 512-byte sectors numbered from 0,
8-inch FM with 77 tracks of 8 sectors, or with --525 MFM with 40
tracks of 9.
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..', '..', 'tools'))
from dmk2imd import write_imd  # noqa: E402

EIGHT = (77, 8, [i * 3 % 8 for i in range(8)])
FIVE = (40, 9, [i * 5 % 9 for i in range(9)])


def main():
    args = sys.argv[1:]
    five = '--525' in args
    if five:
        args.remove('--525')
    if len(args) != 2:
        raise SystemExit(__doc__)
    tracks, spt, order = FIVE if five else EIGHT
    disk = bytearray(open(args[0], 'rb').read())
    disk[2] = spt                       # bspt in src/boot.asm
    disk += b'\0' * (-len(disk) % 512)
    size = tracks * spt * 512
    if len(disk) > size:
        raise SystemExit('the program does not fit on the disk')
    disk += b'\xe5' * (size - len(disk))
    out = []
    for t in range(tracks):
        secs = []
        for r in order:
            off = (t * spt + r) * 512
            secs.append(dict(c=t, h=0, r=r, size=512, dd=five,
                             data=bytes(disk[off:off + 512]), deleted=False, bad=False))
        out.append((t, 0, secs))
    write_imd(out, args[1], not five, os.path.basename(args[0]),
              tool='software/80force/tools/mkdisk.py')


if __name__ == '__main__':
    main()

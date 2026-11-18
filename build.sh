#!/bin/sh
# Builds 80-Force: the graphics, the program, and the disks
# build/proto.imd (8-inch) and build/proto_525.imd. Also the test
# builds: build/play.imd, which plays itself from a key script
# (-DAUTOPLAY), build/die.imd, one ship that never moves, to see the
# game end (-DAUTOPLAY -DDIE), build/boss.imd, the mothership first
# (-DAUTOPLAY -DBOSSFIRST), build/bosslose.imd, the one ship against
# the mothership (all three), and build/stress.sys, every slot full
# (-DSTRESS), for tools/cost.c. Needs Python 3 and sjasmplus.
set -e
cd "$(dirname "$0")"
# FONT: xcpmz80's 8 x 8 font, font.bin beside this file unless set.
: "${FONT:=font.bin}"
mkdir -p build
cp "$FONT" build/font.bin
python3 tools/gfx.py build/font.bin build/gfx.inc
(cd src && sjasmplus --nologo --msg=war --lst=../build/proto.lst --raw=../build/proto.sys proto.asm)
python3 tools/mkdisk.py build/proto.sys build/proto.imd
python3 tools/mkdisk.py build/proto.sys build/proto_525.imd --525
(cd src && sjasmplus --nologo --msg=war -DAUTOPLAY --lst=../build/play.lst --raw=../build/play.sys proto.asm)
python3 tools/mkdisk.py build/play.sys build/play.imd
(cd src && sjasmplus --nologo --msg=war -DAUTOPLAY -DDIE --lst=../build/die.lst --raw=../build/die.sys proto.asm)
python3 tools/mkdisk.py build/die.sys build/die.imd
(cd src && sjasmplus --nologo --msg=war -DAUTOPLAY -DBOSSFIRST --lst=../build/boss.lst --raw=../build/boss.sys proto.asm)
python3 tools/mkdisk.py build/boss.sys build/boss.imd
(cd src && sjasmplus --nologo --msg=war -DAUTOPLAY -DBOSSFIRST -DDIE --lst=../build/bosslose.lst --raw=../build/bosslose.sys proto.asm)
python3 tools/mkdisk.py build/bosslose.sys build/bosslose.imd
(cd src && sjasmplus --nologo --msg=war -DSTRESS --lst=../build/stress.lst --raw=../build/stress.sys proto.asm)

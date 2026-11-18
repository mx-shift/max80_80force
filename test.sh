#!/bin/sh
# Tests 80-Force. Builds first. Needs gcc.
# Needs lobo_max80 checked out beside this one, or where MAX80 points,
# with `make` run in its emu/.
#
# 1. tools/cost.c times 2000 updates, four times round the map, of the
#    -DSTRESS build, every shot and saucer slot full and every collision
#    test made, and of the -DAUTOPLAY build, on the emulator's Z80 core
#    with no video stretch: frames A and B must fit in the picture and
#    the copy windows in theirs, with 8 lines to spare. The -DDIE builds
#    are timed too, as they go to the high scores, the title and back,
#    and each screen change draws a page in the copy windows.
#    tools/hits.c places the ship, shots, saucers, a bomber, a bullet
#    and the mothership by hand and runs hit: each box one dot in and
#    one dot out, and nothing hit once the game is over or won.
# 2. tools/screens.c runs 512 updates of the -DAUTOPLAY build, which
#    plays itself from a key script, with video and font RAM banked as on
#    the machine, and tools/checkscreens.py checks every playfield dot
#    of each against the map and the draw list.
# 3. The emulator with -B at -V 0, 2 and 5 (up to 1, 3 and 6 T an access
#    with the measured 1.02 T) for 40 seconds on the
#    AUTOPLAY disk: channel A's last report must show saucers shot down,
#    points scored and lines to spare, and two frames 0.3 s apart must pass
#    tools/checkframe.py.
#    The beeper, recorded with -s, beeps at least once for each saucer
#    shot down (tools/countbeeps.py).
# 4. A ship that never moves loses its one life against a low table:
#    channel A shows the game, the high score typed, the title and the
#    game again. The mothership, sent first, is shot down within a
#    minute and the game is won, MISSION COMPLETE over the playfield dot
#    for dot, and every dot of its updates checked;
#    a one-ship build loses to it and types its initials, under a logo
#    every dot of which is checked. The title's page is checked dot for
#    dot (tools/checkmenu.py).
# 5. 20 frames in a row of the self-playing disk, a row move among them:
#    the score row's title must not change (tools/checktitle.py).
# 6. The game's own disks boot, 8-inch and 5.25-inch, to the title.
cd "$(dirname "$0")" || exit 1
sh build.sh >/dev/null || exit 1
: "${MAX80:=../lobo_max80}"
R=$MAX80
RAW="$R/emu/max80 -r $R/reference/rom/max80.e12"
# The checks' times count from the end of the load, as the game's own
# clock does: the self-playing disks load by 4.0390 s (boss.imd
# 4.1015 s), so their -t gets that less 0.7493 s (0.7560 s) added
emu() {
	case "$*" in
	*build/boss.imd*) add=3.3455 ;;
	*build/play.imd* | *build/die.imd* | *build/bosslose.imd*) add=3.2897 ;;
	*) add=0 ;;
	esac
	n=$#
	while [ $n -gt 0 ]; do
		a=$1
		shift
		n=$((n - 1))
		if [ "$a" = -t ] && [ $n -gt 0 ]; then
			set -- "$@" -t $(awk "BEGIN { print $1 + $add }")
			shift
			n=$((n - 1))
		else
			set -- "$@" "$a"
		fi
	done
	$RAW "$@"
}
EMU=emu
[ -x $R/emu/max80 ] || { echo "build the emulator first: make in $R/emu"; exit 1; }
gcc -O2 -I $R/emu -o build/cost tools/cost.c $R/emu/z80.c || exit 1
gcc -O2 -I $R/emu -o build/screens tools/screens.c $R/emu/z80.c || exit 1
gcc -O2 -I $R/emu -o build/hits tools/hits.c $R/emu/z80.c || exit 1
T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT
fail=0

for b in stress play die bosslose; do
	if build/cost build/$b.sys build/$b.lst 2000 > $T/c; then
		echo "ok   $b, the most: $(cat $T/c)"
	else
		echo "FAIL $b, the most: $(cat $T/c)"; fail=1
	fi
done

OBJ=$(sed -n 's/^OBJ[[:space:]]*equ[[:space:]]*\([0-9A-Fa-f]*\)h.*/\1/p' src/proto.asm)
if build/hits build/proto.sys build/proto.lst $OBJ > $T/h; then
	sed 's/^ok  /ok   what hits what:/' $T/h
else
	echo "FAIL what hits what:"; cat $T/h; fail=1
fi

if build/screens build/play.sys build/play.lst 512 $T/scr.bin &&
	python3 tools/checkscreens.py $T/scr.bin > $T/scr.txt; then
	echo "ok   $(cut -c6- $T/scr.txt)"
else
	echo "FAIL the screens:"; cat $T/scr.txt; fail=1
fi

# reports FILE: the whole lines, N n U u A a B b C c H h K kills M mode
# O over S score
reports() {
	tr -d '\r' < $1 | grep '^N .* H [0-9][0-9][0-9] K [0-9] M [0-3] O [01] S [0-9]\{6\} *$'
}
report() {
	reports $1 | tail -1
}
for v in 0 2 5; do
	for t in 40 40.3; do
		rm -f $T/s$t.txt $T/f$t.pgm
		$EMU -B -V $v -f -a build/play.imd -t $t -o a:$T/s$t.txt -p $T/f$t.pgm >/dev/null 2>&1
	done
	line=$(report $T/s40.txt)
	set -- $line
	if [ "$1" = N ] && [ "${12}" -ge 5 ] && [ "${20}" -ge 500 ] && [ "$6" -ge 4 ] && [ "$8" -ge 4 ] && [ "${10}" -ge 4 ]; then
		echo "ok   -V $v, channel A: $line"
	else
		echo "FAIL -V $v, channel A: '$line'"; fail=1
	fi
	if python3 tools/checkframe.py --font build/font.bin $T/f40.pgm $T/f40.3.pgm > $T/chk; then
		echo "ok   -V $v, $(cut -c6- $T/chk)"
	else
		echo "FAIL -V $v:"; cat $T/chk; fail=1
	fi
done

# the beeper: at least a beep for every saucer shot down
$EMU -B -V 2 -f -a build/play.imd -t 40 -o a:$T/snd.txt -s $T/snd.wav >/dev/null 2>&1
set -- $(report $T/snd.txt)
beeps=$(python3 tools/countbeeps.py $T/snd.wav)
if [ "$1" = N ] && [ "$beeps" -ge "${12}" ] && [ "${12}" -ge 5 ]; then
	echo "ok   $beeps beeps for ${12} saucers shot down"
else
	echo "FAIL $beeps beeps for '${12}' saucers shot down"; fail=1
fi

# the game ends, a high score is typed, the title, and again: one ship
# that never moves, with a table it can beat
$EMU -B -V 2 -f -a build/die.imd -t 150 -o a:$T/die.txt >/dev/null 2>&1
seen=$(reports $T/die.txt | awk '{print $16}' | uniq | tr -d '\n')
case "$seen" in
*1201*) echo "ok   play, a high score typed, the title, play again: modes $seen" ;;
*) echo "FAIL not play, entry, title, play: modes '$seen'"; fail=1 ;;
esac

# the mothership: shot down within a minute when it comes first, and
# every dot of its updates
$EMU -B -V 2 -f -a build/boss.imd -t 60 -o a:$T/boss.txt >/dev/null 2>&1
set -- $(reports $T/boss.txt | awk '$14 >= 1' | head -1)
if [ "$1" = N ] && [ "${18}" = 1 ] && [ "${20}" -ge 5000 ]; then
	echo "ok   the mothership shot down, the game won, score ${20}"
else
	echo "FAIL the mothership not shot down and the game won: '$*'"; fail=1
fi
# MISSION COMPLETE over the playfield: a report every 2 s, so the
# mothership fell in the 2 s before the first that says so, and the
# banner shows for 4 s from then
k=$(reports $T/boss.txt | awk '$14 >= 1 {print NR; exit}')
$EMU -B -V 2 -f -a build/boss.imd -t $((2 * ${k:-0} + 1)) -p $T/w.pgm >/dev/null 2>&1
if python3 tools/checkmenu.py --banner build/font.bin $T/w.pgm > $T/chk; then
	echo "ok   at $((2 * ${k:-0} + 1)) s the $(cut -c10- $T/chk)"
else
	echo "FAIL the banner at $((2 * ${k:-0} + 1)) s:"; cat $T/chk; fail=1
fi
# and lost to: the one ship, with its points from the mothership, is
# shot down and types its initials
$EMU -B -V 2 -f -a build/bosslose.imd -t 40 -o a:$T/lose.txt >/dev/null 2>&1
seen=$(reports $T/lose.txt | awk '{print $16}' | uniq | tr -d '\n')
case "$seen" in
*120*) echo "ok   lost to the mothership, a high score typed, the title: modes $seen" ;;
*) echo "FAIL not lost to the mothership, entry, title: modes '$seen'"; fail=1 ;;
esac
# the logo on its entry screen, after the game's last sprites are gone
for t in 14 15; do
	rm -f $T/e.pgm
	$EMU -B -V 2 -f -a build/bosslose.imd -t $t -p $T/e.pgm >/dev/null 2>&1
	if python3 tools/checkmenu.py --logo build/font.bin $T/e.pgm > $T/chk; then
		echo "ok   the entry screen at $t s: $(cut -c10- $T/chk)"
	else
		echo "FAIL the entry screen at $t s:"; cat $T/chk; fail=1
	fi
done
if build/screens build/boss.sys build/boss.lst 1024 $T/scrb.bin &&
	python3 tools/checkscreens.py $T/scrb.bin > $T/scr.txt; then
	echo "ok   the mothership's $(cut -c6- $T/scr.txt)"
else
	echo "FAIL the mothership's screens:"; cat $T/scr.txt; fail=1
fi


for k in $(seq 10 29); do
	t=$(python3 -c "print(20 + $k * 84480 / 5066666.67)")
	rm -f $T/t$k.pgm
	$EMU -B -V 2 -f -a build/play.imd -t $t -p $T/t$k.pgm >/dev/null 2>&1
done
python3 tools/checktitle.py --font build/font.bin $T/t??.pgm || fail=1

# (-a now comes last, and the frame is removed first, so a run
# that fails cannot pass on the last one's frame)
for d in "-a build/proto.imd" "-D 1 -a build/proto_525.imd"; do
	rm -f $T/g.pgm
	if $EMU -B -V 2 -f $d -t 10 -p $T/g.pgm >/dev/null 2>&1 &&
		python3 tools/checkmenu.py build/font.bin $T/g.pgm > $T/chk; then
		echo "ok   the game disk shows the title, $d"
	else
		echo "FAIL the game disk, $d:"; cat $T/chk; fail=1
	fi
done
exit $fail

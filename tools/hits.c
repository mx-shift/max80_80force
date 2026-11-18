/* What hits what in 80-Force: hit and bosshit run on the emulator's Z80
 * core (emu/z80.c) with objects placed by hand.
 *
 * Usage: hits GAME.sys GAME.lst OBJ
 *
 * Loads the program as tools/cost.c does, runs main to the frame loop,
 * then for each case clears the objects, places the ship, a shot, a
 * saucer, a bomber, a bullet or the mothership, calls hit (or bosshit)
 * and checks what came of it: the boxes at their edges, one dot in and
 * one dot out, and nothing hit once the game is over or won. OBJ is the
 * objects' address, from src/proto.asm. Prints a line a case, exits 1
 * if any fails.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "z80.h"

static uint8_t mem[65536];

static uint8_t rd(void *c, uint16_t a) { (void)c; return mem[a]; }
static void wrm(void *c, uint16_t a, uint8_t v) { (void)c; mem[a] = v; }
static uint8_t in(void *c, uint16_t p) { (void)c; (void)p; return 0xff; }
static void out(void *c, uint16_t p, uint8_t v) { (void)c; (void)p; (void)v; }

static const char *lstname;

static int label(const char *name)
{
	FILE *f = fopen(lstname, "r");
	char line[512];
	size_t n = strlen(name);

	if (!f)
		return -1;
	while (fgets(line, sizeof line, f)) {
		char *p = line, *q;
		unsigned addr;
		while (*p == ' ')
			p++;
		while (*p >= '0' && *p <= '9')
			p++;
		while (*p == '+')
			p++;
		while (*p == ' ')
			p++;
		if (sscanf(p, "%4x", &addr) != 1)
			continue;
		q = strstr(p, name);
		if (q && q[n] == ':' && (q[-1] == ' ' || q[-1] == '\t') &&
		    !memchr(p, ';', (size_t)(q - p))) {	/* not in a comment */
			fclose(f);
			return (int)addr;
		}
	}
	fclose(f);
	fprintf(stderr, "hits: no %s in %s\n", name, lstname);
	exit(2);
}

static z80 cpu;

static void call(int addr)
{
	unsigned long long c0 = cpu.cycles;

	cpu.sp -= 2;
	mem[cpu.sp] = 0;
	mem[cpu.sp + 1] = 0;
	cpu.pc = (uint16_t)addr;
	while (cpu.pc != 0) {
		z80_step(&cpu);
		if (cpu.cycles - c0 > 400000) {
			fprintf(stderr, "hits: %04X runs on\n", addr);
			exit(2);
		}
	}
}

enum { NSHOT = 4, NFOE = 4, NEB = 2, O_SHOT = 1, O_FOE = 1 + NSHOT, O_EB = 1 + NSHOT + NFOE,
	NOBJ = 1 + NSHOT + NFOE + NEB, IMG_FOE = 1, IMG_SHOT = 2, IMG_BOMBER = 6, IMG_EB = 7,
	P_DRIFT = 0, P_BOOM = 4, P_BOMB = 5 };

static int obj, a_hit, a_bosshit, a_ships, a_over, a_won, a_score, a_bact, a_bx, a_by, a_bhp;
static int fails;

static uint8_t *o(int i) { return mem + obj + 8 * i; }

/* the ship at 100,120, alive, three ships, the game on, nothing else */
static void clear(void)
{
	memset(mem + obj, 0, 8 * NOBJ);
	o(0)[0] = 100;
	o(0)[1] = 120;
	o(0)[5] = 1;
	mem[a_ships] = 3;
	mem[a_over] = mem[a_won] = mem[a_bact] = 0;
	mem[a_score] = mem[a_score + 1] = mem[a_score + 2] = 0;
}

static void put(int i, int x, int y, int img, int pat)
{
	o(i)[0] = (uint8_t)x;
	o(i)[1] = (uint8_t)y;
	o(i)[4] = (uint8_t)img;
	o(i)[5] = 1;
	o(i)[7] = (uint8_t)pat;
}

static void check(int ok, const char *what)
{
	printf("%s %s\n", ok ? "ok  " : "FAIL", what);
	if (!ok)
		fails++;
}

/* a shot at sx,sy against a foe at 80,50: does the foe explode? */
static int shot(int img, int pat, int sx, int sy)
{
	clear();
	put(O_SHOT, sx, sy, IMG_SHOT, 0);
	put(O_FOE, 80, 50, img, pat);
	call(a_hit);
	return o(O_FOE)[7] == P_BOOM;
}

/* a foe at fx,fy against the ship: is the ship hit? */
static int touch(int img, int pat, int fx, int fy)
{
	clear();
	put(O_FOE, fx, fy, img, pat);
	call(a_hit);
	return mem[a_ships] == 2;
}

/* a bullet at bx,by against the ship: is the ship hit? */
static int bullet(int bx, int by)
{
	clear();
	put(O_EB, bx, by, IMG_EB, 0);
	call(a_hit);
	return mem[a_ships] == 2;
}

int main(int argc, char **argv)
{
	if (argc < 4) {
		fprintf(stderr, "usage: hits GAME.sys GAME.lst OBJ\n");
		return 2;
	}
	FILE *f = fopen(argv[1], "rb");
	if (!f)
		return perror(argv[1]), 2;
	size_t got = fread(mem + 0x400, 1, 0x200, f);
	got += fread(mem + 0x1000, 1, (size_t)mem[0x403] * 512, f);
	got += fread(mem + 0x9000, 1, 0x6000, f);
	fclose(f);
	(void)got;
	lstname = argv[2];
	obj = (int)strtol(argv[3], NULL, 16);
	int a_main = label("main"), a_frame = label("frame");
	a_hit = label("hit");
	a_bosshit = label("bosshit");
	a_ships = label("ships");
	a_over = label("over");
	a_won = label("won");
	a_score = label("score");
	a_bact = label("bact");
	a_bx = label("bx");
	a_by = label("by");
	a_bhp = label("bhp");

	memset(&cpu, 0, sizeof cpu);
	cpu.read = rd;
	cpu.write = wrm;
	cpu.in = in;
	cpu.out = out;
	z80_reset(&cpu);
	cpu.pc = (uint16_t)a_main;
	while (cpu.pc != a_frame) {
		z80_step(&cpu);
		if (cpu.cycles > 50000000ULL)
			return fprintf(stderr, "hits: main never reaches frame\n"), 2;
	}

	/* a shot's dots x+1..x+2, y+1..y+6; a saucer's x..x+15, y+2..y+12;
	   a bomber's x..x+15, y+1..y+8 */
	check(shot(IMG_FOE, P_DRIFT, 80 - 2, 50 - 4) && !shot(IMG_FOE, P_DRIFT, 80 - 2, 50 - 5),
	    "shot and saucer: the shot's last line on the saucer's first hits, a line higher misses");
	check(shot(IMG_FOE, P_DRIFT, 80 + 14, 50 + 11) && !shot(IMG_FOE, P_DRIFT, 80 + 14, 50 + 12),
	    "shot and saucer: the shot's first line on the saucer's last hits, a line lower misses");
	check(!shot(IMG_FOE, P_DRIFT, 80 - 3, 50) && !shot(IMG_FOE, P_DRIFT, 80 + 15, 50),
	    "shot and saucer: a dot beside either side misses");
	check(shot(IMG_BOMBER, P_BOMB, 80, 50 - 5) && !shot(IMG_BOMBER, P_BOMB, 80, 50 - 6),
	    "shot and bomber: the bomber's first line, y+1, hits, a line higher misses");
	check(shot(IMG_BOMBER, P_BOMB, 80, 50 + 7) && !shot(IMG_BOMBER, P_BOMB, 80, 50 + 8),
	    "shot and bomber: its last line, y+8, hits, a line lower misses");

	/* the ship's x+2..x+13, y+2..y+14, at 100,120 */
	check(touch(IMG_FOE, P_DRIFT, 100 + 13, 120) && !touch(IMG_FOE, P_DRIFT, 100 + 14, 120),
	    "saucer and ship: its left edge on the ship's right edge hits, a dot right misses");
	check(touch(IMG_FOE, P_DRIFT, 100 - 13, 120) && !touch(IMG_FOE, P_DRIFT, 100 - 14, 120),
	    "saucer and ship: its right edge on the ship's left edge hits, a dot left misses");
	check(touch(IMG_FOE, P_DRIFT, 100, 120 + 12) && !touch(IMG_FOE, P_DRIFT, 100, 120 + 13),
	    "saucer and ship: its top on the ship's bottom hits, a line lower misses");
	check(touch(IMG_FOE, P_DRIFT, 100, 120 - 10) && !touch(IMG_FOE, P_DRIFT, 100, 120 - 11),
	    "saucer and ship: its bottom on the ship's top hits, a line higher misses");
	check(touch(IMG_BOMBER, P_BOMB, 100, 120 + 13) && !touch(IMG_BOMBER, P_BOMB, 100, 120 + 14),
	    "bomber and ship: its top line on the ship's bottom hits, a line lower misses");
	check(touch(IMG_BOMBER, P_BOMB, 100, 120 - 6) && !touch(IMG_BOMBER, P_BOMB, 100, 120 - 7),
	    "bomber and ship: its bottom line on the ship's top hits, a line higher misses");

	/* a bullet's x+1..x+3, y+1..y+3 */
	check(bullet(100 + 12, 120 + 13) && !bullet(100 + 12, 120 + 14) && !bullet(100 + 13, 120 + 13),
	    "bullet and ship: on the ship's bottom right dot hits, a dot below or right misses");
	check(bullet(100 - 1, 120 - 1) && !bullet(100 - 2, 120 - 1) && !bullet(100 - 1, 120 - 2),
	    "bullet and ship: on its top left dot hits, a dot above or left misses");

	/* the game over: a shot on the mothership with one hit left, a
	   bullet on the ship, a saucer on the ship: nothing happens */
	clear();
	mem[a_over] = 1;
	mem[a_ships] = 0;
	o(0)[5] = 0;
	mem[a_bact] = 1;
	mem[a_bx] = 80;
	mem[a_by] = 24;
	mem[a_bhp] = 1;
	put(O_SHOT, 90, 30, IMG_SHOT, 0);
	put(O_FOE + 1, 20, 50, IMG_FOE, P_DRIFT);
	put(O_SHOT + 1, 22, 50, IMG_SHOT, 0);
	call(a_hit);
	check(mem[a_bhp] == 1 && !mem[a_won] && mem[a_bact] && o(O_FOE + 1)[7] != P_BOOM &&
	    !mem[a_score] && !mem[a_score + 1] && !mem[a_score + 2],
	    "after GAME OVER: a shot on the mothership with one hit left and one on a saucer, neither hit, no points");

	clear();
	mem[a_over] = mem[a_won] = 1;
	put(O_EB, 100, 120, IMG_EB, 0);
	put(O_FOE, 100, 120, IMG_FOE, P_DRIFT);
	call(a_hit);
	check(mem[a_ships] == 3 && o(0)[7] == 0, "after MISSION COMPLETE: a bullet and a saucer on the ship, no ship lost");

	/* the mothership's last hit with the ship's last one in the same
	   update: won, 5050 points and no ships to count */
	clear();
	mem[a_ships] = 0;
	mem[a_bact] = 1;
	mem[a_bhp] = 1;
	put(O_SHOT, 90, 30, IMG_SHOT, 0);
	cpu.iy = (uint16_t)(obj + 8 * O_SHOT);
	call(a_bosshit);
	check(mem[a_won] == 1 && mem[a_score] == 0x50 && mem[a_score + 1] == 0x50 && mem[a_score + 2] == 0,
	    "the mothership's last hit with no ships left: 5050 points, not 256 ships' worth");

	/* the mothership's last hit while the ship is hit too: the ship
	   loses nothing in the update the game is won */
	clear();
	mem[a_bact] = 1;
	mem[a_bx] = 80;
	mem[a_by] = 24;
	mem[a_bhp] = 1;
	put(O_SHOT, 90, 30, IMG_SHOT, 0);
	put(O_EB, 100, 120, IMG_EB, 0);
	call(a_hit);
	check(mem[a_won] == 1 && mem[a_ships] == 3,
	    "the mothership's last hit and a bullet on the ship in one update: won, no ship lost");

	return fails ? 1 : 0;
}

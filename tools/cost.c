/* What the 80-Force prototype's work costs, in T-states.
 *
 * Usage: cost STRESS.sys STRESS.lst [UPDATES]
 *
 * Runs the program on the emulator's Z80 core (emu/z80.c) with flat
 * RAM: the boot sector at 0400h, the program at 1000h. Give it the
 * -DSTRESS build, which keeps every shot and saucer slot full: the most
 * an update can be. main runs until it reaches the frame loop, then for
 * UPDATES game updates (default 256, 32 row moves) work_a, work_b and
 * copy_b are each called and timed. Video and font RAM are plain RAM here, so the
 * machine's stretch on those accesses is left out.
 *
 * Prints the most each took, in T-states and in lines of 320, and
 * exits 1 if any is over its budget, 8 lines short of what there is:
 * the picture's lines after the frame's register writes for A and B,
 * about 172, the copy window for copy_b, 76, and for copy_a, 68: S's 78
 * lines less its register writes and the score row, which copy_a waits
 * out (a wait not timed here, as SYSFLG is plain RAM). Set COSTLOG to
 * print each update's: A, copy A, B and copy B, in lines.
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

static int label(const char *lst, const char *name)
{
	FILE *f = fopen(lst, "r");
	char line[512];
	size_t n = strlen(name);

	if (!f)
		return -1;
	while (fgets(line, sizeof line, f)) {
		/* "  123  1ABC xx xx    name:" */
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
		if (q && q[n] == ':' && (q == line || q[-1] == ' ' || q[-1] == '\t')) {
			fclose(f);
			return (int)addr;
		}
	}
	fclose(f);
	return -1;
}

static unsigned long long call(z80 *cpu, int addr)
{
	unsigned long long c0 = cpu->cycles, limit = 400000;

	cpu->sp -= 2;
	mem[cpu->sp] = 0;
	mem[cpu->sp + 1] = 0;
	cpu->pc = (uint16_t)addr;
	while (cpu->pc != 0) {
		z80_step(cpu);
		if (cpu->cycles - c0 > limit) {
			fprintf(stderr, "cost: %04X runs on past %llu T\n", addr, limit);
			exit(2);
		}
	}
	return cpu->cycles - c0;
}

int main(int argc, char **argv)
{
	if (argc < 3) {
		fprintf(stderr, "usage: cost STRESS.sys STRESS.lst [UPDATES]\n");
		return 2;
	}
	FILE *f = fopen(argv[1], "rb");
	if (!f)
		return perror(argv[1]), 2;
	/* the boot sector to 0400h, its byte 3 the program's sectors: the
	   program to 1000h, the data after it to 9000h */
	size_t got = fread(mem + 0x400, 1, 0x200, f);
	got += fread(mem + 0x1000, 1, (size_t)mem[0x403] * 512, f);
	got += fread(mem + 0x9000, 1, 0x6000, f);
	fclose(f);
	(void)got;
	int updates = argc > 3 ? atoi(argv[3]) : 256;
	const char *names[] = { "main", "frame", "work_a", "work_b", "copy_a", "copy_b", "drawn", "la", "lb" };
	int at[9];
	for (int i = 0; i < 9; i++)
		if ((at[i] = label(argv[2], names[i])) < 0) {
			fprintf(stderr, "cost: no %s in %s\n", names[i], argv[2]);
			return 2;
		}

	z80 cpu;
	memset(&cpu, 0, sizeof cpu);
	cpu.read = rd;
	cpu.write = wrm;
	cpu.in = in;
	cpu.out = out;
	z80_reset(&cpu);
	cpu.pc = (uint16_t)at[0];
	while (cpu.pc != at[1]) {
		z80_step(&cpu);
		if (cpu.cycles > 50000000ULL)
			return fprintf(stderr, "cost: main never reaches frame\n"), 2;
	}
	unsigned long long ma = 0, mb = 0, mc = 0, mca = 0;
	int most = 0;
	for (int u = 0; u < updates; u++) {
		/* the spare lines the frame loop would have measured: plenty,
		   so the game spawns as it does with time to spare */
		mem[at[7]] = mem[at[8]] = 100;
		unsigned long long a = call(&cpu, at[2]);
		if (mem[at[6]] > most)
			most = mem[at[6]];
		unsigned long long ca = call(&cpu, at[4]);
		mem[at[7]] = mem[at[8]] = 100;
		unsigned long long b = call(&cpu, at[3]);
		unsigned long long c = call(&cpu, at[5]);
		if (a > ma) ma = a;
		if (b > mb) mb = b;
		if (c > mc) mc = c;
		if (ca > mca) mca = ca;
		if (getenv("COSTLOG"))
			printf("%d A %llu CA %llu B %llu CB %llu\n", u, a / 320, ca / 320, b / 320, c / 320);
	}
	int bad = ma > 164 * 320 || mb > 164 * 320 || mc > 68 * 320 ||
	    mca > 60 * 320;
	printf("%d objects: A %llu T (%llu lines), B %llu T (%llu lines), copy windows %llu T (%llu lines) and %llu T (%llu lines)%s\n",
	    most, ma, ma / 320, mb, mb / 320, mca, mca / 320, mc, mc / 320, bad ? ", over" : "");
	return bad;
}

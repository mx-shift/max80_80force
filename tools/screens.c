/* The 80-Force prototype's screens, update by update.
 *
 * Usage: screens PROTO.sys PROTO.lst UPDATES OUT.bin
 *
 * Runs the program on the emulator's Z80 core (emu/z80.c) as tools/cost.c
 * does, but with video and font RAM banked behind the 1K window as on the
 * machine: VLATCH bits 2-0 pick video RAM 400h-7FFh (2), font RAM 1 (4) or
 * font RAM 2 (6), and video RAM 0-3FFh is at 7C00h. After each update's
 * copy window it writes one record to OUT.bin: video RAM (2048 bytes),
 * font RAM 1 (1024), font RAM 2 (1024), the start address, L and row 1's
 * tile row as the program keeps them (sad, ld_, t1d: 4 bytes), the draw
 * list (16 x 4 bytes: x, y, image, cost), how many are in it (1), the
 * mode (1, 1 while the game is played) and banst (1, 3 while the
 * MISSION COMPLETE banner shows).
 * tools/checkscreens.py reads them. Give it the -DAUTOPLAY build, so the
 * game plays itself.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "z80.h"

static uint8_t mem[65536], vid[2048], font1[1024], font2[1024];
static uint8_t vlatch;

static uint8_t *at(uint16_t a)
{
	if (a >= 0x7000 && a < 0x7400) {
		switch (vlatch & 7) {
		case 2: return &vid[0x400 + a - 0x7000];
		case 4: return &font1[a - 0x7000];
		case 6: return &font2[a - 0x7000];
		}
	}
	if (a >= 0x7C00 && a < 0x8000)
		return &vid[a - 0x7C00];
	return &mem[a];
}
static uint8_t rd(void *c, uint16_t a) { (void)c; return *at(a); }
static void wrm(void *c, uint16_t a, uint8_t v)
{
	(void)c;
	if (a == 0x77DC)	/* VLATCH */
		vlatch = v;
	*at(a) = v;
}
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
		char *p = line, *q;
		unsigned addr;
		while (*p == ' ')
			p++;
		while ((*p >= '0' && *p <= '9') || *p == '+')
			p++;
		while (*p == ' ')
			p++;
		if (sscanf(p, "%4x", &addr) != 1)
			continue;
		q = strstr(p, name);
		if (q && q[n] == ':' && (q[-1] == ' ' || q[-1] == '\t')) {
			fclose(f);
			return (int)addr;
		}
	}
	fclose(f);
	return -1;
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
			fprintf(stderr, "screens: %04X runs on\n", addr);
			exit(2);
		}
	}
}

int main(int argc, char **argv)
{
	if (argc != 5) {
		fprintf(stderr, "usage: screens PROTO.sys PROTO.lst UPDATES OUT.bin\n");
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
	const char *names[] = { "main", "frame", "work_a", "copy_a", "work_b", "copy_b", "drawn", "sad", "la", "lb", "mode", "banst" };
	int a[12];
	for (int i = 0; i < 12; i++)
		if ((a[i] = label(argv[2], names[i])) < 0) {
			fprintf(stderr, "screens: no %s in %s\n", names[i], argv[2]);
			return 2;
		}
	int updates = atoi(argv[3]);

	memset(&cpu, 0, sizeof cpu);
	cpu.read = rd;
	cpu.write = wrm;
	cpu.in = in;
	cpu.out = out;
	z80_reset(&cpu);
	cpu.pc = (uint16_t)a[0];
	while (cpu.pc != a[1]) {
		z80_step(&cpu);
		if (cpu.cycles > 50000000ULL)
			return fprintf(stderr, "screens: main never reaches frame\n"), 2;
	}
	FILE *o = fopen(argv[4], "wb");
	if (!o)
		return perror(argv[4]), 2;
	for (int u = 0; u < updates; u++) {
		/* plenty of spare lines, so the game spawns saucers */
		mem[a[8]] = mem[a[9]] = 100;
		call(a[2]);
		call(a[3]);
		mem[a[8]] = mem[a[9]] = 100;
		call(a[4]);
		call(a[5]);
		fwrite(vid, 1, sizeof vid, o);
		fwrite(font1, 1, sizeof font1, o);
		fwrite(font2, 1, sizeof font2, o);
		fwrite(&mem[a[7]], 1, 4, o);
		fwrite(&mem[0x8980], 1, 16 * 4, o);	/* DRAW */
		fwrite(&mem[a[6]], 1, 1, o);		/* drawn */
		fwrite(&mem[a[10]], 1, 1, o);		/* mode, 1 playing */
		fwrite(&mem[a[11]], 1, 1, o);		/* banst, 3 the banner */
	}
	return fclose(o) != 0;
}

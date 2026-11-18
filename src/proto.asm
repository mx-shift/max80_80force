; 80-Force, an overhead space shooter. MIT
; license, LICENSE. Boots with no OS. This file is the screen: the
; frames, the scroll, the merge and the copy window. The game is in
; game.asm.
;
; Two CRTC frames a monitor frame, 264 lines, by rupture:
;
;   P   the playfield, 40 columns. Row 0 is L lines (R9 = L - 1), its
;       glyphs the bottom L lines of the tiles above row 1, then 22 rows
;       of 8 lines, then 10 - L blank adjust lines: 186 lines. The
;       ground moves down a line each game update as L counts 1 to 8.
;       Past 8 the start address moves up a row in the 2K ring.
;   S   the score row, 80 columns, one row shown of 8, the vsync at its
;       row 6 (line 234, as Lobo's), 14 adjust lines: 78 lines. At
;       least 2 blank lines before S give time to see the gap and
;       turn 40 columns off before S's first line.
;
; The game updates at 30 a second, over two frames, A and B. In each
; frame's picture the CPU works on the update: A moves the game and
; merges its share of the draw list, B merges the rest. An object is
; merged into
; glyphs in RAM, a glyph for each cell it touches, the ground's tile
; under it, its outline cleared and its dots set. In the copy window,
; from S's first line to P's next first line, B's work goes to the
; screen at once: the old cells get their tiles back, the new cells
; their codes, and the glyphs that were still on show are copied in.
; Glyphs not on show are copied during B's picture. Slots are taken
; from opposite ends of the pool each update, so most are not on show.
;
; Each frame the time left is counted: A and B, the picture lines left
; after the work, and C, the lines left in B's copy window. The score
; row shows the least of each second and channel A sends them at 9600
; every 2 seconds.

	include	"hw.inc"
	include	"boot.asm"		; file offset 0, runs at 0400h
	org	1000h			; file offset 200h
	jp	main

OX		equ	8		; the playfield's first wide cell
PCOLS		equ	24
PROWS		equ	22		; full rows under row 0
SOFF		equ	1920		; the score row, from the start address
NSLOT		equ	112		; sprite glyphs
SLOT2		equ	80		; slots from here are in font RAM 2
C_TOP		equ	10h		; row 0's glyphs, one a tile: 10h-1Fh
C_EDGEL		equ	28h		; the playfield's edges
C_EDGER		equ	29h
C_SLOT		equ	30h		; slots 0-79 are 30h-7Fh, 80-111 A0h-BFh
XMAX		equ	176
YMIN		equ	8
YMAX		equ	160

; Work space in A2, always at 8000h, so the program has up to the cell
; map below
STAGE		equ	8000h		; NSLOT glyphs being made
LIST0		equ	8400h		; cells, 4 bytes each, pushed down from
LIST1		equ	8600h		; the top: the cell map address, code, tile
ROW0IMG		equ	8800h		; row 0's 80 bytes
ROW1BUF		equ	8880h		; a new row 1's 48 bytes
OBJ		equ	8900h		; the game's objects, 8 bytes each
DRAW		equ	8980h		; what to merge this update, 4 bytes each
SBUF		equ	8A00h		; the score row's 80 codes
TXBUF		equ	8B00h		; the line channel A is sending
TPAGE		equ	8C00h		; the title's page, 22 rows of 24 codes
RBUF		equ	8E80h		; a playfield row's 48 bytes for vcopy
BANBUF		equ	8F00h		; the banner's rows, 48 bytes each
CELLMAP		equ	5000h		; a cell's slot + 1, 0 none: 5000h-53FFh
					; for video 400h-7FFh, 5C00h-5FFFh for
					; 0-3FFh, so + 2000h is the CPU address

	assert	high CELLMAP * 256 == CELLMAP

; Score row columns
F_SCORE		equ	18		; 6 digits
F_SHIPS		equ	32		; 1 digit
F_WAVE		equ	40		; 3 digits
F_OVER		equ	26		; GAME OVER over SHIPS and WAVE, 17 wide
F_A		equ	54
F_B		equ	60
F_C		equ	66

main:	di
	ld	sp,STACK
	ld	a,PIO_A2
	ld	(PIODA),a
	ld	a,0Eh			; channel A at 9600
	ld	(BAUDA),a
	ld	hl,siotab
	ld	b,siotabn
.sio:	ld	a,(hl)
	ld	(SIOCA),a
	inc	hl
	djnz	.sio
	xor	a
	ld	(vlw),a
	ld	hl,crtab
	call	crtset
	call	fontinit
	call	textinit
	ld	hl,ROW1BUF
	ld	de,ROW1BUF+1
	ld	bc,2*PCOLS-1
	ld	(hl),0
	ldir
	ld	hl,CELLMAP		; no cell has a slot
	ld	de,CELLMAP+1
	ld	bc,0FFFh
	ld	(hl),0
	ldir
	call	gameinit
	ld	hl,0
	ld	(sad),hl
	ld	(san),hl
	ld	a,8
	ld	(ld_),a
	ld	(ln),a
	ld	a,MAPROWS-22		; the stage's start: its first rows on
	ld	(t1d),a			; the screen
	ld	(t1n),a
	call	row0init
	call	row0make
	call	drawall
	call	topglyphs
	call	rbufinit
	ifdef	STRESS			; the full-load build plays at once
	ld	a,M_PLAY
	ld	(mode),a
	else
	call	totitle			; the title first
	endif
	ld	hl,LIST1+4*NSLOT	; empty lists
	ld	(nlp),hl
	xor	a
	ld	(nused),a
	ld	(phase),a
	ld	(txn),a
	jp	frame

; The frame loop. Enters in the vertical blank.
frame:	call	gapwait			; the blank before P
	ld	a,08h
	ld	(vlw),a
	ld	a,VL_FONT
	call	setvl
.p0:	inc	hl			; P's line 0, HL still counting
	ld	a,(SYSFLG)
	add	a,a
	jp	p,.p0
	ld	a,(ld_)			; row 0 is L lines
	dec	a
	ld	e,a
	ld	a,9
	call	wr
	ld	a,6			; 23 rows shown, before row 1
	ld	e,23
	call	wr
	ld	a,(ld_)			; to line L, row 1's first
	ld	b,a
	call	srises
	ld	a,9
	ld	e,7
	call	wr
	ld	a,(phase)		; the copy window's spare polls, after
	or	a			; B's (the phase is back to A)
	jr	nz,.nc
	ld	(idlec),hl
.nc:	call	srise
	ld	a,4			; 23 rows
	ld	e,22
	call	wr
	ld	a,(ld_)			; 10 - L lines of adjust, so P is 186
	neg
	add	a,10
	ld	e,a
	ld	a,5
	call	wr
	ld	a,7			; no vsync in P
	ld	e,127
	call	wr
	ld	hl,(sad)		; S's start, latched when S starts
	ld	de,SOFF
	add	hl,de
	ld	a,h
	and	7
	ld	e,a
	ld	a,12
	call	wr
	ld	e,l
	ld	a,13
	call	wr

	ld	a,(phase)
	or	a
	jr	nz,.wb
	call	work_a
	call	gapwait
	ld	(idlea),hl
	jr	.s
.wb:	call	work_b
	call	gapwait
	ld	(idleb),hl
.s:	xor	a			; S: 80 columns, set in the blank
	ld	(vlw),a
	ld	a,VL_FONT
	call	setvl
.s0:	ld	a,(SYSFLG)		; S's line 0
	add	a,a
	jp	p,.s0
	ld	a,4			; 8 rows, 1 shown, 14 adjust lines
	ld	e,7
	call	wr
	ld	a,6
	ld	e,1
	call	wr
	ld	a,5
	ld	e,14
	call	wr
	call	srise
	ld	a,7			; the vsync at row 6
	ld	e,6
	call	wr
	ld	a,(phase)
	or	a
	jr	nz,.cb
	call	copy_a
	jr	.e
.cb:	call	copy_b
.e:	ld	hl,(sad)		; P's start, latched when P starts
	ld	a,h
	and	7
	ld	e,a
	ld	a,12
	call	wr
	ld	e,l
	ld	a,13
	call	wr
	call	txbyte
	ld	hl,(fcount)		; frames since the start, for the seed
	inc	hl
	ld	(fcount),hl
	ld	a,(phase)
	xor	1
	ld	(phase),a
	jp	frame

; Wait for a low display enable of 6 polls, longer than a line's blank,
; so a gap between frames. HL counts the polls, 35 T each while the
; picture is on.
gapwait:
	ld	hl,0
.h:	inc	hl
	ld	a,(SYSFLG)
	add	a,a
	jp	m,.h
	ld	b,6
.l:	inc	hl
	ld	a,(SYSFLG)
	add	a,a
	jp	m,.h
	djnz	.l
	ret

; Wait for the next line's picture to start
srise:	ld	a,(SYSFLG)
	add	a,a
	jp	m,srise
.l:	ld	a,(SYSFLG)
	add	a,a
	jp	p,.l
	ret
srises:	call	srise
	djnz	srises
	ret

; CRTC register A = E
wr:	ld	(CRTREG),a
	ld	a,e
	ld	(CRTBYT),a
	ret

crtset:	ld	b,0
.n:	ld	a,b
	ld	(CRTREG),a
	ld	a,(hl)
	ld	(CRTBYT),a
	inc	hl
	inc	b
	ld	a,b
	cp	16
	jr	nz,.n
	ret

; VLATCH = A, with the wide bit while P shows
setvl:	push	hl
	ld	hl,vlw
	or	(hl)
	ld	(VLATCH),a
	pop	hl
	ret

; One frame of 264 lines to start from: 33 rows of 8
crtab:	db	77h, 50h, 61h, 06h, 32, 0, 23, 29, 0, 7, 20h, 0, 0, 0, 0, 0

; Lobo's channel A setup with one stop bit and no auto enables (diag's)
siotab:	db	18h,18h,14h,44h,13h,0C1h,15h,0EAh,11h,0
siotabn	equ	$-siotab

; ---------------------------------------------------------------------
; Frame A's picture: a new update. The scroll moves a line, the game
; moves (game.asm), and frame A's share of the draw list is merged.
work_a:
	ld	hl,(nlp)		; last update's cells are now the old
	ld	(oldlist),hl
	ld	a,(nused)
	ld	(oldused),a
	ld	a,(slim)		; last update's pool
	ld	(plim),a
	ld	a,(dir)			; the slots from the other end,
	xor	1			; the list in the other buffer
	ld	(dir),a
	jr	nz,.dn
	ld	a,(banreq)		; the banner's glyphs take the pool's
	or	a			; top, from an update going up: the
	jr	z,.up			; last one's slots, at the top, are
	xor	a			; still shown until its copy B
	ld	(banreq),a
	inc	a
	ld	(banst),a
	ld	a,NSLOT-NBAN
	ld	(slim),a
.up:	ld	hl,LIST0+4*NSLOT	; going up: from slot + 1 = 1, full at
	ld	b,1			; slim + 1, INC C
	ld	a,(slim)
	inc	a
	ld	d,a
	ld	e,0Ch
	jr	.l0
.dn:	ld	hl,LIST1+4*NSLOT	; going down: from slim, full at 0, DEC C
	ld	a,(slim)
	ld	(mdlim+1),a
	ld	b,a
	ld	de,0Dh
.l0:	ld	(nlp),hl
	ld	a,b
	ld	(nextp1),a
	ld	a,d
	ld	(mclim+1),a
	ld	a,e
	ld	(mcstep),a
	xor	a
	ld	(nused),a
	ld	a,(mode)		; the ground holds still off the game
	cp	M_PLAY
	jr	z,.play
	call	still
	jp	menu			; the title, entry or start
.play:	ld	a,(banst)		; and under the banner
	or	a
	jr	z,.scroll
	call	still
	jr	.game
.scroll:	ld	a,(ld_)			; the scroll: L + 1, or a row up
	inc	a
	ld	hl,(sad)
	ld	c,0
	cp	9
	jr	nz,.ns
	ld	a,(t1d)
	dec	a
	and	MAPROWS-1
	ld	(t1n),a
	ld	de,-80
	add	hl,de
	ld	a,h
	and	7
	ld	h,a
	ld	c,1
	ld	a,1
	jr	.sc
.ns:	push	af
	ld	a,(t1d)
	ld	(t1n),a
	pop	af
.sc:	ld	(ln),a
	ld	(san),hl
	ld	a,c
	ld	(shiftp),a

.game:	call	game			; the ship, shots and saucers move
	ld	ix,DRAW			; and frame A's share of them is merged
	ld	a,(drawa)
	or	a
	ret	z
	ld	b,a
.m:	push	bc
	call	merge
	pop	bc
	ld	de,4
	add	ix,de
	djnz	.m
	ret

; The ground held still: the new state the shown one
still:	ld	hl,(sad)
	ld	(san),hl
	ld	a,(ld_)
	ld	(ln),a
	ld	a,(t1d)
	ld	(t1n),a
	xor	a
	ld	(shiftp),a
	ret

; Frame B's picture: the rest of the draw list, row 0's glyphs, a row
; move made ready, and the slots not on show copied in.
work_b:
	ld	a,(drawa)		; the rest of the draw list
	ld	l,a
	ld	h,0
	add	hl,hl
	add	hl,hl
	ld	de,DRAW
	add	hl,de
	push	hl
	pop	ix
	ld	a,(drawa)
	ld	b,a
	ld	a,(drawn)
	sub	b
	jr	z,.nm
	ld	b,a
.m:	push	bc
	call	merge
	pop	bc
	ld	de,4
	add	ix,de
	djnz	.m
.nm:	ld	a,(shiftp)
	or	a
	call	nz,shiftprep
	call	splitslots
	ld	a,(free0)
	ld	b,a
	ld	a,(free1)
	jp	copyslots		; [free0, free1)

; Old and new slot ranges: the new not in the old go now, the rest
; (ovl0 to ovl1) in the copy window.
splitslots:
	ld	a,(nused)
	ld	c,a
	ld	a,(oldused)
	ld	d,a
	ld	a,(dir)
	or	a
	jr	nz,.down
	; new [0, u), old [112 - uo, 112): new from min(u, 112 - uo) is on show
	; (112 is plim, the pool's top last update)
	ld	a,(plim)
	sub	d
	cp	c
	jr	c,.a1
	ld	a,c
.a1:	ld	(free1),a
	ld	(ovl0),a
	xor	a
	ld	(free0),a
	ld	a,c
	ld	(ovl1),a
	ret
.down:	; new [112 - u, 112), old [0, uo): new below max(112 - u, uo) is on show
	; (112 is slim)
	ld	a,(slim)
	sub	c
	ld	(ovl0),a
	cp	d
	jr	nc,.d1
	ld	a,d
.d1:	ld	(free0),a
	ld	(ovl1),a
	ld	a,(slim)
	ld	(free1),a
	ret

; Copy slots [B, A) from STAGE to font RAM
copyslots:
	cp	b
	ret	z
	ret	c
	ld	c,a			; C = end
	ld	a,b
	cp	SLOT2
	jr	nc,.two
	ld	a,c			; font RAM 1 part, [B, min(C, 80))
	cp	SLOT2
	jr	c,.e1
	ld	a,SLOT2
.e1:	push	bc
	push	af
	ld	a,VL_FONT
	call	setvl
	pop	af
	sub	b			; slots
	call	.len
	push	hl			; length
	ld	l,b
	ld	h,0
	add	hl,hl
	add	hl,hl
	add	hl,hl
	push	hl
	ld	de,STAGE
	add	hl,de
	ex	(sp),hl
	ld	de,FONTWIN+C_SLOT*8
	add	hl,de
	ex	de,hl			; DE font
	pop	hl			; HL stage
	pop	bc
	call	fastcopy
	pop	bc
	ld	a,c
	cp	SLOT2+1
	ret	c
	ld	b,SLOT2
.two:	ld	a,VL_FONT2		; font RAM 2 part, [max(B, 80), C)
	call	setvl
	ld	a,c
	sub	b
	call	.len
	push	hl
	ld	l,b
	ld	h,0
	add	hl,hl
	add	hl,hl
	add	hl,hl
	push	hl
	ld	de,STAGE
	add	hl,de
	ex	(sp),hl
	ld	de,FONTWIN-30h*8	; code 50h + n, font RAM 2 index n - 30h
	add	hl,de
	ex	de,hl
	pop	hl
	pop	bc
	jp	fastcopy
.len:	ld	l,a			; HL = A * 8
	ld	h,0
	add	hl,hl
	add	hl,hl
	add	hl,hl
	ret

; Copy BC bytes, a multiple of 8, HL to DE
fastcopy:
	ld	a,b
	or	c
	ret	z
.l:	ldi
	ldi
	ldi
	ldi
	ldi
	ldi
	ldi
	ldi
	jp	pe,.l
	ret

; The copy window after B: the update goes on the screen.
copy_b:	ld	a,VL_VIDEO
	call	setvl
	ld	(spsave),sp
	ld	a,(oldused)		; the old cells' tiles back
	or	a
	jr	z,.nr
	ld	b,a
	ld	sp,(oldlist)
.r:	pop	hl
	pop	de
	set	5,h
	ld	(hl),d
	djnz	.r
.nr:	ld	sp,(spsave)
	ld	a,(shiftp)		; a row move: row 0 and row 1
	or	a
	jr	z,.nsh
	call	gapwait			; the new row 0 is where the score row
					; was: wait until it has been drawn
	ld	hl,(san)
	ld	de,ROW0IMG
	ld	bc,80
	call	vcopy
	ld	hl,(san)
	ld	de,80+2*OX
	add	hl,de
	ld	de,ROW1BUF
	ld	bc,2*PCOLS
	call	vcopy
.nsh:	ld	a,(nused)		; the new cells' codes
	or	a
	jr	z,.nn
	ld	b,a
	ld	sp,(nlp)
.n:	pop	hl
	pop	de
	ld	(hl),0			; out of the cell map for the next update
	set	5,h
	ld	(hl),e
	djnz	.n
.nn:	ld	sp,(spsave)
	call	banshow			; the banner over them
	ld	a,(ovl0)		; the slots that were on show
	ld	b,a
	ld	a,(ovl1)
	call	copyslots
	call	topglyphs		; row 0's glyphs for the new L
	ld	hl,(san)		; the new state shows from the next P
	ld	(sad),hl
	ld	a,(ln)
	ld	(ld_),a
	ld	a,(t1n)
	ld	(t1d),a
	ld	a,(banst)		; the pool's top no longer shown
	cp	1
	jr	nz,.nb
	inc	a
	ld	(banst),a
.nb:	ld	b,4			; some rows of a screen job
	jp	scrjob

; The copy window after A: the counts, once an update.
copy_a:	ld	hl,(idlea)		; the lines left, and the least of
	call	lines			; each this second
	ld	(la),a
	ld	hl,mina
	call	least
	ld	hl,(idleb)
	call	lines
	ld	(lb),a
	ld	hl,minb
	call	least
	ld	hl,(idlec)
	call	lines
	ld	(lc),a
	ld	hl,minc
	call	least
	ld	a,(upd)
	inc	a
	ld	(upd),a
	cp	30			; every second
	jr	c,.show
	xor	a
	ld	(upd),a
	ld	a,(mina)		; the score row and the report show the
	ld	(sha),a			; least of the second
	ld	a,(minb)
	ld	(shb),a
	ld	a,(minc)
	ld	(shc),a
	ld	a,255
	ld	(mina),a
	ld	(minb),a
	ld	(minc),a
	ld	a,(secs)
	inc	a
	ld	(secs),a
	and	1
	call	z,report
.show:	ld	a,(mode)		; off the game: the best score
	cp	M_PLAY
	jr	z,.pl
	ld	hl,shi
	ld	c,F_OVER
	call	stext
	ld	hl,HISCORE+5
	ld	de,SBUF+F_OVER+5
	jr	.sc2
.pl:	ld	hl,sships		; SHIPS and WAVE, or GAME OVER
	ld	a,(over)
	or	a
	jr	z,.so
	ld	hl,sover
	ld	a,(won)
	or	a
	jr	z,.so
	ld	hl,swon
.so:	ld	c,F_OVER
	call	stext
	ld	a,(over)
	or	a
	jr	nz,.sc
	ld	a,(ships)
	add	a,'0'-20h
	ld	l,a
	ld	h,0
	ld	de,ASC2CODE
	add	hl,de
	ld	a,(hl)
	ld	(SBUF+F_SHIPS),a
	ld	a,(wave)
	ld	c,F_WAVE
	call	num
.sc:	ld	hl,score+2		; the score, 6 BCD digits
	ld	de,SBUF+F_SCORE
.sc2:	ld	b,3
.d:	ld	a,(hl)
	rrca
	rrca
	rrca
	rrca
	call	.dig
	ld	a,(hl)
	call	.dig
	dec	hl
	djnz	.d
	ld	a,(sha)
	ld	c,F_A
	call	num
	ld	a,(shb)
	ld	c,F_B
	call	num
	ld	a,(shc)
	ld	c,F_C
	call	num
	call	gapwait			; once the score row has been drawn,
	ld	a,VL_VIDEO		; all of it to the screen
	call	setvl
	ld	hl,(sad)
	ld	de,SOFF
	add	hl,de
	ld	de,SBUF
	ld	bc,80
	call	vcopy
	call	banfont		; the banner's glyphs, once
	ld	b,3			; and some rows of a screen job, not its
	jp	scrjoba			; first part, in what is left of S
.dig:	and	0Fh			; the BCD digit in A to DE
	push	hl
	add	a,'0'-20h
	ld	l,a
	ld	h,0
	push	de
	ld	de,ASC2CODE
	add	hl,de
	pop	de
	ld	a,(hl)
	ld	(de),a
	inc	de
	pop	hl
	ret

; The ASCII text at HL into SBUF from column C
stext:	ld	b,0
	ld	de,SBUF
	ex	de,hl
	add	hl,bc
	ex	de,hl
.c:	ld	a,(hl)
	or	a
	ret	z
	push	hl
	sub	20h
	ld	l,a
	ld	h,0
	ld	bc,ASC2CODE
	add	hl,bc
	ld	a,(hl)
	ld	(de),a
	pop	hl
	inc	hl
	inc	de
	jr	.c

; Polls in HL to lines: HL * 35 / 320, about HL * 28 / 256, at most 255
lines:	ld	d,h
	ld	e,l
	add	hl,hl
	add	hl,hl
	add	hl,hl			; 8
	push	hl
	add	hl,hl
	add	hl,hl			; 32
	pop	bc
	or	a
	sbc	hl,bc			; 24
	add	hl,de
	add	hl,de
	add	hl,de
	add	hl,de			; 28
	ld	a,h
	ret

; (HL) = min((HL), A)
least:	cp	(hl)
	ret	nc
	ld	(hl),a
	ret

; A as 3 decimal digits into SBUF at column C
num:	ld	b,0
	ld	hl,SBUF
	add	hl,bc
	inc	hl
	inc	hl
	ld	b,3
.d:	push	bc
	ld	c,10
	call	div8
	add	a,'0'-20h
	push	hl
	ld	hl,ASC2CODE
	ld	c,a
	ld	b,0
	add	hl,bc
	ld	a,(hl)
	pop	hl
	ld	(hl),a
	dec	hl
	ld	a,e			; the quotient
	pop	bc
	djnz	.d
	ret
; A / C: E quotient, A remainder
div8:	ld	e,0
.l:	cp	c
	ret	c
	sub	c
	inc	e
	jr	.l

; ---------------------------------------------------------------------
; Merge the draw list entry at IX (x, y, image) into slots, in the next
; update's place. Keeps IX. The object's first tile, cell map byte and
; image line are worked out once, then stepped a row at a time; the
; stack is the new list for the whole object, and C holds the next slot
; + 1 across its rows.
merge:	ld	(msave),ix
	ld	a,(ix+0)
	ld	b,a			; B = x
	and	7
	ld	c,a			; C = shift
	ld	a,(ix+2)		; OBJTAB[image * 8 + shift]: the image at
	add	a,a			; this shift, cells across, height
	add	a,a
	add	a,a
	add	a,c
	ld	l,a
	ld	h,0
	add	hl,hl
	add	hl,hl
	ld	de,OBJTAB
	add	hl,de
	ld	e,(hl)
	inc	l
	ld	d,(hl)
	inc	l
	ld	a,(hl)
	ld	(.nc+1),a
	inc	l
	ld	a,(hl)
	ld	(mgleft),a		; lines of the image still to do
	ld	(mimg),de
	ld	a,b			; c0 = x / 8
	rrca
	rrca
	rrca
	and	1Fh
	ld	b,a
	ld	a,(ln)			; C = y - L
	ld	c,a
	ld	a,(ix+1)
	sub	c
	ld	c,a
	rrca				; E = the first row less 1
	rrca
	rrca
	and	1Fh
	ld	e,a
	ld	a,(t1n)			; its tile
	add	a,e
	and	MAPROWS-1
	add	a,a
	ld	l,a
	ld	h,high MAPROW
	ld	a,(hl)
	inc	l
	ld	h,(hl)
	add	a,b
	ld	l,a
	jr	nc,.t
	inc	h
.t:	ld	(mtp),hl
	ld	a,e			; and its cell map byte
	inc	a
	add	a,a
	ld	l,a
	ld	h,high MUL80
	ld	a,(hl)
	inc	l
	ld	h,(hl)
	ld	l,a
	ld	de,(san)
	add	hl,de
	ld	a,b
	add	a,OX
	add	a,a
	add	a,l
	ld	l,a
	jr	nc,.v
	inc	h
.v:	ld	a,h
	and	7
	add	a,0Ch
	and	0Fh
	or	high CELLMAP
	ld	h,a
	ld	(mcm),hl
	ld	a,c			; the first row from glyph line dy,
	and	7			; at most 8 - dy lines
	ld	(mcj0+1),a
	ld	(mcj0z+1),a
	neg
	add	a,8
	ld	(spt),sp
	ld	sp,(nlp)
	ld	e,a
	ld	a,(nextp1)
	ld	c,a
	ld	a,e
.row:	ld	hl,mgleft		; D = this row's lines, no more than
	cp	(hl)			; are left
	jr	c,.c
	ld	a,(hl)
.c:	ld	d,a
	ld	a,(hl)
	sub	d
	ld	(hl),a
	ld	a,d
	add	a,a
	ld	(mgc2),a		; the image moves 2 a line
	add	a,a			; the row's constants for D lines
	add	a,a
	ld	l,a
	ld	h,high ROWTAB
	ld	e,(hl)
	inc	l
	ld	d,(hl)
	inc	l
	ld	(mcjp+1),de
	ld	e,(hl)
	inc	l
	ld	d,(hl)
	inc	l
	ld	(mcjz+1),de
	ld	a,(hl)
	ld	(mcbk+1),a
	ld	hl,(mimg)		; HL' the image's line, column 0
	push	hl
	exx
	pop	hl
	exx
	ld	hl,(mcm)
	ld	ix,(mtp)
.nc:	ld	b,0			; cells across
	call	mcells
	ld	a,(mgleft)
	or	a
	jr	z,.end
	ld	hl,(mcm)		; the next row: 80 on in video RAM
	ld	de,80
	add	hl,de
	ld	a,h
	cp	high CELLMAP+4
	jr	nz,.w
	ld	a,high CELLMAP+0Ch
.w:	and	0Fh
	or	high CELLMAP
	ld	h,a
	ld	(mcm),hl
	ld	hl,(mtp)		; 24 on in the map, which has its first
	ld	de,PCOLS		; rows again after its end, so a
	add	hl,de			; sprite's rows never wrap
	ld	(mtp),hl
	ld	a,(mimg)		; this row's lines on in the image, in
	ld	hl,mgc2			; its 32-byte column, no carry
	add	a,(hl)
	ld	(mimg),a
	xor	a			; from glyph line 0, 8 lines at most
	ld	(mcj0+1),a
	ld	(mcj0z+1),a
	ld	a,8
	jr	.row
.end:	ld	(nlp),sp
	ld	sp,(spt)
	ld	a,c
	ld	(nextp1),a
	ld	ix,(msave)
	ld	a,(dir)			; how many slots are taken: the next
	or	a			; less the first
	ld	a,c
	jr	nz,.d
	dec	a
	ld	(nused),a
	ret
.d:	neg
mdlim:	add	a,NSLOT			; slim, set by work_a
	ld	(nused),a
	ret

; For 0 to 8 lines: where in MERGE8 and MERGE8Z to start, and how far
; the image moved in them, 2 a line
	align	256
ROWTAB:
	dup	9, i
	dw	MERGE8+(8-i)*7
	dw	MERGE8Z+(8-i)*5
	db	2*i, 0, 0, 0
	edup

; B cells along a row. A cell has a slot already if another sprite
; took it this update, or takes the next: its code and tile, then its
; CPU address, pushed on the list, its glyph started as the tile. Then
; the sprite's lines are merged into the glyph. A slot's glyph is at
; STAGE + 8 * slot.
mcells:	pop	de			; the return, off the list
	ld	(mcret+1),de
mc_cell:	ld	a,(hl)
	or	a
	jr	nz,mc_have
	ld	a,c
mclim:	cp	0			; NSLOT + 1 going up, 0 going down: full
	jp	z,mc_skip
	ld	(hl),a
mcstep:	inc	c			; or DEC C, going down
	ld	e,a
	ld	d,high CODETAB
	ex	af,af'			; A' = slot + 1
	ld	a,(de)
	ld	e,a
	ld	d,(ix+0)
	push	de			; the code and the tile
	push	hl			; the cell map address: + 2000h is the CPU's
	ld	a,d
mc_c1:	exx
	ex	af,af'			; A = slot + 1, A' = the tile
	dec	a
	rlca
	rlca
	rlca
	ld	c,a
	and	7
	or	high STAGE
	ld	d,a
	ld	a,c
	or	7			; from the glyph's last line back
	ld	e,a
	ex	af,af'
	or	a
	jr	z,mc_zero
	add	a,a
	add	a,a
	add	a,a
	add	a,7
	ld	c,a
	ld	b,high TILEGFX
	rept	7
	ld	a,(bc)
	ld	(de),a
	dec	c
	dec	e
	endr
	ld	a,(bc)
	ld	(de),a
	jr	mc_mrg
mc_zero:	xor	a			; over blank space: the glyph
	rept	7			; clear, then the sprite's dots
	ld	(de),a			; stored, no mask needed
	dec	e
	endr
	ld	(de),a
	ld	a,e
mcj0z:	add	a,0
	ld	e,a
mcjz:	jp	MERGE8Z
mc_have:	exx
	dec	a
	rlca
	rlca
	rlca
	ld	c,a
	and	7
	or	high STAGE
	ld	d,a
	ld	a,c
	and	0F8h
	ld	e,a
mc_mrg:	ld	a,e
mcj0:	add	a,0			; the row's first line
	ld	e,a
mcjp:	jp	MERGE8			; into MERGE8 for the row's lines
mback:	ld	a,l			; the image back to the row's line, an
mcbk:	sub	0			; 8-bit step that undoes INC L's wrap
	ld	l,a			; at a page's end, then on to the next
	ld	bc,32			; column with a carry
	add	hl,bc
mc_nx:	exx
	inc	ix
	inc	l
	inc	l
	jr	nz,mc_nw
	inc	h
	ld	a,h
	cp	high CELLMAP+4
	jr	nz,mc_w
	ld	a,high CELLMAP+0Ch
mc_w:	and	0Fh
	or	high CELLMAP
	ld	h,a
mc_nw:	dec	b
	jp	nz,mc_cell
mcret:	jp	0
mc_skip:	exx				; no slot left: the cell is left out
	ld	bc,32
	add	hl,bc
	jr	mc_nx

; By slot + 1: its code
	align	256
CODETAB:
	db	0
	dup	SLOT2, i
	db	C_SLOT+i
	edup
	dup	NSLOT-SLOT2, i
	db	0A0h+i
	edup

	assert	(high STAGE & 7) == 0 && low STAGE == 0
	assert	BANBUF + BANROWS * 2 * PCOLS <= 9000h

; A line over blank space: the dots only
MERGE8Z:
	rept	8
	inc	l
	ld	a,(hl)
	inc	l
	ld	(de),a
	inc	e
	endr
	jp	mback

; A line: the glyph AND the outline mask, OR the dots. HL the image
; (mask, dots), DE the glyph.
MERGE8:
	rept	8
	ld	a,(de)
	and	(hl)
	inc	l
	or	(hl)
	inc	l
	ld	(de),a
	inc	e
	endr
	jp	mback

	align	256
MUL80:
	dup	24, i
	dw	i*80
	edup

; ---------------------------------------------------------------------
; Row 0's glyphs for L lines (ln), straight into font RAM: glyph
; C_TOP + t gets the bottom L lines of tile t from its line 0. Tile 0
; is blank and its glyph stays so. Row 0's codes, C_TOP + the tile of
; the row above row 1, change only at a row move (row0make).
topglyphs:
	ld	a,VL_FONT
	call	setvl
	ld	a,(ln)
	ld	c,a
	ld	b,0
	neg
	add	a,8
	ld	(.skip+1),a		; 8 - L
	ld	hl,TILEGFX+8
	ld	de,FONTWIN+(C_TOP+1)*8
	ld	a,15
.t:	push	af
.skip:	ld	a,0
	add	a,l
	ld	l,a			; TILEGFX is a page, no carry
	push	bc
	ldir
	pop	bc
	ld	a,(.skip+1)		; on to the next tile and glyph
	add	a,e
	ld	e,a
	jr	nc,.n
	inc	d
.n:	pop	af
	dec	a
	jr	nz,.t
	ret

	assert	low TILEGFX == 0

; ROW0IMG, row 0's 80 bytes, for the tile row above row 1 when row 1 is
; tile row A: C_TOP + each tile, a wide cell each. The edges and blanks
; around them are put in once, by row0init.
row0make:
	dec	a
	and	MAPROWS-1
	add	a,a
	ld	l,a
	ld	h,high MAPROW
	ld	a,(hl)
	inc	l
	ld	h,(hl)
	ld	l,a
	ld	de,ROW0IMG+2*OX
	ld	b,PCOLS
.c:	ld	a,(hl)
	add	a,C_TOP
	ld	(de),a
	inc	hl
	inc	e			; ROW0IMG is 80 bytes in a page
	inc	e
	djnz	.c
	ret

	assert	low ROW0IMG + 80 <= 256

; ROW0IMG's edges and blanks
row0init:
	ld	hl,ROW0IMG
	ld	de,ROW0IMG+1
	ld	bc,79
	ld	(hl),0
	ldir
	ld	a,C_EDGEL
	ld	(ROW0IMG+2*(OX-1)),a
	ld	a,C_EDGER
	ld	(ROW0IMG+2*(OX+PCOLS)),a
	ret

; A row move, in B's picture: the score row copied to where it goes,
; and row 1's tiles made ready for the copy window
shiftprep:
	ld	a,VL_VIDEO
	call	setvl
	ld	hl,(sad)		; the score row at the old start + 1840,
	ld	de,SOFF-80		; the new start + 1920
	add	hl,de
	ld	de,SBUF
	ld	bc,80
	call	vcopy
	ld	a,(t1n)			; row 0's codes for the new tile row
	call	row0make
	ld	a,(t1n)			; row 1, the tiles, a code a wide cell
	add	a,a
	ld	l,a
	ld	h,0
	ld	de,MAPROW
	add	hl,de
	ld	a,(hl)
	inc	hl
	ld	h,(hl)
	ld	l,a
	ld	de,ROW1BUF
	ld	b,PCOLS
.r1:	ld	a,(hl)
	ld	(de),a
	inc	hl
	inc	de
	inc	de
	djnz	.r1
	ret

; Copy BC bytes from DE to video offset HL, mod 2K, in runs that stay
; in one half of video RAM. The window on video RAM.
vcopy:	ld	(vco),hl
	ld	(vcs),de
.n:	ld	a,b
	or	c
	ret	z
	ld	hl,(vco)
	ld	a,h
	and	7
	ld	h,a
	ld	(vco),hl
	cp	4
	ld	a,4
	jr	c,.lo
	ld	a,8
.lo:	ld	d,a
	ld	e,0
	ex	de,hl
	or	a
	sbc	hl,de			; room to the half's end
	or	a
	sbc	hl,bc
	jr	c,.part
	ld	h,b			; all of it
	ld	l,c
	ld	bc,0
	jr	.go
.part:	add	hl,bc			; the room, and the rest after it
	ld	a,c
	sub	l
	ld	c,a
	ld	a,b
	sbc	a,h
	ld	b,a
.go:	push	bc
	ld	b,h
	ld	c,l
	ld	hl,(vco)
	push	hl
	add	hl,bc
	ld	(vco),hl
	pop	hl
	call	vcpu
	ex	de,hl
	ld	hl,(vcs)
	ldir
	ld	(vcs),hl
	pop	bc
	jr	.n

; HL = the CPU address of video offset HL, mod 2K
vcpu:	ld	a,h
	and	7
	cp	4
	jr	nc,.h
	add	a,high VIDLO
	ld	h,a
	ret
.h:	add	a,high FONTWIN-4
	ld	h,a
	ret

; Video offset HL = A. Keeps all but A. The window on video RAM.
vput:	push	hl
	push	af
	call	vcpu
	pop	af
	ld	(hl),a
	pop	hl
	ret

; ---------------------------------------------------------------------
; The screen from nothing: every row, the score row
drawall:
	ld	a,VL_VIDEO
	call	setvl
	ld	hl,VIDLO
	ld	de,VIDLO+1
	ld	bc,3FFh
	ld	(hl),0
	ldir
	ld	hl,FONTWIN
	ld	de,FONTWIN+1
	ld	bc,3FFh
	ld	(hl),0
	ldir
	ld	hl,(sad)		; row 0
	ld	de,ROW0IMG
	ld	bc,80
	call	vcopy
	ld	a,VL_VIDEO
	call	setvl
	ld	b,1			; rows 1-22: the edges and the tiles
.row:	push	bc
	ld	a,b
	add	a,a
	ld	l,a
	ld	h,0
	ld	de,MUL80
	add	hl,de
	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	ld	hl,(sad)
	add	hl,de
	push	hl
	ld	de,2*(OX-1)
	add	hl,de
	ld	a,C_EDGEL
	call	vput
	ld	de,2*(PCOLS+1)
	add	hl,de
	ld	a,C_EDGER
	call	vput
	pop	hl
	ld	de,2*OX
	add	hl,de
	ld	a,(t1d)
	dec	a
	add	a,b
	and	MAPROWS-1
	add	a,a
	ld	e,a
	ld	d,0
	push	hl
	ld	hl,MAPROW
	add	hl,de
	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	pop	hl
	ld	b,PCOLS
.t:	ld	a,(de)
	call	vput
	inc	hl
	inc	hl
	inc	de
	djnz	.t
	pop	bc
	inc	b
	ld	a,b
	cp	PROWS+1
	jr	nz,.row
	ld	hl,(sad)		; the score row
	ld	de,SOFF
	add	hl,de
	ld	de,SBUF
	ld	bc,80
	jp	vcopy

; The font RAMs: tiles, edges, slots clear, the text from 80h
fontinit:
	ld	a,VL_FONT
	call	setvl
	ld	hl,FONTWIN
	ld	de,FONTWIN+1
	ld	bc,3FFh
	ld	(hl),0
	ldir
	ld	hl,TILEGFX
	ld	de,FONTWIN
	ld	bc,16*8
	ldir
	ld	hl,FONTWIN+C_EDGEL*8	; a line at each edge, 1 dot wide
	ld	b,8
.l:	ld	(hl),01h
	inc	hl
	djnz	.l
	ld	b,8
.r:	ld	(hl),80h
	inc	hl
	djnz	.r
	ld	hl,TEXTGFX+NTEXT*8	; the text past 32, codes TEXT2 on
	ld	de,FONTWIN+TEXT2*8
	ld	bc,NTEXT2*8+1
	dec	bc
	ld	a,b
	or	c
	jr	z,.n2
	ldir
.n2:	ld	a,VL_FONT2
	call	setvl
	ld	hl,FONTWIN
	ld	de,FONTWIN+1
	ld	bc,3FFh
	ld	(hl),0
	ldir
	ld	hl,TEXTGFX
	ld	de,FONTWIN
	ld	bc,NTEXT*8
	ldir
	ret

; The score row's text into SBUF
textinit:
	ld	hl,SBUF
	ld	de,SBUF+1
	ld	bc,79
	ld	(hl),80h
	ldir
	ld	hl,stitle
	ld	de,SBUF+2
.c:	ld	a,(hl)
	or	a
	ret	z
	push	hl
	sub	20h
	ld	l,a
	ld	h,0
	ld	bc,ASC2CODE
	add	hl,bc
	ld	a,(hl)
	ld	(de),a
	pop	hl
	inc	hl
	inc	de
	jr	.c
; From column 2. The F_ columns above are where its numbers are.
stitle:	db	"80-FORCE  SCORE 000000  SHIPS 3  WAVE 001    FREE A 000 B 000 C 000",0
sships:	db	"SHIPS 3  WAVE 001",0
sover:	db	"GAME OVER        ",0
swon:	db	"MISSION COMPLETE ",0
shi:	db	"HIGH             ",0

; ---------------------------------------------------------------------
; Channel A: a line every 2 seconds, a byte a frame when the SIO is
; ready, never waiting
report:	ld	a,(txn)
	or	a
	ret	nz
	ld	hl,TXBUF
	ld	(hl),'N'
	inc	hl
	ld	a,(drawn)
	call	dec3
	ld	(hl),'U'
	inc	hl
	ld	a,(oldused)
	call	dec3
	ld	(hl),'A'
	inc	hl
	ld	a,(sha)
	call	dec3
	ld	(hl),'B'
	inc	hl
	ld	a,(shb)
	call	dec3
	ld	(hl),'C'
	inc	hl
	ld	a,(shc)
	call	dec3
	ld	(hl),'H'
	inc	hl
	ld	a,(hits)
	call	dec3
	ld	(hl),'K'		; motherships destroyed
	inc	hl
	ld	(hl),' '
	inc	hl
	ld	a,(bkills)
	and	7
	add	a,'0'
	ld	(hl),a
	inc	hl
	ld	(hl),' '
	inc	hl
	ld	(hl),'M'		; the mode, M_
	inc	hl
	ld	(hl),' '
	inc	hl
	ld	a,(mode)
	add	a,'0'
	ld	(hl),a
	inc	hl
	ld	(hl),' '
	inc	hl
	ld	(hl),'O'		; the game over, 0 or 1
	inc	hl
	ld	(hl),' '
	inc	hl
	ld	a,(over)
	add	a,'0'
	ld	(hl),a
	inc	hl
	ld	(hl),' '
	inc	hl
	ld	(hl),'S'
	inc	hl
	ld	(hl),' '
	inc	hl
	ld	de,score+2
	ld	b,3
.s:	ld	a,(de)
	rrca
	rrca
	rrca
	rrca
	and	0Fh
	add	a,'0'
	ld	(hl),a
	inc	hl
	ld	a,(de)
	and	0Fh
	add	a,'0'
	ld	(hl),a
	inc	hl
	dec	de
	djnz	.s
	ld	(hl),' '
	inc	hl
	ld	(hl),13
	inc	hl
	ld	(hl),10
	ld	a,6*6+4+4+4+9+2
	ld	(txn),a
	ld	hl,TXBUF
	ld	(txp),hl
	ret
; " ddd " at HL, HL moves on
dec3:	ld	(hl),' '
	inc	hl
	inc	hl
	inc	hl
	ld	b,3
.d:	ld	c,10
	call	div8
	add	a,'0'
	ld	(hl),a
	dec	hl
	ld	a,e
	djnz	.d
	inc	hl
	inc	hl
	inc	hl
	inc	hl
	ld	(hl),' '
	inc	hl
	ret

txbyte:	ld	a,(txn)
	or	a
	ret	z
	ld	a,(SIOCA)
	and	4
	ret	z
	ld	hl,(txp)
	ld	a,(hl)
	ld	(SIODA),a
	inc	hl
	ld	(txp),hl
	ld	hl,txn
	dec	(hl)
	ret

; ---------------------------------------------------------------------
vlw:	db	0			; 08h while P shows
fcount:	dw	0			; frames since the start
phase:	db	0			; 0 frame A, 1 frame B
sad:	dw	0			; on show: the start address, L, row 1's tile row
ld_:	db	0
t1d:	db	0
san:	dw	0			; the next update's
ln:	db	0
t1n:	db	0
shiftp:	db	0			; the next update moves a row
nused:	db	0
oldused: db	0
dir:	db	0
oldlist: dw	0			; the old list's first entry
slim:	db	NSLOT			; the sprite pool, less the banner's
plim:	db	NSLOT			; and last update's
nextp1:	db	0			; the next slot + 1
msave:	dw	0
mgleft:	db	0			; the object's image lines still to do
mgc2:	db	0			; 2 x this row's lines
mcm:	dw	0			; a sprite row's first cell map byte
mtp:	dw	0			; and its tile
spt:	dw	0
nlp:	dw	0
free0:	db	0
free1:	db	0
ovl0:	db	0
ovl1:	db	0
idlea:	dw	0
idleb:	dw	0
idlec:	dw	0
la:	db	0			; lines left this update
lb:	db	0
lc:	db	0
mina:	db	255			; the least this second
minb:	db	255
minc:	db	255
sha:	db	0			; and last second's, as shown
shb:	db	0
shc:	db	0
upd:	db	0
secs:	db	0
txn:	db	0
txp:	dw	0
spsave:	dw	0
mimg:	dw	0
vco:	dw	0
vcs:	dw	0

	include	"game.asm"
	include	"title.asm"
PROG_END:
	assert	PROG_END <= CELLMAP
	block	(1000h-PROG_END) & 511, 0	; to a whole sector

; The images, the map and the tables, loaded by the boot sector after
; the program, to A2 at DATA
DATA		equ	9000h
	disp	DATA
	include	"../build/gfx.inc"
DATA_END:
	ent
	assert	DATA_END <= 0F000h

PROGSEC	equ	(PROG_END-1000h+511)/512
DATASEC	equ	(DATA_END-DATA+511)/512

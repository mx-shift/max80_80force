; 80-Force's title screen and high scores. The game is in one of
; four modes:
;
;   M_TITLE  the logo, the high scores, PRESS SPACE TO PLAY; the ground
;            holds still and nothing moves
;   M_ENTRY  a new high score: its initials are typed, UP and DOWN for
;            the letter, A to Z, SPACE for the next
;   M_START  the playfield is drawn back from the map, then M_PLAY
;   M_PLAY   the game (game.asm)
;
; The title and the entry screen are a page of 22 rows of 24 codes,
; TPAGE, drawn into the playfield's rows 1 to 22 a few rows at a time
; in the copy windows (scrjob), as the whole playfield does not fit in
; one. Built with -DAUTOPLAY the title starts a game by itself and the
; initials type themselves.
;
; The high scores are in RAM, and start again at every boot.

M_TITLE		equ	0
M_PLAY		equ	1
M_ENTRY		equ	2
M_START		equ	3
NHI		equ	5		; high scores, 6 bytes each: 3 letters
					; and the score, BCD, low byte first

; Once an update, in frame A's picture, while the game is not played
menu:	xor	a			; nothing to merge
	ld	(drawn),a
	ld	(drawa),a
	call	sndtick
	call	keys
	ld	a,(kb)			; the keys just pressed
	ld	hl,prevkb
	ld	c,(hl)
	ld	(hl),a
	ld	b,a
	ld	a,c
	cpl
	and	b
	ld	(kpress),a
	ld	hl,menut
	inc	(hl)
	ld	a,(mode)
	cp	M_ENTRY
	jp	z,entry
	cp	M_START
	jr	z,.start
	ifdef	AUTOPLAY		; the title
	ld	a,(menut)
	cp	60
	ret	c
	else
	ld	a,(kpress)
	and	K_FIRE
	ret	z
	endif
	ld	a,M_START		; draw the map back, then play
	ld	(mode),a
	ld	a,(t1d)
	call	row0make
	ld	a,1
	ld	(jobsrc),a
	jp	jobstart
.start:	ld	a,(jobrow)		; once the map is back
	or	a
	ret	nz
	ld	a,M_PLAY
	ld	(mode),a
	jp	gameinit

; To the title: the objects gone, the page made and drawn
totitle:
	ld	a,M_TITLE
	ld	(mode),a
	call	clearobj
	call	pagebase
	ld	hl,smsg1
	ld	b,18
	call	pcentre
	ld	hl,smsg2
	ld	b,19
	call	pcentre
	jr	topage

; To the entry screen for a new high score, at the place newhi made
toentry:
	ld	a,M_ENTRY
	ld	(mode),a
	call	clearobj
	call	pagebase
	ld	hl,snew
	ld	b,18
	call	pcentre
	ld	hl,skeys
	ld	b,19
	call	pcentre
topage:	xor	a
	ld	(menut),a
	ld	(drawn),a		; this update merges nothing
	ld	(drawa),a
	ld	(jobsrc),a		; from TPAGE
	ld	(banreq),a		; no banner, the whole pool from the
	ld	(banst),a		; next update
	ld	a,NSLOT
	ld	(slim),a
	ld	a,(kb)			; a key held now is not a press
	ld	(prevkb),a
	call	row0blank
	jp	jobstart

; The game's objects gone, so nothing is merged
clearobj:
	ld	hl,OBJ
	ld	de,OBJ+1
	ld	bc,NOBJ*8-1
	ld	(hl),0
	ldir
	ret

; TPAGE: blank, the logo in rows 3-6, HIGH SCORES in row 9, the table
; in rows 11-15
TABROW		equ	11
pagebase:
	ld	hl,TPAGE
	ld	de,TPAGE+1
	ld	bc,22*24-1
	ld	(hl),0
	ldir
	ld	hl,LOGO			; "80-FORCE"
	ld	de,TPAGE+2*24
	ld	bc,4*24
	ldir
	ld	hl,shigh
	ld	b,9
	call	pcentre
	ld	b,0			; the table
.e:	push	bc
	call	hiline
	pop	bc
	inc	b
	ld	a,b
	cp	NHI
	jr	nz,.e
	ret

; Table line B (0-4) into TPAGE row TABROW + B: "1  ACE  010000"
hiline:	ld	a,b
	add	a,'1'
	ld	(hbuf),a
	ld	l,b			; HISCORE + 6 B
	ld	h,0
	add	hl,hl
	ld	e,l
	ld	d,h
	add	hl,hl
	add	hl,de
	ld	de,HISCORE
	add	hl,de
	ld	de,hbuf+3		; the letters
	ld	c,3
.l:	ld	a,(hl)
	ld	(de),a
	inc	hl
	inc	de
	dec	c
	jr	nz,.l
	inc	hl			; the score, high byte first
	inc	hl
	ld	de,hbuf+8
	ld	c,3
.s:	ld	a,(hl)
	rrca
	rrca
	rrca
	rrca
	and	0Fh
	add	a,'0'
	ld	(de),a
	inc	de
	ld	a,(hl)
	and	0Fh
	add	a,'0'
	ld	(de),a
	inc	de
	dec	hl
	dec	c
	jr	nz,.s
	ld	a,b
	add	a,TABROW
	ld	b,a
	ld	hl,hbuf
	jp	pcentre

; The ASCII text at HL into TPAGE row B (1-22), in the middle
pcentre:
	push	hl
	ld	c,0
.n:	ld	a,(hl)
	or	a
	jr	z,.w
	inc	c
	inc	hl
	jr	.n
.w:	ld	a,24
	sub	c
	srl	a
	ld	c,a
	pop	hl
; ... from column C
ptext:	push	hl
	ld	a,b
	dec	a
	ld	l,a			; TPAGE + 24 (B - 1) + C
	ld	h,0
	add	hl,hl
	add	hl,hl
	add	hl,hl
	ld	e,l
	ld	d,h
	add	hl,hl
	add	hl,de
	ld	e,c
	ld	d,0
	add	hl,de
	ld	de,TPAGE
	add	hl,de
	ex	de,hl
	pop	hl
.c:	ld	a,(hl)
	or	a
	ret	z
	push	hl
	sub	20h
	ld	l,a
	ld	h,0
	push	de
	ld	de,ASC2CODE
	add	hl,de
	pop	de
	ld	a,(hl)
	ld	(de),a
	pop	hl
	inc	hl
	inc	de
	jr	.c

; Row 0 blank, as the page starts at row 1
row0blank:
	ld	hl,ROW0IMG+2*OX
	ld	b,PCOLS
.c:	ld	(hl),C_TOP
	inc	l
	inc	l
	djnz	.c
	ret

; ---------------------------------------------------------------------
; The score in the table? NC if not. Else C, the table moved down a
; place below it, the new line "A  " at hplace, the score in it.
newhi:	ld	ix,HISCORE
	ld	b,0
.p:	ld	a,(score+2)		; score > this line's?
	cp	(ix+5)
	jr	c,.no
	jr	nz,.yes
	ld	a,(score+1)
	cp	(ix+4)
	jr	c,.no
	jr	nz,.yes
	ld	a,(score)
	cp	(ix+3)
	jr	c,.no
	jr	z,.no
.yes:	ld	a,b			; move the lines below down
	ld	(hplace),a
	ld	hl,HISCORE+6*NHI-7	; from the last line's end, back
	ld	de,HISCORE+6*NHI-1
	ld	a,NHI-1
	sub	b
	jr	z,.put
	add	a,a
	ld	c,a
	add	a,a
	add	a,c			; 6 a line
	ld	c,a
	ld	b,0
	lddr
.put:	ld	a,(hplace)		; the new line
	ld	l,a
	ld	h,0
	add	hl,hl
	ld	e,l
	ld	d,h
	add	hl,hl
	add	hl,de
	ld	de,HISCORE
	add	hl,de
	ld	(hl),'A'
	inc	hl
	ld	(hl),' '
	inc	hl
	ld	(hl),' '
	inc	hl
	ld	a,(score)
	ld	(hl),a
	inc	hl
	ld	a,(score+1)
	ld	(hl),a
	inc	hl
	ld	a,(score+2)
	ld	(hl),a
	xor	a
	ld	(hpos),a
	scf
	ret
.no:	ld	de,6
	add	ix,de
	inc	b
	ld	a,b
	cp	NHI
	jr	nz,.p
	or	a
	ret

; The entry screen: UP and DOWN change the letter at hpos, A to Z and
; round, SPACE or
; RIGHT keeps it and goes to the next; after the third, the title.
; The letter being typed blinks.
entry:	ld	a,(hplace)		; HL = the letter at hpos
	ld	l,a
	ld	h,0
	add	hl,hl
	ld	e,l
	ld	d,h
	add	hl,hl
	add	hl,de
	ld	de,HISCORE
	add	hl,de
	ld	a,(hpos)
	ld	e,a
	ld	d,0
	add	hl,de
	ifdef	AUTOPLAY		; the self-playing build types CPU, a
	ld	a,(menut)		; letter every 16 updates, to be seen
	and	15
	jr	nz,.show
	ld	de,sauto
	ld	a,(hpos)
	add	a,e
	ld	e,a
	jr	nc,.ad
	inc	d
.ad:	ld	a,(de)
	ld	(hl),a
	jr	.next
	else
	ld	a,(kpress)
	ld	c,a
	bit	0,c			; UP: the next letter
	jr	z,.dn
	ld	a,(hl)
	call	nextch
	ld	(hl),a
.dn:	bit	1,c			; DOWN: the one before
	jr	z,.ok
	ld	a,(hl)
	call	prevch
	ld	(hl),a
.ok:	ld	a,c			; SPACE or RIGHT: kept
	and	K_FIRE|K_RIGHT
	jr	z,.show
	endif
.next:	ld	a,(hl)			; a space kept is an A
	cp	' '
	jr	nz,.nx
	ld	(hl),'A'
.nx:	ld	a,(hpos)
	inc	a
	ld	(hpos),a
	cp	3
	jr	c,.n3
	ld	hl,SND_HIT
	call	sound
	jp	totitle
.n3:	inc	hl			; the next starts as A
	ld	(hl),'A'
.show:	ld	a,(hplace)		; the line again, the letter blinking
	ld	b,a
	push	bc
	call	hiline
	pop	bc
	ld	a,(menut)
	and	8
	jr	z,.row
	ld	a,b			; blank where the letter is: hbuf + 3 +
	add	a,TABROW		; hpos, from the line's start
	ld	b,a
	ld	a,(hpos)
	add	a,3+5			; the line starts at column 5
	ld	c,a
	ld	hl,sspace
	call	ptext
	ld	a,(hplace)
	ld	b,a
.row:	ld	a,(jobrow)		; just that row to the screen, unless
	or	a			; the page is still being drawn, which
	ret	nz			; draws it too
	ld	a,b
	add	a,TABROW
	ld	(jobrow),a
	ld	(jobend),a
	xor	a
	ld	(jobsrc),a
	ret

; A to the next letter, Z to A, or the one before, A to Z
nextch:	cp	'Z'
	jr	z,.z
	inc	a
	ret
.z:	ld	a,'A'
	ret
prevch:	cp	'A'
	jr	z,.a
	dec	a
	ret
.a:	ld	a,'Z'
	ret

; ---------------------------------------------------------------------
; The screen job: playfield rows jobrow to jobend drawn, from TPAGE
; (jobsrc 0) or the map (1), a few each copy window. A job starts with
; the logo's glyphs and row 0 from ROW0IMG.
jobstart:
	ld	a,1
	ld	(jobrow),a
	ld	a,22
	ld	(jobend),a
	ld	a,1
	ld	(job0),a
	ret

; From copy A: the logo's glyphs, 30 lines, are left to copy B
scrjoba:
	ld	a,(job0)
	or	a
	ret	nz
	; B rows at most
scrjob:	ld	a,(jobrow)
	or	a
	ret	z
	ld	a,VL_VIDEO
	call	setvl
	ld	a,(job0)
	or	a
	jr	z,.r
	xor	a
	ld	(job0),a
	push	bc
	ld	a,VL_FONT		; the logo's glyphs, codes 30h on,
	call	setvl			; slots the game is not using now
	ld	hl,LOGOGFX
	ld	de,FONTWIN+30h*8
	ld	bc,NLOGO*8
	ldir
	ld	a,VL_VIDEO
	call	setvl
	ld	hl,(sad)
	ld	de,ROW0IMG
	ld	bc,80
	call	vcopy
	pop	bc
	ret				; the rows from the next window
.r:	push	bc
	ld	a,(jobrow)
	call	drawrow
	pop	bc
	ld	a,(jobend)
	ld	hl,jobrow
	cp	(hl)
	jr	z,.done
	inc	(hl)
	djnz	.r
	ret
.done:	ld	(hl),0
	ret

; Playfield row A (1-22): 24 codes from TPAGE or the map, a wide cell
; each, to video RAM
drawrow:
	ld	c,a
	ld	a,(jobsrc)
	or	a
	jr	nz,.map
	ld	a,c			; TPAGE + 24 (row - 1)
	dec	a
	ld	l,a
	ld	h,0
	add	hl,hl
	add	hl,hl
	add	hl,hl
	ld	e,l
	ld	d,h
	add	hl,hl
	add	hl,de
	ld	de,TPAGE
	add	hl,de
	jr	.go
.map:	ld	a,(t1d)			; the map's tile row t1d + row - 1
	add	a,c
	dec	a
	and	MAPROWS-1
	add	a,a
	ld	l,a
	ld	h,high MAPROW
	ld	a,(hl)
	inc	l
	ld	h,(hl)
	ld	l,a
.go:	ld	de,RBUF			; a code a wide cell
	ld	b,PCOLS
.c:	ld	a,(hl)
	ld	(de),a
	inc	hl
	inc	de
	inc	de
	djnz	.c
	ld	a,c			; to row C
	add	a,a
	ld	l,a
	ld	h,high MUL80
	ld	a,(hl)
	inc	l
	ld	h,(hl)
	ld	l,a
	ld	de,(sad)
	add	hl,de
	ld	de,2*OX
	add	hl,de
	ld	de,RBUF
	ld	bc,2*PCOLS
	jp	vcopy

; ---------------------------------------------------------------------
; The MISSION COMPLETE banner, playfield rows BANTOP on, the ground held
; still under it. Its glyphs are the sprite pool's top NBAN slots,
; codes 0C0h - NBAN on, given up by work_a.
BANTOP		equ	9

; From copy A, once the pool's top is no longer on show: the glyphs,
; and the rows made ready for vcopy
banfont:
	ld	a,(banst)
	cp	2
	ret	nz
	inc	a
	ld	(banst),a
	ld	hl,BANNER
	ld	de,BANBUF
	ld	b,BANROWS*PCOLS
.c:	ld	a,(hl)
	ld	(de),a
	inc	hl
	inc	de
	xor	a
	ld	(de),a
	inc	de
	djnz	.c
	ld	a,VL_FONT2
	call	setvl
	ld	hl,BANGFX
	ld	de,FONTWIN+(40h-NBAN)*8	; code 80h + n is font RAM 2's n
	ld	bc,NBAN*8
	ldir
	ld	a,VL_VIDEO
	jp	setvl

; From copy B, after the sprites' cells: the banner's rows over them,
; every update, as a sprite under it leaves its cells there
banshow:
	ld	a,(banst)
	cp	3
	ret	nz
	ld	hl,BANBUF
	ld	b,BANTOP
.r:	push	bc
	push	hl
	ld	a,b			; row B's video offset
	add	a,a
	ld	l,a
	ld	h,high MUL80
	ld	a,(hl)
	inc	l
	ld	h,(hl)
	ld	l,a
	ld	de,(san)
	add	hl,de
	ld	de,2*OX
	add	hl,de
	pop	de
	push	de
	ld	bc,2*PCOLS
	call	vcopy
	pop	hl
	ld	de,2*PCOLS
	add	hl,de
	pop	bc
	inc	b
	ld	a,b
	cp	BANTOP+BANROWS
	jr	nz,.r
	ret

; RBUF's odd bytes stay 0
rbufinit:
	ld	hl,RBUF
	ld	de,RBUF+1
	ld	bc,2*PCOLS-1
	ld	(hl),0
	ldir
	ret

shigh:	db	"HIGH SCORES",0
smsg1:	db	"PRESS SPACE TO PLAY",0
smsg2:	db	"ARROWS MOVE SPACE FIRES",0
snew:	db	"NEW HIGH SCORE",0
skeys:	db	"UP DOWN LETTER SPACE OK",0
sspace:	db	" ",0
	ifdef	AUTOPLAY
sauto:	db	"CPU"
	endif
hbuf:	db	"1  AAA  000000",0

; The table at boot
HISCORE:
	ifdef	DIE			; the one-ship test build: low, so its
	db	"ACE", 50h, 00h, 00h	; score makes the table
	db	"MAX", 40h, 00h, 00h
	db	"PIX", 30h, 00h, 00h
	db	"ZAP", 20h, 00h, 00h
	db	"BIT", 10h, 00h, 00h
	else
	db	"ACE", 00h, 00h, 01h	; 10000
	db	"MAX", 00h, 80h, 00h	; 8000
	db	"PIX", 00h, 60h, 00h	; 6000
	db	"ZAP", 00h, 40h, 00h	; 4000
	db	"BIT", 00h, 20h, 00h	; 2000
	endif

mode:	db	M_TITLE
menut:	db	0			; updates in this mode
prevkb:	db	0
kpress:	db	0
hplace:	db	0			; the new high score's line
hpos:	db	0			; and the letter being typed
jobrow:	db	0			; the screen job: the next row, 0 none,
jobend:	db	0			; the last, TPAGE or the map, row 0
jobsrc:	db	0			; first
job0:	db	0

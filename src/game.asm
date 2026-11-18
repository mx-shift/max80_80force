; 80-Force's game: the ship, its shots,
; the saucers in waves, what hits what, the score and the ships left.
; Run once an update, in frame A's picture, before the sprites are
; merged.
;
; An object is 8 bytes in OBJ: x, y, dx, dy, image, alive, age, and for
; a saucer its pattern (P_). A swinger keeps its middle in dx. The
; ship's 8th byte counts its explosion once its last life is lost.
; Object 0 is the ship, then NSHOT shots, then NFOE saucers. x is in glyph
; dots across the playfield (0-176), y in lines from the playfield's top
; (8-160), as the merge takes them.
;
; Built with -DAUTOPLAY the keys come from a script, so a test sees the
; same game every run; with -DDIE as well, one ship that never moves or
; fires, to see the game end and start again. Built with -DSTRESS every shot and saucer slot is
; kept full and every collision test is made but nothing is ever hit:
; the most work an update can be, for tools/cost.c.

	ifndef	NSHOT			; 4 shots, 4 saucers and 2 bullets fit
NSHOT		equ	4		; at 30 updates a second, by
	endif				; tools/cost.c over 2000 updates
	ifndef	NFOE
NFOE		equ	4
	endif
	ifndef	NEB
NEB		equ	2		; the bombers' bullets
	endif
NOBJ		equ	1+NSHOT+NFOE+NEB
O_SHOT		equ	1
O_FOE		equ	1+NSHOT
O_EB		equ	1+NSHOT+NFOE
IMG_SHIP	equ	0		; the images, in tools/gfx.py's order
IMG_FOE		equ	1
IMG_SHOT	equ	2
IMG_EXPL	equ	3		; 3 frames, 3 updates each
IMG_BOMBER	equ	6
IMG_EB		equ	7
IMG_BOSS	equ	8		; 4: top left, top right, bottom left,
					; bottom right
EBV		equ	3		; lines an update a bullet falls
BOSSHP		equ	24		; hits the mothership takes
BOSSY		equ	24		; the line it patrols at
BOSSGAP		equ	24		; updates between its bullets
SHIPYMIN	equ	96		; the ship stays in the lower part
SHIPV		equ	3		; dots an update across
SHIPVY		equ	2		; lines an update up and down
SHOTV		equ	6		; lines an update a shot climbs
FIREGAP		equ	6		; updates between shots
FLASH		equ	90		; updates the ship blinks after a hit
	ifdef	DIE			; a test build: one ship that sits
SHIPS0		equ	1		; still and fires, so it scores, then
	else				; a saucer gets it and the game ends
SHIPS0		equ	3		; ships at the start
	endif
WAVEPAUSE	equ	45		; updates between one wave's end and the next
OVERWAIT	equ	60		; updates GAME OVER shows
OVERWIN		equ	120		; and the MISSION COMPLETE banner
P_DRIFT		equ	0		; the saucers' patterns: swing a dot an
P_SINE		equ	1		; update, follow a sine round a middle,
P_DIVE		equ	2		; steer at the ship, straight down,
P_LINE		equ	3		; an explosion, a bomber that drifts and
P_BOOM		equ	4		; drops bullets on the ship
P_BOMB		equ	5
	ifndef	FIXA			; the split's guess at each frame's
FIXA		equ	130		; own work, in units of about 100 T:
	endif				; A moves and tests what hits what,
	ifndef	FIXB			; B makes row 0's glyphs and copies
FIXB		equ	10		; each new cell's glyph, 1.5 a cell
	endif

K_UP		equ	1		; the keys, as kb holds them
K_DOWN		equ	2
K_LEFT		equ	4
K_RIGHT		equ	8
K_FIRE		equ	16

	assert	NOBJ*8 <= DRAW-OBJ

; A new game: the ship in the middle at the bottom, nothing else, the
; score 0, SHIPS0 ships, the first wave after a pause
gameinit:
	ld	hl,OBJ
	ld	de,OBJ+1
	ld	bc,NOBJ*8-1
	ld	(hl),0
	ldir
	ld	ix,OBJ
	ld	(ix+0),88
	ld	(ix+1),YMAX-8
	ld	(ix+4),IMG_SHIP
	ld	(ix+5),1
	xor	a
	ld	(hits),a
	ld	(firet),a
	ld	(drawn),a
	ld	(drawa),a
	ld	(score),a
	ld	(score+1),a
	ld	(score+2),a
	ld	(over),a
	ld	(wave),a
	ld	(wi),a
	ld	(wleft),a
	ld	(bact),a
	ld	(won),a
	ld	(banreq),a
	ld	(banst),a
	ifdef	BOSSFIRST		; a test build: the mothership first
	ld	a,NWAVES
	ld	(wi),a
	endif
	ld	a,SHIPS0
	ld	(ships),a
	ld	a,WAVEPAUSE
	ld	(wpause),a
	ret

game:	call	keys
	call	sndtick
	ld	a,(over)
	or	a
	call	nz,gameover
	ld	a,(mode)		; gone to the entry screen or the title:
	cp	M_PLAY			; nothing more this update
	ret	nz
	ld	a,(OBJ+5)		; no ship once the game is over
	or	a
	call	nz,ship
	call	shots
	call	foes
	call	boss
	call	ebullets
	call	spawn
	call	hit
	jp	drawlist

; GAME OVER: the saucers fly on and no more come. After OVERWAIT
; updates, the entry screen for a new high score, or the title.
gameover:
	ld	hl,overt
	ld	a,(hl)
	inc	a
	jr	z,.sat
	ld	(hl),a
.sat:	ld	a,(hl)
	ld	b,OVERWAIT		; GAME OVER for 2 seconds, MISSION
	ld	a,(won)			; COMPLETE for 4
	or	a
	jr	z,.w
	ld	b,OVERWIN
.w:	ld	a,(hl)
	cp	b
	ret	c
	call	newhi
	jp	c,toentry
	jp	totitle

; ---------------------------------------------------------------------
; kb = the keys held: the arrows and SPACE, all in matrix row 6 so no
; three of them can ghost a fourth, or W A S D
keys:
	ifdef	AUTOPLAY
	ld	a,(apc)			; the script: a count of updates, keys
	or	a
	jr	nz,.same
	ld	hl,(app)
	ld	a,(hl)
	or	a
	jr	nz,.next
	ld	hl,APSCRIPT
	ld	a,(hl)
.next:	ld	(apc),a
	inc	hl
	ld	a,(hl)
	ld	(apk),a
	inc	hl
	ld	(app),hl
.same:	ld	hl,apc
	dec	(hl)
	ld	a,(apk)
	ld	(kb),a
	jr	mixseed
	else
	ld	a,(MATRIX+40h)		; D3 UP, D4 DOWN, D5 LEFT, D6 RIGHT,
	rrca				; D7 SPACE: shifted down 3, the K_ bits
	rrca
	rrca
	and	1Fh
	ld	c,a
	ld	a,(MATRIX+04h)		; row 2: D7 W, D3 S
	bit	7,a
	jr	z,.w
	set	0,c
.w:	bit	3,a
	jr	z,.s
	set	1,c
.s:	ld	a,(MATRIX+01h)		; row 0: D1 A, D4 D
	bit	1,a
	jr	z,.a
	set	2,c
.a:	bit	4,a
	jr	z,.d
	set	3,c
.d:	ld	a,c
	ld	(kb),a
	; falls into mixseed
	endif

; When the keys held change, the frame count goes into the random
; seed: the player's timing makes each game's saucers different. The
; self-playing builds' timing never changes, so their games do not.
mixseed:
	ld	hl,oldkb
	cp	(hl)
	ret	z
	ld	(hl),a
	ld	hl,(seed)
	ld	a,(fcount)
	xor	l
	ld	l,a
	ld	a,(fcount+1)
	xor	h
	ld	h,a
	or	l			; never 0, where xorshift would stay
	jr	nz,.s
	inc	l
.s:	ld	(seed),hl
	ret

	ifdef	AUTOPLAY
; Updates, keys; 0 starts again
	ifdef	DIE
APSCRIPT:
	db	200, K_FIRE
	db	0
	else
APSCRIPT:
	db	20, K_FIRE
	db	24, K_LEFT|K_FIRE
	db	30, K_RIGHT|K_FIRE
	db	12, K_UP|K_FIRE
	db	40, K_LEFT|K_FIRE
	db	10, 0
	db	20, K_DOWN|K_RIGHT
	db	50, K_RIGHT|K_FIRE
	db	16, K_UP|K_LEFT|K_FIRE
	db	30, K_FIRE
	db	16, K_DOWN
	db	0
	endif
app:	dw	APSCRIPT
apc:	db	0
apk:	db	0
	endif

; ---------------------------------------------------------------------
; The ship moves with the keys and fires a shot every FIREGAP updates
; while SPACE is held
ship:	ld	a,(OBJ+7)		; exploding: 3 frames, then gone
	or	a
	jr	z,.live
	inc	a
	ld	(OBJ+7),a
	cp	11
	jr	c,.boom
	xor	a
	ld	(OBJ+5),a
	ret
.boom:	sub	2			; 0-8: frame (count - 2) / 3
	ld	c,IMG_EXPL
.f3:	cp	3
	jr	c,.fi
	sub	3
	inc	c
	jr	.f3
.fi:	ld	a,c
	ld	(OBJ+4),a
	ret
.live:	ld	ix,OBJ
	ld	a,(kb)
	ifdef	STRESS
	or	K_FIRE
	endif
	ld	c,a
	ld	a,(ix+0)
	bit	2,c			; left
	jr	z,.r
	sub	SHIPV
	jr	nc,.r
	xor	a
.r:	bit	3,c			; right
	jr	z,.x
	add	a,SHIPV
	cp	XMAX+1
	jr	c,.x
	ld	a,XMAX
.x:	ld	(ix+0),a
	ld	a,(ix+1)
	bit	0,c			; up
	jr	z,.dn
	sub	SHIPVY
	cp	SHIPYMIN
	jr	nc,.dn
	ld	a,SHIPYMIN
.dn:	bit	1,c			; down
	jr	z,.y
	add	a,SHIPVY
	cp	YMAX+1
	jr	c,.y
	ld	a,YMAX
.y:	ld	(ix+1),a
	ld	a,(ix+6)		; the blink after a hit runs down
	or	a
	jr	z,.f
	dec	(ix+6)
.f:	ld	a,(firet)
	or	a
	jr	z,.ready
	dec	a
	ld	(firet),a
	ret
.ready:	bit	4,c
	ret	z
	ld	ix,OBJ+8*O_SHOT		; a free shot
	ld	b,NSHOT
	ld	de,8
.s:	ld	a,(ix+5)
	or	a
	jr	z,.new
	add	ix,de
	djnz	.s
	ret
.new:	ld	a,(OBJ+0)		; from the ship's nose: its dots at
	add	a,6			; x + 1 and 2, the ship's middle
	ld	(ix+0),a
	ld	a,(OBJ+1)
	sub	6
	ld	(ix+1),a
	ld	(ix+4),IMG_SHOT
	ld	(ix+5),1
	ifdef	STRESS
	ld	a,1
	else
	ld	a,FIREGAP
	endif
	ld	(firet),a
	ret

; Shots climb and go at the top
shots:	ld	ix,OBJ+8*O_SHOT
	ld	b,NSHOT
	ld	de,8
.l:	ld	a,(ix+5)
	or	a
	jr	z,.n
	ld	a,(ix+1)
	sub	SHOTV
	cp	YMIN
	jr	nc,.ok
	ld	(ix+5),0
	jr	.n
.ok:	ld	(ix+1),a
.n:	add	ix,de
	djnz	.l
	ret

; Saucers move by their pattern and go at the bottom: a drifter swings
; a dot an update, turning every 32 updates and at the edges; a swinger
; follows SINT round its middle; a diver steers a dot an update at the
; ship; a column goes straight down.
foes:	ld	ix,OBJ+8*O_FOE
	ld	b,NFOE
.l:	ld	a,(ix+5)
	or	a
	jp	z,.n
	inc	(ix+6)
	ld	a,(ix+7)
	or	a
	jr	z,.drift
	dec	a
	jr	z,.sine
	dec	a
	jr	z,.dive
	dec	a
	jp	z,.down			; a column
	dec	a
	jr	nz,.bomb
	ld	a,(ix+6)		; an explosion: a frame every 3
	cp	10			; updates, then gone
	jr	nc,.gone
	dec	a
	ld	c,IMG_EXPL
.f3:	cp	3
	jr	c,.fi
	sub	3
	inc	c
	jr	.f3
.fi:	ld	(ix+4),c
	jr	.down
.gone:	ld	(ix+5),0
	jp	.n
.bomb:	ld	a,(ix+6)		; a bomber: every 16 updates, when the
	and	15			; ship is within 24 dots across, a
	jr	nz,.drift		; bullet if one is free
	ld	a,(OBJ+5)
	or	a
	jr	z,.drift
	ld	a,(OBJ+0)
	sub	(ix+0)
	add	a,24
	cp	49
	call	c,ebfire
	jr	.drift
.dive:	ld	a,(OBJ+0)		; a diver
	cp	(ix+0)
	jr	z,.down
	jr	c,.dl
	inc	(ix+0)
	jr	.down
.dl:	dec	(ix+0)
	jr	.down
.sine:	ld	a,(ix+6)		; middle + SINT[2 age]
	add	a,a
	and	63
	ld	e,a
	ld	d,0
	ld	hl,SINT
	add	hl,de
	ld	a,(hl)
	add	a,(ix+2)
	ld	(ix+0),a
	jr	.down
.drift:	ld	a,(ix+6)
	and	31
	jr	nz,.mx
	ld	a,(ix+2)
	neg
	ld	(ix+2),a
.mx:	ld	a,(ix+0)
	add	a,(ix+2)
	cp	XMAX+1			; off either edge (below 0 is over F8h)
	jr	c,.xs
	ld	a,(ix+2)
	neg
	ld	(ix+2),a
	ld	a,(ix+0)
.xs:	ld	(ix+0),a
.down:	ld	a,(ix+1)
	add	a,(ix+3)
	cp	YMAX+1
	jr	c,.ys
	ld	(ix+5),0
	jr	.n
.ys:	ld	(ix+1),a
.n:	ld	de,8
	add	ix,de
	dec	b
	jp	nz,.l
	ret

; A bullet from the bomber at IX, if one is free. Keeps IX and B.
ebfire:	ld	iy,OBJ+8*O_EB
	ld	c,NEB
	ld	de,8
.s:	ld	a,(iy+5)
	or	a
	jr	z,.new
	add	iy,de
	dec	c
	jr	nz,.s
	ret
.new:	ld	a,(ix+0)		; under its middle
	add	a,6
	ld	(iy+0),a
	ld	a,(ix+1)
	add	a,8
	ld	(iy+1),a
	ld	(iy+4),IMG_EB
	ld	(iy+5),1
	ret

; Bullets fall and go at the bottom. The -DSTRESS build keeps them all
; falling from the top, at random places across.
ebullets:
	ld	ix,OBJ+8*O_EB
	ld	b,NEB
.l:	ld	a,(ix+5)
	or	a
	jr	nz,.mv
	ifdef	STRESS
	call	rnd
.m:	cp	XMAX+1
	jr	c,.x
	sub	XMAX+1
	jr	.m
.x:	ld	(ix+0),a
	ld	(ix+1),YMIN
	ld	(ix+4),IMG_EB
	ld	(ix+5),1
	endif
	jr	.n
.mv:	ld	a,(ix+1)
	add	a,EBV
	cp	YMAX+8
	jr	c,.y
	ld	(ix+5),0
	jr	.n
.y:	ld	(ix+1),a
.n:	ld	de,8
	add	ix,de
	djnz	.l
	ret

; ---------------------------------------------------------------------
; Sound: the beeper has one tone, about 2 kHz for about 1/15 second, so
; a sound is a rhythm of beeps. A sound is a list of the updates to wait
; before each beep, 0 at its end; a new sound takes over from the last.
sound:	ld	(sndp),hl
	ld	a,(hl)
	ld	(sndc),a
	ret

sndtick:
	ld	hl,(sndp)
	ld	a,h
	or	l
	ret	z
	ld	a,(sndc)
	dec	a
	ld	(sndc),a
	ret	nz
	ld	(BEEP),a
	inc	hl
	ld	a,(hl)
	ld	(sndc),a
	or	a
	jr	nz,.on
	ld	hl,0
.on:	ld	(sndp),hl
	ret

SND_HIT:	db	1, 0			; a saucer shot down
SND_SHIP:	db	1, 3, 3, 0		; a ship lost
SND_OVER:	db	1, 4, 4, 4, 4, 0	; the last ship lost
SND_BOSS:	db	1, 3, 3, 3, 3, 3, 3, 0	; the mothership gone

; The waves. When a wave has sent all its saucers and none is left, a
; pause, then the next from WAVES, round and round. A wave sends a
; saucer every gap updates, when a slot is free and both frames had at
; least 16 lines to spare last update, so a slower machine runs fewer.
; The -DSTRESS build sends drifters every update instead.
spawn:
	ifdef	STRESS
	call	freefoe
	ret	nz
	call	rnd
	ld	c,a
	ld	b,P_DRIFT
	jp	spawn1
	else
	ld	a,(over)
	or	a
	ret	nz
	ld	a,(wleft)
	or	a
	jr	nz,.go
	ld	a,(bact)		; the wave is out: wait for the
	or	a			; mothership and the last saucer
	ret	nz
	ld	ix,OBJ+8*O_FOE
	ld	b,NFOE
	ld	de,8
.any:	ld	a,(ix+5)
	or	a
	ret	nz
	add	ix,de
	djnz	.any
	ld	hl,wpause
	ld	a,(hl)
	or	a
	jr	z,.next
	dec	(hl)
	ret
.next:	ld	(hl),WAVEPAUSE
	ld	a,(wi)			; after the last wave the mothership
	cp	NWAVES
	jr	c,.wv
	xor	a
	ld	(wi),a
	ld	hl,wave
	inc	(hl)
	jp	bossgo
.wv:	ld	a,(wi)			; WAVES[wi]: count, gap, pattern, dy, x
	ld	l,a
	ld	h,0
	add	hl,hl
	add	hl,hl
	add	a,l			; * 5
	ld	l,a
	ld	de,WAVES
	add	hl,de
	ld	de,wleft
	ld	bc,5
	ldir
	xor	a
	ld	(wtimer),a
	ld	hl,wi
	inc	(hl)
	ld	hl,wave
	inc	(hl)
	ret
.go:	ld	hl,wtimer
	ld	a,(hl)
	or	a
	jr	z,.due
	dec	(hl)
	ret
.due:	ld	a,(la)
	cp	16
	ret	c
	ld	a,(lb)
	cp	16
	ret	c
	call	freefoe
	ret	nz
	ld	a,(wgap)
	ld	(wtimer),a
	ld	hl,wleft
	dec	(hl)
	ld	a,(wx)
	or	a
	jr	nz,.x
	call	rnd
.x:	ld	c,a
	ld	a,(wpat)
	ld	b,a
	ld	a,(wdy)
	ld	(ix+3),a
	jr	spawn1
	endif

; IX = a free saucer slot, NZ if none
freefoe:
	ld	ix,OBJ+8*O_FOE
	ld	b,NFOE
	ld	de,8
.s:	ld	a,(ix+5)
	or	a
	ret	z
	add	ix,de
	djnz	.s
	or	1
	ret

; A saucer at IX, across about C, pattern B, at the top. A swinger's
; middle is kept 40 dots in from either edge, its swing being 40.
spawn1:	ld	a,c
.m:	cp	XMAX+1
	jr	c,.x
	sub	XMAX+1
	jr	.m
.x:	ld	c,a
	ld	(ix+0),a
	ld	(ix+1),YMIN
	ld	a,IMG_FOE
	ld	(ix+4),a
	ld	a,b
	cp	P_BOMB
	jr	nz,.img
	ld	(ix+4),IMG_BOMBER
.img:	ld	(ix+5),1
	ld	(ix+6),0
	ld	(ix+7),b
	ifdef	STRESS
	call	rnd
	and	1
	inc	a
	ld	(ix+3),a
	endif
	ld	a,b
	cp	P_SINE
	jr	nz,.dx
	ld	a,c			; a swinger: its middle 40 to 136
	cp	40
	jr	nc,.lo
	ld	a,40
.lo:	cp	XMAX-40+1
	jr	c,.mid
	ld	a,XMAX-40
.mid:	ld	(ix+2),a
	ld	(ix+0),a
	ret
.dx:	call	rnd			; a drifter: one way or the other
	ld	c,1
	bit	0,a
	jr	z,.d
	ld	c,-1
.d:	ld	(ix+2),c
	ret

; count, gap, pattern, dy, x (0 at random)
WAVES:
	db	5, 24, P_DRIFT, 1, 0
	db	5, 12, P_LINE, 2, 40
	db	3, 40, P_BOMB, 1, 0
	db	5, 16, P_SINE, 1, 88
	db	4, 30, P_DIVE, 2, 0
	db	5, 12, P_LINE, 2, 136
	db	3, 36, P_BOMB, 1, 0
	db	6, 14, P_SINE, 1, 60
	db	5, 20, P_DIVE, 2, 0
	db	8, 12, P_DRIFT, 2, 0
NWAVES		equ	($-WAVES)/5

; Points for a saucer by its pattern, BCD, low byte first
PATPTS:	db	00h, 01h		; drifter 100
	db	50h, 01h		; swinger 150
	db	00h, 02h		; diver 200
	db	00h, 01h		; column 100
	db	00h, 00h		; an explosion, nothing
	db	00h, 03h		; bomber 300

; ---------------------------------------------------------------------
; The mothership, the final boss, after the last wave: four 16-dot
; sprites, 32 x 25 dots, (bx, by) its top left. It comes down to BOSSY,
; then patrols side to side, dropping a bullet every BOSSGAP updates.
; It takes BOSSHP hits, 50 points each, blinking at each; then it
; explodes in four, for 5000 points and 1000 for each ship left, and the
; game is won: MISSION COMPLETE, then the high scores.
bossgo:	ld	a,1
	ld	(bact),a
	ld	(bdx),a
	ld	a,72
	ld	(bx),a
	ld	a,YMIN
	ld	(by),a
	ld	a,BOSSHP
	ld	(bhp),a
	ld	a,BOSSGAP
	ld	(bfire),a
	xor	a
	ld	(bflash),a
	ret

boss:	ld	a,(bact)
	or	a
	ret	z
	ld	hl,bflash
	ld	a,(hl)
	or	a
	jr	z,.f
	dec	(hl)
.f:	ld	a,(by)			; down to its line first
	cp	BOSSY
	jr	nc,.pat
	inc	a
	ld	(by),a
	ret
.pat:	ld	a,(bdx)			; side to side, 32 dots wide
	ld	hl,bx
	add	a,(hl)
	cp	XMAX-16+1
	jr	c,.x
	ld	a,(bdx)
	neg
	ld	(bdx),a
	ld	a,(hl)
.x:	ld	(hl),a
	ld	hl,bfire
	dec	(hl)
	ret	nz
	ld	(hl),BOSSGAP
	ld	a,(bx)			; a bullet from under its middle
	add	a,8
	ld	(btmp),a
	ld	a,(by)
	add	a,14
	ld	(btmp+1),a
	ld	ix,btmp
	jp	ebfire

; The mothership hit by the shot at IY
bosshit:
	ld	(iy+5),0
	ld	a,4
	ld	(bflash),a
	ld	hl,SND_HIT
	call	sound
	ld	a,50h			; 50 points a hit
	call	addlo
	ld	hl,bhp
	dec	(hl)
	ret	nz
	ld	hl,bkills
	inc	(hl)
	xor	a			; gone: four explosions, 5000 points,
	ld	(bact),a		; 1000 for each ship left, and the
	ld	a,50h			; game is won
	call	addhi
	ld	a,(ships)
	or	a
	jr	z,.sh0
	ld	b,a
.sh:	ld	a,10h
	call	addhi
	djnz	.sh
.sh0:
	xor	a
	ld	(overt),a
	ld	(overup),a
	inc	a
	ld	(over),a
	ld	(won),a
	ld	(banreq),a		; and MISSION COMPLETE over the ground
	ld	ix,OBJ+8*O_FOE
	ld	de,BOOMXY
	ld	b,4
.b:	ld	a,(de)
	ld	hl,bx
	add	a,(hl)
	ld	(ix+0),a
	inc	de
	ld	a,(de)
	ld	hl,by
	add	a,(hl)
	ld	(ix+1),a
	inc	de
	ld	(ix+3),0
	ld	(ix+5),1
	call	boom
	push	de
	ld	de,8
	add	ix,de
	pop	de
	djnz	.b
	ld	hl,SND_BOSS
	jp	sound

; The score + A, BCD: addlo A tens and units, addhi A hundreds
addlo:	ld	hl,score
	add	a,(hl)
	daa
	ld	(hl),a
	inc	hl
	ld	a,(hl)
	adc	a,0
	jr	addh2
addhi:	ld	hl,score+1
	add	a,(hl)
addh2:	daa
	ld	(hl),a
	inc	hl
	ld	a,(hl)
	adc	a,0
	daa
	ld	(hl),a
	ret

	assert	NFOE >= 4
BOOMXY:	db	0, 0, 16, 0, 0, 12, 16, 12	; its explosions
BOSSXY:	db	0, 0, 16, 0, 0, 16, 16, 16	; its four sprites

; ---------------------------------------------------------------------
; What hits what, by boxes in dots: a shot's dots are x+1..x+2,
; y+1..y+6; a saucer's x..x+15, y+2..y+12, a bomber's x..x+15,
; y+1..y+8; the ship's x+2..x+13, y+2..y+14; a bullet's x+1..x+3,
; y+1..y+3. Explosions hit nothing. A shot and a saucer that touch: the
; shot goes, the saucer explodes, its points are scored, a beep. A
; saucer or a bullet that touches the ship, unless it blinks: the
; saucer explodes or the bullet goes, and the ship is hit (shiphit).
; Once the game is over, won or lost, nothing hits anything.
hit:	ld	a,(over)
	or	a
	ret	nz
	ld	iy,OBJ+8*O_SHOT
	ld	b,NSHOT
.sh:	ld	a,(iy+5)
	or	a
	jp	z,.nsh
	push	bc
	ld	a,(iy+0)		; C shot x + 2, L shot y + 5, once a shot
	add	a,2
	ld	c,a
	ld	a,(iy+1)
	add	a,5
	ld	l,a
	ld	ix,OBJ+8*O_FOE
	ld	b,NFOE
.f:	ld	a,(ix+5)
	or	a
	jr	z,.nf
	ld	a,(ix+7)
	cp	P_BOOM
	jr	z,.nf
	ld	a,c			; across: shot x + 2 - foe x in 0..16
	sub	(ix+0)
	cp	17
	jr	nc,.nf
	ld	a,l			; down: shot y + 5 - foe y in 1..16 for a
	sub	(ix+1)			; saucer, 0..12 for a bomber
	cp	17
	jr	nc,.nf
	dec	a			; 1..12 hits either
	cp	12
	jr	c,.fh
	ld	e,a			; FFh (0) hits only a bomber, 12..15
	ld	a,(ix+4)		; (13..16) only a saucer
	cp	IMG_BOMBER
	jr	z,.fb
	inc	e
	jr	z,.nf
	jr	.fh
.fb:	inc	e
	jr	nz,.nf
.fh:
	ifdef	STRESS			; every test made, nothing ever hit
	jr	.nf
	endif
	ld	(iy+5),0
	ld	hl,hits
	inc	(hl)
	ld	a,(ix+7)		; its points
	add	a,a
	ld	e,a
	ld	d,0
	ld	hl,PATPTS
	add	hl,de
	ld	a,(score)
	add	a,(hl)
	daa
	ld	(score),a
	inc	hl
	ld	a,(score+1)
	adc	a,(hl)
	daa
	ld	(score+1),a
	ld	a,(score+2)
	adc	a,0
	daa
	ld	(score+2),a
	call	boom
	ld	hl,SND_HIT
	call	sound
	pop	bc
	jr	.nsh
.nf:	ld	de,8
	add	ix,de
	djnz	.f
	pop	bc
.nsh:	ld	de,8
	add	iy,de
	dec	b
	jp	nz,.sh
	ld	a,(bact)		; the shots and the mothership: its box
	or	a			; x..x+31, y+2..y+26
	jr	z,.nob
	ld	iy,OBJ+8*O_SHOT
	ld	b,NSHOT
.bs:	ld	a,(iy+5)
	or	a
	jr	z,.nbs
	ld	a,(iy+0)		; across: shot x + 2 - bx in 0..32
	add	a,2
	ld	hl,bx
	sub	(hl)
	cp	33
	jr	nc,.nbs
	ld	a,(iy+1)		; down: shot y + 4 - by in 0..29
	add	a,4
	ld	hl,by
	sub	(hl)
	cp	30
	jr	nc,.nbs
	ifdef	STRESS
	jr	.nbs
	endif
	call	bosshit
	ld	a,(bact)		; gone: the game won, nothing more hit
	or	a
	ret	z
.nbs:	ld	de,8
	add	iy,de
	djnz	.bs
.nob:
	ld	a,(OBJ+5)		; the ship, unless it is gone, exploding
	or	a			; or blinking
	ret	z
	ld	a,(OBJ+7)
	or	a
	ret	nz
	ld	a,(OBJ+6)
	or	a
	ret	nz
	ld	ix,OBJ+8*O_FOE
	ld	b,NFOE
.g:	ld	a,(ix+5)
	or	a
	jr	z,.ng
	ld	a,(ix+7)
	cp	P_BOOM
	jr	z,.ng
	ld	a,(OBJ+0)		; across: ship x + 13 - foe x in 0..26
	add	a,13
	sub	(ix+0)
	cp	27
	jr	nc,.ng
	ld	a,(OBJ+1)		; down: ship y + 13 - foe y in 1..23 for a
	add	a,13			; saucer, 0..19 for a bomber
	sub	(ix+1)
	cp	24
	jr	nc,.ng
	dec	a			; 1..19 hits either
	cp	19
	jr	c,.gh
	ld	e,a			; FFh (0) hits only a bomber, 19..22
	ld	a,(ix+4)		; (20..23) only a saucer
	cp	IMG_BOMBER
	jr	z,.gb
	inc	e
	jr	z,.ng
	jr	.gh
.gb:	inc	e
	jr	nz,.ng
.gh:
	ifdef	STRESS
	jr	.ng
	endif
	call	boom
	jp	shiphit
.ng:	ld	de,8
	add	ix,de
	djnz	.g
	ld	a,(bact)		; the mothership: ship x + 13 - bx in
	or	a			; 0..42, ship y + 12 - by in 0..36
	jr	z,.nbb
	ld	a,(OBJ+0)
	add	a,13
	ld	hl,bx
	sub	(hl)
	cp	43
	jr	nc,.nbb
	ld	a,(OBJ+1)
	add	a,12
	ld	hl,by
	sub	(hl)
	cp	37
	jr	nc,.nbb
	jp	shiphit
.nbb:	ld	ix,OBJ+8*O_EB		; and the bullets
	ld	b,NEB
.b:	ld	a,(ix+5)
	or	a
	jr	z,.nb
	ld	a,(ix+0)		; across: bullet x + 1 - ship x in 0..13
	inc	a
	ld	hl,OBJ+0
	sub	(hl)
	cp	14
	jr	nc,.nb
	ld	a,(ix+1)		; down: bullet y + 1 - ship y in 0..14
	inc	a
	ld	hl,OBJ+1
	sub	(hl)
	cp	15
	jr	nc,.nb
	ifdef	STRESS
	jr	.nb
	endif
	ld	(ix+5),0
	jp	shiphit
.nb:	ld	de,8
	add	ix,de
	djnz	.b
	ret

; The saucer at IX explodes where it is
boom:	ld	(ix+7),P_BOOM
	ld	(ix+6),0
	ld	(ix+4),IMG_EXPL
	ret

; The ship is hit: a ship less and it blinks, beeps; or with none left
; it explodes and the game is over
shiphit:
	ld	a,FLASH
	ld	(OBJ+6),a
	ld	hl,ships
	dec	(hl)
	ld	hl,SND_SHIP
	jp	nz,sound
	xor	a			; none left
	ld	(OBJ+6),a
	ld	(overt),a
	ld	(overup),a
	inc	a
	ld	(over),a
	ld	(OBJ+7),a		; the ship explodes
	ld	a,IMG_EXPL
	ld	(OBJ+4),a
	ld	hl,SND_OVER
	jp	sound

; ---------------------------------------------------------------------
; DRAW: what to merge this update, 4 bytes each, x, y, image: the
; saucers, the ship, which while it blinks shows every other 2 updates,
; then the shots, last so that the split between the frames can fall
; among them, the smallest steps. drawa of them go in frame A, the rest
; in B, split by cost so that the frames come out even, each frame's
; own work counted too (FIXA, FIXB).
drawlist:
	ld	de,DRAW
	ld	c,0			; how many
	ld	b,0			; their cost
	ld	ix,OBJ+8*O_FOE
	ld	l,NFOE
	ld	h,2
	call	dladd
	ld	a,(bact)		; the mothership's four, unless it blinks
	or	a
	jr	z,.nb
	ld	a,(bflash)
	and	2
	jr	nz,.nb
	push	bc
	ld	hl,BOSSXY
	ld	b,4
	ld	c,IMG_BOSS
.bp:	ld	a,(bx)
	add	a,(hl)
	ld	(de),a
	inc	hl
	inc	de
	ld	a,(by)
	add	a,(hl)
	ld	(de),a
	inc	hl
	inc	de
	ld	a,c
	ld	(de),a
	inc	de
	inc	de
	inc	c
	djnz	.bp
	pop	bc
	ld	a,c
	add	a,4
	ld	c,a
.nb:	ld	a,(OBJ+6)
	and	2
	jr	nz,.sh
	ld	ix,OBJ
	ld	l,1
	ld	h,2
	call	dladd
.sh:	ld	ix,OBJ+8*O_EB
	ld	l,NEB
	ld	h,1
	call	dladd
	ld	ix,OBJ+8*O_SHOT
	ld	l,NSHOT
	ld	h,1
	call	dladd
.split:	ld	a,c
	ld	(drawn),a
	ld	(drawa),a
	or	a
	ret	z
	ld	b,a			; each entry's cost into its 4th byte
	ld	ix,DRAW
	ld	hl,0			; their sum
	ld	c,0			; their cells
.e:	call	cost
	add	a,l
	ld	l,a
	jr	nc,.e1
	inc	h
.e1:	ld	de,4
	add	ix,de
	djnz	.e
	ld	a,c			; B's own work: FIXB + 1.5 a cell
	srl	a
	add	a,c
	add	a,FIXB
	ld	e,a
	ld	d,0
	add	hl,de			; A's share: (B's own + all - FIXA) / 2
	ld	de,FIXA
	or	a
	sbc	hl,de
	jr	nc,.t
	ld	hl,0
.t:	srl	h
	rr	l
	ex	de,hl			; DE = A's share, HL = A's so far
	ld	hl,0
	ld	ix,DRAW
	ld	a,(drawn)
	ld	b,a
	ld	c,0
.w:	ld	a,(ix+3)		; A takes the next while half of it
	srl	a			; still fits in A's share
	push	hl
	add	a,l
	ld	l,a
	jr	nc,.w1
	inc	h
.w1:	or	a
	sbc	hl,de
	pop	hl
	jr	nc,.done
	ld	a,(ix+3)
	add	a,l
	ld	l,a
	jr	nc,.w2
	inc	h
.w2:	inc	c
	push	de
	ld	de,4
	add	ix,de
	pop	de
	djnz	.w
.done:	ld	a,c
	ld	(drawa),a
	ret

; The cost of merging the entry at IX, in units of about 100 T, into its
; 4th byte and A, from COSTTAB by its image, shift and pair of lines in
; the row, the more of the two:
; 7, and 5 a row and 5 a cell (tools/gfx.py). Adds its cells to C.
; Keeps B and HL.
cost:	ld	a,(ix+2)		; image * 32 + shift * 4 + line / 2,
	ld	d,a			; over 2 pages
	rrca
	rrca
	rrca
	and	0E0h
	ld	e,a
	ld	a,(ix+0)
	and	7
	add	a,a
	add	a,a
	or	e
	ld	e,a
	ld	a,(ln)			; (y - L) / 2, keeping HL
	neg
	add	a,(ix+1)
	and	7
	srl	a
	or	e
	ld	e,a
	ld	a,d			; the page: image / 8
	rrca
	rrca
	rrca
	and	1
	add	a,high COSTTAB
	ld	d,a
	inc	d			; the cells, 2 pages on
	inc	d
	ld	a,(de)
	add	a,c
	ld	c,a
	dec	d
	dec	d
	ld	a,(de)
	ld	(ix+3),a
	ret

; L objects from IX, each costing H, onto DE when alive
dladd:	ld	a,(ix+5)
	or	a
	jr	z,.na
	ld	a,(ix+0)
	ld	(de),a
	inc	de
	ld	a,(ix+1)
	ld	(de),a
	inc	de
	ld	a,(ix+4)
	ld	(de),a
	inc	de
	inc	de
	inc	c
	ld	a,b
	add	a,h
	ld	b,a
.na:	push	de
	ld	de,8
	add	ix,de
	pop	de
	dec	l
	jr	nz,dladd
	ret

; An 8-bit pseudo-random number in A: two steps of John Metcalf's
; 16-bit xorshift (shifts 7, 9, 8, period 65535), which spreads a
; small change in the seed over the whole number. Keeps all but A, F.
rnd:	push	hl
	ld	hl,(seed)
	call	.step
	call	.step
	ld	(seed),hl
	ld	a,l
	pop	hl
	ret
.step:	ld	a,h
	rra
	ld	a,l
	rra
	xor	h
	ld	h,a
	ld	a,l
	rra
	ld	a,h
	rra
	xor	l
	ld	l,a
	xor	h
	ld	h,a
	ret

seed:	dw	0ACE1h
kb:	db	0
oldkb:	db	0
firet:	db	0
hits:	db	0
score:	ds	3			; BCD, low byte first
ships:	db	0
wave:	db	0			; the wave on the screen, from 1
over:	db	0			; the game is over
overt:	db	0			; updates since
overup:	db	0			; SPACE let go since
wi:	db	0			; the next wave in WAVES
wpause:	db	0
wtimer:	db	0
wleft:	db	0			; this wave: saucers still to send,
wgap:	db	0			; updates between them, pattern,
wpat:	db	0			; lines down an update, across (0 at
wdy:	db	0			; random), as in WAVES
wx:	db	0
bact:	db	0			; the mothership: on, top left, dx,
bx:	db	0			; hits left, blinking, updates to its
by:	db	0			; next bullet
bdx:	db	0
bhp:	db	0
bflash:	db	0
bfire:	db	0
btmp:	db	0, 0			; its bullet's place, for ebfire
bkills:	db	0			; motherships destroyed, for the tests
won:	db	0			; the game ended with the mothership
banreq:	db	0			; the banner wanted
banst:	db	0			; the banner: 0 none, 1 the pool cut,
					; 2 its top free, 3 shown
sndp:	dw	0			; the sound playing, 0 none
sndc:	db	0			; updates to its next beep
drawn:	db	0
drawa:	db	0

; The boot sector. Track 0 sector 0, loaded by the boot ROM to
; 0400h and run there with the I/O block at 0000h, IY = MLATCH and AF'
; as the ROM's READ wants them. It reads the program to 1000h and its
; data to 9000h in A2, one sector a call, moves the I/O block to 7000h
; and starts it. The same
; loader as Maximum-80's (software/demo/src/boot.asm), with no message:
; the program is small and loads in about a second.
; tools/mkdisk.py sets the sectors a track at offset 2.

	org	0400h
boot:	jr	bstart
bspt:	db	8			; sectors a track
bprog:	db	PROGSEC			; the program's sectors, for the tools
	assert	bspt == 0402h

bstart:	di
	ld	sp,0B00h		; RAM900, bank A whatever the PIO shows
	ld	a,PIO_A2
	ld	(B_PIODA),a
	ld	de,0			; track
	ld	b,1			; sector
	ld	c,PROGSEC		; the program to 1000h
	ld	hl,1000h
	call	bload
	ld	c,DATASEC		; then the data to A2
	ld	hl,DATA
	call	bload
	ld	a,VL_FONT		; the I/O block to 7000h
	ld	(B_VLATCH),a
	ld	(VLATCH),a		; and its RAM copy at the new place
	jp	main

; C sectors to HL from track DE, sector B, on
bload:	push	bc
	push	de
	ld	c,b			; first and last sector the same
	xor	a			; head 0
	call	ROMREAD			; HL comes back past the sector
	pop	de
	pop	bc
	inc	b
	ld	a,(bspt)
	cp	b
	jr	nz,bnext
	ld	b,0			; next track, from sector 0
	inc	de
bnext:	dec	c
	jr	nz,bload
	ret

	assert	$ <= 0600h
	block	0600h-$,0

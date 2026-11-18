; 80-Force's addresses. The I/O block sits at 7000h once booted,
; so the program, its tables and the stack are in A1 below it, and A2
; shows at 8000h-FFFFh, unused so far.

BLK		equ	7000h
FONTWIN		equ	BLK		; the 1K window
VLATCH		equ	BLK+7DCh
BAUDA		equ	BLK+7D0h
CRTREG		equ	BLK+7E0h
CRTBYT		equ	BLK+7E1h
SYSFLG		equ	BLK+7E1h	; bit 6 the CRTC's display enable
SIODA		equ	BLK+7E4h
SIOCA		equ	BLK+7E5h
BEEP		equ	BLK+7F8h	; any write beeps
PIODA		equ	BLK+7FCh	; bank select, bits 7-4
MATRIX		equ	BLK+800h	; the keys, row r at + (1 << r)
VIDLO		equ	BLK+0C00h	; video RAM 000h-3FFh

VL_VIDEO	equ	72h		; block at 7000h, window video RAM 400h-7FFh
VL_FONT		equ	74h		; window font RAM 1, codes 00h-7Fh
VL_FONT2	equ	76h		; window font RAM 2, codes 80h-BFh
VL_WIDE		equ	08h		; 40 columns, cells 16 dots wide

PIO_A2		equ	40h		; A1 low, A2 high

; The boot ROM's, while the block is at 0000h
ROMREAD		equ	0003h
B_VLATCH	equ	07DCh
B_PIODA		equ	07FCh

STACK		equ	6F00h

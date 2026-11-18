#!/usr/bin/env python3
"""Count the beeps in a sound recorded by the emulator's -s.

Usage: countbeeps.py SOUND.wav

A beep is a run of sound with at least 10 ms of silence before it.
Prints how many.
"""
import sys
import wave


def main():
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    w = wave.open(sys.argv[1])
    rate, width = w.getframerate(), w.getsampwidth()
    data = w.readframes(w.getnframes())
    n = len(data) // width
    quiet = int(rate * 0.010)
    beeps, still, on = 0, quiet, False
    for i in range(n):
        v = int.from_bytes(data[i * width:(i + 1) * width], 'little', signed=width > 1)
        if v != 0 and (width > 1 or v != 128):
            if not on and still >= quiet:
                beeps += 1
            on, still = True, 0
        else:
            still += 1
            if still >= quiet:
                on = False
    print(beeps)


if __name__ == '__main__':
    main()

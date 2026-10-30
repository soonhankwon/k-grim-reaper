#!/usr/bin/env python3
"""Generate original, deterministic mono test effects; no external samples."""
from math import sin, pi, exp
from pathlib import Path
import random
import struct
import wave

OUT = Path(__file__).resolve().parent.parent / 'game/assets/audio'
RATE = 22050
OUT.mkdir(parents=True, exist_ok=True)

def write(name, seconds, sample):
    samples = [max(-1.0, min(1.0, sample(i / RATE, i))) for i in range(int(RATE * seconds))]
    with wave.open(str(OUT / name), 'wb') as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(RATE)
        output.writeframes(b''.join(struct.pack('<h', round(v * 24000)) for v in samples))

rng = random.Random(1742)
write('ink-hit-v1.wav', .23, lambda t, i: .48 * exp(-t * 24) * (rng.random() * 2 - 1) + .32 * sin(2*pi*(115*t - 130*t*t)) * exp(-t*19))
write('seal-drum-v1.wav', .60, lambda t, i: .65 * sin(2*pi*(83*t - 45*t*t)) * exp(-t*7) + .15 * (rng.random()*2-1) * exp(-t*28))
wind_state = [0.0]
def wind(t, _i):
    wind_state[0] = .988 * wind_state[0] + .012 * (rng.random()*2-1)
    return wind_state[0] * 1.6 * min(1.0, t*5) * max(0.0, (1.6-t)/1.6)
write('bamboo-wind-v1.wav', 1.6, wind)
snap_rng = random.Random(2026)
write('item-snap-v1.wav', .14, lambda t, i: .38 * (snap_rng.random()*2-1) * exp(-t*65) + .32 * sin(2*pi*(740*t - 1200*t*t)) * exp(-t*30) + .18 * sin(2*pi*1120*t) * exp(-t*42))
write('guard-chime-v1.wav', .26, lambda t, i: .32 * sin(2*pi*530*t) * exp(-t*15) + .23 * sin(2*pi*810*t) * exp(-t*20) + .12 * sin(2*pi*1190*t) * exp(-t*25))

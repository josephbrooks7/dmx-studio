"""Writes a test song with known answers: 2 s silence, 16 bars quiet intro (hats + soft kick),
16 bars loud section (kick + snare + bass + hats) at 128 BPM, then 3 s silence. Tagged title/artist."""
import math, random, struct, sys, wave
sr = 44100; bpm = 128.0; beat = 60 / bpm
random.seed(1)
lead = 2.0; intro_bars = 16; loud_bars = 16; tail = 3.0
dur = lead + (intro_bars + loud_bars) * 4 * beat + tail
n = int(dur * sr); x = [0.0] * n
def add(t0, gen, length, amp):
    i0 = int(t0 * sr)
    for i in range(int(length * sr)):
        if i0 + i < n: x[i0 + i] += amp * gen(i / sr)
kick = lambda t: math.sin(2 * math.pi * (50 + 80 * math.exp(-t * 40)) * t) * math.exp(-t * 12)
snare = lambda t: (random.uniform(-1, 1) * 0.7 + 0.3 * math.sin(2 * math.pi * 190 * t)) * math.exp(-t * 18)
hat = lambda t: random.uniform(-1, 1) * math.exp(-t * 90)
bass = lambda t: math.sin(2 * math.pi * 55 * t) * min(1, t * 50) * math.exp(-t * 3)
t = lead
for b in range((intro_bars + loud_bars) * 4):
    loud = b >= intro_bars * 4
    amp = 1.0 if loud else 0.25
    add(t, kick, 0.35, 0.9 * amp)
    if loud and b % 2 == 1: add(t, snare, 0.25, 0.5)
    if loud: add(t, bass, 0.4, 0.35)
    add(t + beat / 2, hat, 0.05, 0.15 * (1 if loud else 0.6))
    t += beat
peak = max(abs(v) for v in x) or 1
pcm = b"".join(struct.pack("<h", int(max(-1, min(1, v / peak * 0.9)) * 32767)) for v in x)
out = sys.argv[1]
w = wave.open(out, "wb"); w.setnchannels(1); w.setsampwidth(2); w.setframerate(sr); w.writeframes(pcm); w.close()
# add RIFF LIST/INFO tags (title + artist) so the tag reader is tested too
def chunk(cid, data):
    if len(data) % 2: data += b"\0"
    return cid + struct.pack("<I", len(data)) + data
info = b"INFO" + chunk(b"INAM", b"Test Groove\0") + chunk(b"IART", b"Red Velvet Test\0")
raw = open(out, "rb").read()
body = raw[12:] + chunk(b"LIST", info)
open(out, "wb").write(b"RIFF" + struct.pack("<I", 4 + len(body)) + b"WAVE" + body)
print(f"wrote {out}: {dur:.1f}s, beats start at {lead:.3f}s every {beat:.4f}s, loud from {lead + intro_bars*4*beat:.2f}s")

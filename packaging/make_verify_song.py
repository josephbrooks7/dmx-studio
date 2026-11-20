"""Verification song with known answers (written next to it as JSON):
  A  bass-heavy: kicks + long sustained bass notes (must NOT count as kicks), one kick off the grid
  B  sparse vocal: sung phrases (harmonics + formants + vibrato), no drums
  C  drums + vocals: kick, snare, hats and singing together
100 BPM, 8 bars each, 1 s silence at both ends."""
import json, math, random, struct, sys, wave
import numpy as np
sr = 44100; bpm = 100.0; beat = 60 / bpm; bar = 4 * beat
rng = np.random.default_rng(7)
lead = 1.0; bars = 8
dur = lead + 3 * bars * bar + 1.0
x = np.zeros(int(dur * sr))
parts = {k: np.zeros((len(x), 2)) for k in ("drums", "bass", "vocals", "other")}   # stereo ground-truth stems
PAN = {"drums": (0.5, 0.5), "bass": (0.5, 0.5), "vocals": (0.5, 0.5), "other": (0.8, 0.2)}
cur = ["drums"]
truth = {"kick": [], "snare": [], "hat": [], "vocal": [], "sections": {}}

def put(t0, sig, amp):
    i0 = int(t0 * sr); i1 = min(len(x), i0 + len(sig)); x[i0:i1] += amp * sig[: i1 - i0]
    gl, gr = PAN[cur[0]]; parts[cur[0]][i0:i1, 0] += gl * 2 * amp * sig[: i1 - i0]; parts[cur[0]][i0:i1, 1] += gr * 2 * amp * sig[: i1 - i0]
def put_as(kind, t0, sig, amp):
    cur[0] = kind; put(t0, sig, amp); cur[0] = "drums"

def tt(length): return np.arange(int(length * sr)) / sr
def kick():
    t = tt(0.4); f = 48 + 90 * np.exp(-t * 35); ph = 2 * np.pi * np.cumsum(f) / sr
    click = rng.uniform(-1, 1, len(t)) * np.exp(-t * 400) * 0.3
    return (np.sin(ph) * np.exp(-t * 11) + click)
def snare():
    t = tt(0.3); n = rng.uniform(-1, 1, len(t))
    return (0.65 * n * np.exp(-t * 16) + 0.45 * np.sin(2 * np.pi * 200 * t) * np.exp(-t * 22))
def hat():
    t = tt(0.06); n = rng.uniform(-1, 1, len(t) + 2)
    hp = (n[:-2] - 2 * n[1:-1] + n[2:]) / 4
    return hp * np.exp(-t * 80)
def bass_note(f0, length):
    t = tt(length); env = np.minimum(1, t / 0.06) * np.minimum(1, (length - t) / 0.1)
    f = f0 * (1 + 0.04 * np.sin(2 * np.pi * 0.5 * t))
    return np.sin(2 * np.pi * np.cumsum(f) / sr) * env
FORM = {"a": (730, 1090, 2440), "e": (530, 1840, 2480), "i": (270, 2290, 3010), "o": (570, 840, 2410), "u": (300, 870, 2240)}
def sing(length, f0, vowels):
    t = tt(length); out = np.zeros(len(t))
    vib = 1 + 0.012 * np.sin(2 * np.pi * 5.5 * t)
    ph = 2 * np.pi * np.cumsum(f0 * vib) / sr
    seg = len(t) // len(vowels)
    for vi, v in enumerate(vowels):
        a, b = vi * seg, (vi + 1) * seg if vi < len(vowels) - 1 else len(t)
        for h in range(1, 24):
            fh = f0 * h
            if fh > 5000: break
            g = sum(math.exp(-((fh - F) / 120) ** 2) for F in FORM[v]) + 0.05
            out[a:b] += g / h ** 0.6 * np.sin(h * ph[a:b])
    syll = 0.65 + 0.35 * np.abs(np.sin(np.pi * t * 3.0))
    env = np.minimum(1, t / 0.08) * np.minimum(1, (length - t) / 0.15)
    return out * syll * env / 6

t = lead
# ---- A: bass-heavy
truth["sections"]["bass_heavy"] = [t, t + bars * bar]
for b in range(bars * 4):
    bt = t + b * beat
    if b % 2 == 0:
        kt = bt + (0.06 if b == 10 else 0.0)        # one kick deliberately off the grid
        put(kt, kick(), 0.9); truth["kick"].append(kt)
    put_as("bass", bt + beat / 2, bass_note(41 + (b % 4) * 6, beat * 1.4), 0.75)   # sustained bass on the off-beats
    put(bt + beat / 2, hat(), 0.12); truth["hat"].append(bt + beat / 2)
t += bars * bar
# ---- B: sparse vocal (no drums)
truth["sections"]["sparse_vocal"] = [t, t + bars * bar]
phrases = [(0.2, 2.6, 220, "aeo"), (4.2, 2.2, 247, "iau"), (7.6, 3.0, 196, "oea"), (12.0, 2.4, 262, "aio"), (15.6, 2.4, 220, "ea")]
for st, ln, f0, vw in phrases:
    put_as("vocals", t + st, sing(ln, f0, list(vw)), 0.8); truth["vocal"].append([t + st, t + st + ln])
put_as("other", t, np.sin(2 * np.pi * 110 * tt(bars * bar)) * 0.04, 1)   # quiet pad
t += bars * bar
# ---- C: drums + vocals
truth["sections"]["drums_vocals"] = [t, t + bars * bar]
for b in range(bars * 4):
    bt = t + b * beat
    if b % 2 == 0: put(bt, kick(), 0.85); truth["kick"].append(bt)
    else: put(bt, snare(), 0.55); truth["snare"].append(bt)
    for h in (0, 0.5):
        put(bt + h * beat, hat(), 0.1); truth["hat"].append(bt + h * beat)
for st, ln, f0, vw in [(0.3, 3.0, 233, "aei"), (4.4, 2.8, 262, "oau"), (8.6, 3.2, 220, "eao"), (13.0, 2.8, 247, "iao")]:
    put_as("vocals", t + st, sing(ln, f0, list(vw)), 0.7); truth["vocal"].append([t + st, t + st + ln])
def pluck(f0, length):   # a guitar-like plucked chord, panned left ("other")
    tq = tt(length); return sum(np.sin(2 * np.pi * f0 * r * tq) for r in (1, 1.26, 1.5)) * np.exp(-tq * 3) / 3
for b in range(bars):
    put_as("other", t + b * bar + beat, pluck(330 if b % 2 else 294, bar * 0.9), 0.25)
t += bars * bar

mix = sum(parts.values())
g = 0.9 / (np.max(np.abs(mix)) or 1)
out = sys.argv[1]
def write(path, st):
    w = wave.open(path, "wb"); w.setnchannels(2); w.setsampwidth(2); w.setframerate(sr)
    w.writeframes((np.clip(st * g, -1, 1) * 32767).astype("<i2").tobytes()); w.close()
write(out, mix)
if "--parts" in sys.argv:   # ground-truth stems for checking the splitter
    for k, v in parts.items(): write(out.rsplit(".", 1)[0] + f".{k}.wav", v)
json.dump(truth, open(out.rsplit(".", 1)[0] + ".truth.json", "w"), indent=1)
print(f"wrote {out}: {dur:.1f}s kicks={len(truth['kick'])} snares={len(truth['snare'])} hats={len(truth['hat'])} vocal phrases={len(truth['vocal'])}")

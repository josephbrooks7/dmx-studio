"""Pop-structure test song with known parts: Intro, Verse 1, Pre-Chorus, Chorus, Verse 2, Pre-Chorus,
Chorus 2, Bridge, Chorus 3, Outro. Each part has its own chord progression; choruses are louder and sung.
Writes <name>.truth.json with the parts."""
import json, math, sys, wave
import numpy as np
sr = 44100; bpm = 100.0; beat = 60 / bpm; bar = 4 * beat
rng = np.random.default_rng(11)
plan = [("Intro", 4, "I"), ("Verse", 8, "V"), ("Pre-Chorus", 4, "P"), ("Chorus", 8, "C"), ("Verse", 8, "V"),
        ("Pre-Chorus", 4, "P"), ("Chorus", 8, "C"), ("Bridge", 8, "B"), ("Chorus", 8, "C"), ("Outro", 4, "I")]
NOTE = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}
def chord(name):  # e.g. "Am", "F"
    root = NOTE[name[0]]; minor = name.endswith("m")
    return [root, root + (3 if minor else 4), root + 7]
PROG = {"I": ["C", "C", "F", "F"], "V": ["Am", "F", "C", "G"], "P": ["Dm", "Em", "F", "G"],
        "C": ["C", "G", "Am", "F"], "B": ["Em", "Am", "Dm", "G"]}
lead = 1.0
total = lead + sum(b for _, b, _ in plan) * bar + 2
L = np.zeros(int(total * sr)); R = np.zeros(int(total * sr))
def put(t0, sig, amp, pan=0.5):
    i = int(t0 * sr); j = min(len(L), i + len(sig))
    L[i:j] += amp * (1 - pan) * 2 * sig[: j - i]; R[i:j] += amp * pan * 2 * sig[: j - i]
tt = lambda n: np.arange(int(n * sr)) / sr
hz = lambda m: 440 * 2 ** ((m - 69) / 12)
def pad(notes, length):
    t = tt(length); env = np.minimum(1, t / 0.05) * np.minimum(1, (length - t) / 0.1)
    return sum(np.sign(np.sin(2 * np.pi * hz(48 + n) * t)) * 0.3 + np.sin(2 * np.pi * hz(60 + n) * t) for n in notes) * env / 4
def bassnote(n, length):
    t = tt(length); return np.sin(2 * np.pi * hz(36 + n) * t) * np.minimum(1, t / 0.02) * np.exp(-t * 1.5)
def kick():
    t = tt(0.35); f = 50 + 90 * np.exp(-t * 35); return np.sin(2 * np.pi * np.cumsum(f) / sr) * np.exp(-t * 12)
def snare():
    t = tt(0.25); return 0.7 * rng.uniform(-1, 1, len(t)) * np.exp(-t * 18) + 0.3 * np.sin(2 * np.pi * 190 * t) * np.exp(-t * 20)
def hat():
    t = tt(0.05); n = rng.uniform(-1, 1, len(t) + 2); return (n[:-2] - 2 * n[1:-1] + n[2:]) / 4 * np.exp(-t * 90)
FORM = [(730, 1090, 2440), (530, 1840, 2480), (300, 870, 2240), (570, 840, 2410)]
def sing(notes, length):
    """A sung line: one note per beat, vowel formants, vibrato."""
    out = np.zeros(int(length * sr)); per = len(out) // len(notes)
    for k, m in enumerate(notes):
        t = tt(per / sr); f0 = hz(m) * (1 + 0.01 * np.sin(2 * np.pi * 5.5 * t)); ph = 2 * np.pi * np.cumsum(f0) / sr
        F = FORM[k % 4]; seg = np.zeros(len(t))
        for h in range(1, 20):
            if hz(m) * h > 5000: break
            g = sum(math.exp(-((hz(m) * h - x) / 120) ** 2) for x in F) + 0.05
            seg += g / h ** 0.6 * np.sin(h * ph)
        env = np.minimum(1, t / 0.03) * np.minimum(1, (t[-1] - t + 1e-3) / 0.05)
        out[k * per:k * per + len(t)] = seg * env / 6
    return out
MEL = {"V": [69, 69, 67, 65, 64, 64, 65, 67], "P": [62, 64, 65, 67, 69, 71, 72, 72], "C": [72, 72, 74, 72, 71, 69, 67, 69],
       "B": [64, 67, 69, 71, 69, 67, 64, 62]}
truth = []
t = lead
for name, nbars, key in plan:
    loud = {"C": 1.0, "B": 0.7, "P": 0.75, "V": 0.6, "I": 0.35}[key]
    truth.append([name, t, t + nbars * bar])
    for b in range(nbars):
        t0 = t + b * bar; ch = chord(PROG[key][b % 4])
        put(t0, pad(ch, bar), 0.35 * loud, 0.35)
        put(t0, bassnote(ch[0], bar), 0.5 * loud)
        for q in range(4):
            if key != "I" or q == 0: put(t0 + q * beat, kick(), 0.8 * loud)
            if key not in ("I",) and q % 2 == 1: put(t0 + q * beat, snare(), 0.45 * loud)
            for h in ((0, 0.5) if key == "C" else (0.5,)):
                put(t0 + (q + h) * beat, hat(), 0.08 * loud, 0.6)
        if key in MEL and b % 2 == 0 and "--no-vocals" not in sys.argv:   # a sung line over two bars (1.75 bars sung, then a breath)
            put(t0, sing(MEL[key], bar * 1.75), 0.9 * (0.8 + 0.4 * loud))
    t += nbars * bar
mix = np.stack([L, R], 1); mix = mix / np.max(np.abs(mix)) * 0.9
w = wave.open(sys.argv[1], "wb"); w.setnchannels(2); w.setsampwidth(2); w.setframerate(sr)
w.writeframes((mix * 32767).astype("<i2").tobytes()); w.close()
json.dump(truth, open(sys.argv[1].rsplit(".", 1)[0] + ".truth.json", "w"), indent=1)
print("wrote", sys.argv[1], f"{total:.1f}s", [p[0] for p in truth])

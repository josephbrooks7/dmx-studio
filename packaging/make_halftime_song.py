"""A half-time bass track: 140 BPM, kick on beat 1, snare on beat 3 only, heavy sustained sub-bass."""
import sys, wave, numpy as np
sr = 44100; bpm = 140.0; beat = 60 / bpm; bars = 24
x = np.zeros(int((2 + bars * 4 * beat + 2) * sr)); rng = np.random.default_rng(3)
def put(t0, sig, amp):
    i = int(t0 * sr); j = min(len(x), i + len(sig)); x[i:j] += amp * sig[: j - i]
tt = lambda L: np.arange(int(L * sr)) / sr
def kick():
    t = tt(0.4); f = 45 + 90 * np.exp(-t * 35); return np.sin(2 * np.pi * np.cumsum(f) / sr) * np.exp(-t * 10)
def snare():
    t = tt(0.3); return (0.7 * rng.uniform(-1, 1, len(t)) * np.exp(-t * 15) + 0.4 * np.sin(2 * np.pi * 190 * t) * np.exp(-t * 20))
def hat():
    t = tt(0.05); n = rng.uniform(-1, 1, len(t) + 2); return (n[:-2] - 2 * n[1:-1] + n[2:]) / 4 * np.exp(-t * 90)
for b in range(bars):
    t0 = 2 + b * 4 * beat
    put(t0, kick(), 0.9); put(t0 + 2 * beat, snare(), 0.6)
    if b % 2: put(t0 + 3.5 * beat, kick(), 0.7)
    for h in range(8): put(t0 + h * beat / 2, hat(), 0.08)
    t = tt(4 * beat); put(t0, np.sin(2 * np.pi * 45 * t) * (0.6 + 0.4 * np.sin(2 * np.pi * 4 / beat / 4 * t)), 0.5)
x = x / np.max(np.abs(x)) * 0.9
w = wave.open(sys.argv[1], 'wb'); w.setnchannels(1); w.setsampwidth(2); w.setframerate(sr)
w.writeframes((x * 32767).astype('<i2').tobytes()); w.close()

"""The app's High Quality split. Default "vocals focus": vocals from Demucs' vocals specialist (must beat the
6-part reference), drums/bass/other from the quick splitter on the instrumental. VOX unset: 6-part parity."""
import json, os, subprocess, sys, wave
import numpy as np
song, stems, ref = sys.argv[1], sys.argv[2], json.load(open(sys.argv[3]))
base = song.rsplit(".", 1)[0]
vox = os.environ.get("VOX") == "1"
def read(p):
    if not p.endswith(".wav"):
        subprocess.run(["afconvert", "-f", "WAVE", "-d", "LEI16", p, "/tmp/_h.wav"], check=True); p = "/tmp/_h.wav"
    w = wave.open(p); return np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").astype(float).reshape(-1, w.getnchannels()) / 32768
def sdr(name):
    est, r = read(os.path.join(stems, name + ".m4a")), read(f"{base}.{name}.wav")
    n = min(len(est), len(r)); best = -99
    for sh in range(-2400, 2401, 16):
        e = est[max(0, sh):n + min(0, sh)]; q = r[max(0, -sh):n - max(0, sh)]
        m = min(len(e), len(q)); e, q = e[:m], q[:m]
        best = max(best, 10 * np.log10((q ** 2).sum() / (((q - e) ** 2).sum() + 1e-9) + 1e-12))
    return best
ok = True
def check(cond, msg):
    global ok
    print(("PASS " if cond else "FAIL ") + msg); ok = ok and cond
if vox:
    for name, need in (("vocals", ref["vocals"] + 1.0), ("drums", 2.0), ("bass", 8.0)):
        v = sdr(name); check(v >= need, f"{name}: {v:.1f} dB (need {need:.1f}; 6-part model gives {ref.get(name, 0):.1f})")
    for name in ("other", "backing"):
        check(os.path.exists(os.path.join(stems, name + ".m4a")), f"{name} written")
else:
    for name in ("drums", "bass", "other", "vocals"):
        v = sdr(name); check(v >= ref[name] - 1.0, f"{name}: app {v:.1f} dB vs reference {ref[name]:.1f} dB")
sys.exit(0 if ok else 1)

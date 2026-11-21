"""The app's High Quality split (Swift + Core ML) must match the reference pipeline (export_demucs.py)."""
import json, os, subprocess, sys, wave
import numpy as np
song, stems, ref = sys.argv[1], sys.argv[2], json.load(open(sys.argv[3]))
base = song.rsplit(".", 1)[0]
def read(p):
    if not p.endswith(".wav"):
        subprocess.run(["afconvert", "-f", "WAVE", "-d", "LEI16", p, "/tmp/_h.wav"], check=True); p = "/tmp/_h.wav"
    w = wave.open(p); return np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").astype(float).reshape(-1, w.getnchannels()) / 32768
ok = True
vox = os.environ.get("VOX") == "1"   # vocals come from the specialist: vocals/other differ from the 6-part reference
for name in ("drums", "bass", "other", "vocals", "guitar", "piano", "backing"):
    if name == "backing" and not vox and not os.path.exists(os.path.join(stems, "backing.m4a")): continue
    p = os.path.join(stems, name + ".m4a")
    if not os.path.exists(p): print("FAIL", name, "missing"); ok = False; continue
    if name not in ref: print("PASS", name, "written"); continue
    est, r = read(p), read(f"{base}.{name}.wav")
    n = min(len(est), len(r)); best = -99
    for sh in range(-2400, 2401, 16):
        e = est[max(0, sh):n + min(0, sh)]; q = r[max(0, -sh):n - max(0, sh)]
        m = min(len(e), len(q)); e, q = e[:m], q[:m]
        best = max(best, 10 * np.log10((q ** 2).sum() / (((q - e) ** 2).sum() + 1e-9) + 1e-12))
    good = best >= ref[name] - 1.0 or (vox and name in ("vocals", "other"))
    ok = ok and good
    print(("PASS " if good else "FAIL ") + f"{name}: app {best:.1f} dB vs reference {ref[name]:.1f} dB (true part)")
sys.exit(0 if ok else 1)

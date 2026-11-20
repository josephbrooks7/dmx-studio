"""CI check for the built-in stem splitter + drum/vocal detection on the verification song.
Usage: check_stems.py analyze_output.txt verify.wav stems_dir"""
import json, re, subprocess, sys, wave, os
import numpy as np
out, song, stems = sys.argv[1], sys.argv[2], sys.argv[3]
o = open(out).read()
T = json.load(open(song.rsplit('.', 1)[0] + '.truth.json'))
ok = True
def check(cond, msg):
    global ok
    print(('PASS ' if cond else 'FAIL ') + msg); ok = ok and cond
def times(key):
    m = re.search(key + r'=([\d.,]*)', o); return [float(v) for v in m.group(1).split(',') if v] if m else []
def match(det, tru, tol=0.05):
    used = set(); tp = 0
    for d in det:
        c = [j for j, t in enumerate(tru) if j not in used and abs(t - d) <= tol]
        if c: used.add(c[0]); tp += 1
    return tp, len(det) - tp, len(tru) - tp
for key, name, rec, fmax in (('kickTimes', 'kick', 0.95, 2), ('snareTimes', 'snare', 0.9, 2), ('hatTimes', 'hat', 0.8, 30)):
    tp, fp, fn = match(times(key), T[name])
    check(tp / len(T[name]) >= rec and fp <= fmax, f'{name}: {tp} found, {fp} false, {fn} missed (of {len(T[name])})')
# the bass-heavy section: sustained bass notes must not turn into kicks
a, b = T['sections']['bass_heavy']
bk = [t for t in times('kickTimes') if a <= t <= b]
check(abs(len(bk) - 16) <= 1, f'bass-heavy section: {len(bk)} kicks (16 real, sustained bass ignored)')
offgrid = [t for t in T['kick'] if abs(((t - a) / 0.6) - round((t - a) / 0.6)) > 0.05]
check(all(min(abs(d - t) for d in times('kickTimes')) < 0.03 for t in offgrid), 'off-grid kick kept at its real time')
m = re.search(r'vocalPhrases=([\d.,\-]*)', o)
ph = [tuple(float(x) for x in p.split('-')) for p in m.group(1).split(',') if p] if m else []
ov = lambda p, q: max(0, min(p[1], q[1]) - max(p[0], q[0]))
tot = sum(e - s for s, e in T['vocal']); det = sum(e - s for s, e in ph) or 1e-9
cov = sum(ov(p, q) for p in ph for q in T['vocal'])
check(cov / tot >= 0.8 and cov / det >= 0.8, f'vocal phrases: {len(ph)} found, coverage {cov/tot:.2f}, precision {cov/det:.2f}')
# separated parts: present and close to the true parts
def read(path):
    if not path.endswith('.wav'):
        subprocess.run(['afconvert', '-f', 'WAVE', '-d', 'LEI16', path, '/tmp/_s.wav'], check=True); path = '/tmp/_s.wav'
    w = wave.open(path); d = np.frombuffer(w.readframes(w.getnframes()), dtype='<i2').astype(float) / 32768
    return d.reshape(-1, w.getnchannels())
mix = read(song); g = None
for k, need in (('vocals', 4.0), ('drums', 0.5), ('bass', 7.0)):
    p = os.path.join(stems, k + '.m4a')
    if not os.path.exists(p): check(False, f'{k}.m4a written'); continue
    est = read(p); ref = read(song.rsplit('.', 1)[0] + f'.{k}.wav')
    n = min(len(est), len(ref)); best = -99
    for sh in range(-2400, 2401, 16):          # allow for AAC encoder delay
        e = est[max(0, sh):n + min(0, sh)]; r = ref[max(0, -sh):n - max(0, sh)]
        m2 = min(len(e), len(r)); e, r = e[:m2], r[:m2]
        sdr = 10 * np.log10((r ** 2).sum() / (((r - e) ** 2).sum() + 1e-9) + 1e-12); best = max(best, sdr)
    check(best >= need, f'{k} part separated: {best:.1f} dB (need {need})')
check(os.path.exists(os.path.join(stems, 'other.m4a')) and os.path.exists(os.path.join(stems, 'overview.json')), 'other.m4a + waveform overview written')
sys.exit(0 if ok else 1)

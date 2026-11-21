"""Checks the app's pasted-lyrics timing against the truth. usage: check_lyric_align.py app_output.txt truth.json"""
import json, re, sys
truth = json.load(open(sys.argv[2]))
got = [(float(m.group(1)), m.group(2).strip()) for m in
       (re.match(r"^LINE ([\d.]+) [\d.]+ (.*)$", l) for l in open(sys.argv[1])) if m]
print("app lines:"); [print(f"  {t:6.2f}  {s}") for t, s in got]
ok = True
if [s for _, s in got] != truth["lines"]:
    print(f"FAIL paste cleaning: expected the {len(truth['lines'])} lyric lines once, got {len(got)}"); ok = False
else: print("PASS paste cleaning: web leftovers and the duplicate copy removed")
if ok:
    errs = sorted(abs(t - s) for (t, _), s in zip(got, truth["starts"]))
    med, worst = errs[len(errs) // 2], errs[-1]
    print(f"line start error: median {med:.2f}s, worst {worst:.2f}s")
    if med <= 0.6 and worst <= 2.0: print("PASS pasted lines land where they're sung")
    else: print("FAIL pasted line timing"); ok = False
sys.exit(0 if ok else 1)

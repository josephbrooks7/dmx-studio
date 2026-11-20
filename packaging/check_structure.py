import json, re, sys
o = open(sys.argv[1]).read(); truth = json.load(open(sys.argv[2]))
secs = [(m[0], float(m[1]), float(m[2])) for m in re.findall(r'section (.+?) ([\d.]+)-([\d.]+) ', o)]
print("detected:", [f"{n} {a:.0f}-{b:.0f}" for n, a, b in secs])
ok = 0; bad = []
for name, a, b in truth:
    mid = (a + b) / 2
    got = next((n for n, s, e in secs if s <= mid < e), "?")
    role = re.sub(r"\s*\d+$", "", got.split(" ·")[0])
    good = role == name
    ok += good
    print(("PASS " if good else "FAIL ") + f"{name} at {a:.0f}-{b:.0f}s detected as {got}")
    if not good: bad.append(name)
v2 = [n for n, s, e in secs if s <= (truth[4][1] + truth[4][2]) / 2 < e]
print(f"{ok}/{len(truth)} parts named right")
sys.exit(0 if ok >= len(truth) - 2 and not (v2 and v2[0].startswith("Chorus")) else 1)

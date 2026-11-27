"""Learn anthropometric relationships from ANSUR II individual records (male and female CSVs).

Writes packaging/character-reference/ansur2-model.json with, per sex:
- percentiles (5/50/95) and mean/SD of every numeric measurement (mm, or as recorded)
- a linear fit of every measurement against stature (slope, intercept, residual SD, r), so
  bone lengths follow height and the residual SD says how much individuals vary at a height
- a correlation matrix for the measurements the character system uses
Only summary statistics are written; the raw records are not committed.

usage: python3 ansur2_model.py MALE.csv FEMALE.csv OUT.json
"""
import csv, json, math, sys

KEY = ["stature", "weightkg", "span", "sittingheight", "acromialheight", "crotchheight",
       "biacromialbreadth", "bideltoidbreadth", "shoulderelbowlength", "forearmhandlength",
       "radialestylionlength", "acromionradialelength", "handlength", "handbreadth", "footlength",
       "footbreadthhorizontal", "kneeheightsitting", "lateralfemoralepicondyleheight",
       "neckcircumference", "neckcircumferencebase", "chestcircumference", "waistcircumference",
       "buttockcircumference", "thighcircumference", "calfcircumference", "bicepscircumferenceflexed",
       "forearmcircumferenceflexed", "wristcircumference", "anklecircumference", "headcircumference",
       "headbreadth", "headlength", "cervicaleheight", "waistheightomphalion", "trochanterionheight"]


def load(path):
    for enc in ("utf-8-sig", "latin-1"):
        try:
            with open(path, newline="", encoding=enc) as f:
                rows = list(csv.DictReader(f))
            break
        except UnicodeDecodeError:
            continue
    cols = {}
    for name in rows[0].keys():
        vals = []
        for r in rows:
            try:
                vals.append(float(r[name]))
            except (TypeError, ValueError):
                vals = None
                break
        if vals:
            cols[name.strip().lower()] = vals
    return cols, len(rows)


def pct(sorted_vals, p):
    k = (len(sorted_vals) - 1) * p / 100
    lo, hi = math.floor(k), math.ceil(k)
    return sorted_vals[lo] + (sorted_vals[hi] - sorted_vals[lo]) * (k - lo)


def fit(x, y):
    n = len(x); mx = sum(x) / n; my = sum(y) / n
    sxx = sum((a - mx) ** 2 for a in x); syy = sum((b - my) ** 2 for b in y)
    sxy = sum((a - mx) * (b - my) for a, b in zip(x, y))
    slope = sxy / sxx if sxx else 0.0
    inter = my - slope * mx
    resid = math.sqrt(sum((b - (inter + slope * a)) ** 2 for a, b in zip(x, y)) / max(n - 2, 1))
    r = sxy / math.sqrt(sxx * syy) if sxx and syy else 0.0
    return {"slope": round(slope, 5), "intercept": round(inter, 2), "residualSD": round(resid, 2), "r": round(r, 3)}


def corr(a, b):
    n = len(a); ma = sum(a) / n; mb = sum(b) / n
    sab = sum((x - ma) * (y - mb) for x, y in zip(a, b))
    sa = math.sqrt(sum((x - ma) ** 2 for x in a)); sb = math.sqrt(sum((y - mb) ** 2 for y in b))
    return round(sab / (sa * sb), 3) if sa and sb else 0.0


def summarize(cols, n):
    out = {"records": n, "measurements": {}, "vsStature": {}, "correlations": {}}
    stature = cols.get("stature")
    for name, vals in sorted(cols.items()):
        if name in ("subjectid",) or len(set(vals)) < 10:
            continue
        s = sorted(vals); m = sum(vals) / len(vals)
        sd = math.sqrt(sum((v - m) ** 2 for v in vals) / (len(vals) - 1))
        out["measurements"][name] = {"p5": round(pct(s, 5), 1), "p50": round(pct(s, 50), 1),
                                     "p95": round(pct(s, 95), 1), "mean": round(m, 1), "sd": round(sd, 1)}
        if stature and name != "stature":
            out["vsStature"][name] = fit(stature, vals)
    keys = [k for k in KEY if k in cols]
    out["correlations"] = {"order": keys,
                           "matrix": [[corr(cols[a], cols[b]) for b in keys] for a in keys]}
    out["missingKeyMeasurements"] = [k for k in KEY if k not in cols]
    return out


def main():
    male_csv, female_csv, out = sys.argv[1:4]
    model = {"schemaVersion": 1,
             "source": "ANSUR II public data (US Army 2012 anthropometric survey) via Penn State OpenLab; summary statistics only",
             "units": "as recorded in ANSUR II (lengths in mm; weightkg in tenths of kg)",
             "male": summarize(*load(male_csv)), "female": summarize(*load(female_csv))}
    with open(out, "w") as f:
        json.dump(model, f, indent=1)
        f.write("\n")
    for sex in ("male", "female"):
        m = model[sex]
        print(sex, m["records"], "records,", len(m["measurements"]), "measurements; missing key:", m["missingKeyMeasurements"])


if __name__ == "__main__":
    main()

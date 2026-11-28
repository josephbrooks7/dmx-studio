#!/usr/bin/env python3
"""Make the compact character pack bundled inside DMX Studio from the full Character Library.

  python3 build_app_pack.py <library_dir> <out_dir>

Keeps: base mesh, skeleton, skin weights, the adult shape targets the app drives (sex, muscle,
weight, height for young adults; never child or baby targets), one skin per sex and ancestry,
and the wardrobe slots Character Studio uses. Writes catalog.json (the app's index),
CREDITS.md (CC-BY authors) and contents.json (a readable list for review).
"""
import json, re, shutil, sys
from pathlib import Path
import numpy as np

sys.path.insert(0, str(Path(__file__).parent))
from mhbody import read_bin
from build_library import write_bin

lib, out = Path(sys.argv[1]), Path(sys.argv[2])
if out.exists():
    shutil.rmtree(out)
out.mkdir(parents=True)
cat = json.load(open(lib / "catalog.json"))

for f in ("base.bin", "rig.json", "weights.bin"):
    shutil.copy2(lib / f, out / f)

# ---- adult macro targets only
macro = next(g for g in cat["targets"] if g["group"] == "macrodetails")
header, arrays = read_bin(lib / macro["file"])
keep = re.compile(r"^macrodetails/(?:(?:african|asian|caucasian)-(?:male|female)-young"
                  r"|universal-(?:male|female)-young-\w+muscle-\w+weight"
                  r"|height/(?:male|female)-young-\w+muscle-\w+weight-(?:max|min)height)$")
banned = re.compile(r"child|baby|old", re.I)
idx_all, d_all, ranges, n = [], [], [], 0
for r in header["targets"]:
    if not keep.match(r["name"]) or banned.search(r["name"]):
        continue
    s, c = r["start"], r["count"]
    idx_all.append(arrays["index"][s:s + c]); d_all.append(arrays["delta"][s:s + c])
    ranges.append({"name": r["name"], "start": n, "count": c, "license": r["license"], "source": r["source"]})
    n += c
write_bin(out / "targets.bin", {"kind": "targets", "group": "adult-macro", "targets": ranges},
          {"index": np.concatenate(idx_all), "delta": np.concatenate(d_all).astype(np.float32)})
print("targets:", len(ranges))

# ---- skins: one per sex and ancestry (young adult), plus any extra young adult skins
skins = []
for sex in ("female", "male"):
    for race in ("caucasian", "asian", "african"):
        found = [s for s in cat["skins"] if re.search(rf"\byoung\b.*\b{race}\b.*\b{sex}\b|\b{race}\b.*\byoung\b.*\b{sex}\b", s["name"].lower())
                 and not (sex == "male" and "female" in s["name"].lower())]
        found.sort(key=lambda s: ("detailed" in s["name"].lower(), s["name"]))
        if found:
            s = dict(found[0], sex=sex, ancestry=race)
            skins.append(s)
for s in skins:
    (out / "skins").mkdir(exist_ok=True)
    shutil.copy2(lib / s["texture"], out / s["texture"])
print("skins:", [s["name"] for s in skins])

# ---- wardrobe
SLOTS = {"hair", "eyebrows", "eyelashes", "eyes", "teeth", "shoes", "top", "bottom", "outfit", "socks", "hat", "facialhair",
         "glasses", "gloves", "wings"}
MAX_VERTICES = 60000      # very dense items cost too much per performer
items = [i for i in cat["items"] if i["slot"] in SLOTS and i.get("vertices", 0) <= MAX_VERTICES]
for i in items:
    src = lib / Path(i["file"]).parent
    shutil.copytree(src, out / Path(i["file"]).parent, dirs_exist_ok=True)

# Keep the download reasonable: color maps up to 1024 px, normal maps up to 512 px.
from PIL import Image
Image.MAX_IMAGE_PIXELS = None
shrunk = 0
for img in list(out.rglob("*.png")) + list(out.rglob("*.jpg")) + list(out.rglob("*.jpeg")):
    try:
        with Image.open(img) as im:
            limit = 512 if "normal" in img.name.lower() else 1024
            if max(im.size) <= limit:
                continue
            scale = limit / max(im.size)
            small = im.resize((max(1, int(im.width * scale)), max(1, int(im.height * scale))), Image.LANCZOS)
            if img.suffix.lower() in (".jpg", ".jpeg"):
                small.convert("RGB").save(img, quality=88)
            else:
                small.save(img, optimize=True)
            shrunk += 1
    except Exception as e:
        print("texture skipped", img, e)
print("textures shrunk:", shrunk)

app = {"version": 1, "basemesh": cat["basemesh"], "rig": cat.get("rig"), "targets": "targets.bin",
       "skins": skins, "items": items, "licenses": cat["licenses"],
       "credits": [c for c in cat["credits"] if c["id"] in {x["id"] for x in items + skins}]}
json.dump(app, open(out / "catalog.json", "w"), indent=1)

lines = ["# Character credits", "",
         "Bodies, skeleton and most assets: MakeHuman (CC0). The following are CC BY 4.0:", ""]
for c in app["credits"]:
    lines.append(f"- {c['name']} by {c['author']} ({c['pack']}), CC BY 4.0, {c['source']}")
(out / "CREDITS.md").write_text("\n".join(lines) + "\n")

contents = {"targets": len(ranges), "skins": [s["name"] for s in skins], "items": {}}
for i in items:
    contents["items"].setdefault(i["slot"], []).append(
        {"id": i["id"], "name": i["name"], "gender": i["gender"], "styles": i["styles"], "license": i["license"],
         "tags": i["tags"][:8], "vertices": i["vertices"], "transparent": i["transparent"]})
json.dump(contents, open(out / "contents.json", "w"), indent=1)
size = sum(p.stat().st_size for p in out.rglob("*") if p.is_file())
print("items:", {k: len(v) for k, v in contents["items"].items()}, "size MB:", round(size / 1e6, 1))

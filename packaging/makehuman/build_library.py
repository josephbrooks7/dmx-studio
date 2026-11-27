#!/usr/bin/env python3
"""Build the DMX Studio Character Library from MakeHuman CC0 / CC-BY assets.

Inputs
  --mh      MakeHuman repository data dir (contains 3dobjs/base.obj, targets/, modifiers/)
  --packs   directory of asset-pack zips (the makehuman-assets-1 release) + manifest.json
Output
  --out     library directory:
              catalog.json            everything the app needs to list, filter and credit
              base.bin                shared body (morphable) mesh
              targets/<group>.bin     sparse shape adjustments, one file per group
              items/<id>/item.bin     fitted clothing / hair / eyebrows / beards ... (mesh + binding)
              items/<id>/*.jpg|png    textures, thumb.png
              skins/<id>.jpg          skin textures, thumbs

Binary files are little-endian. Every .bin starts with a JSON header:
  uint32 header_length, header JSON (utf-8), then raw arrays at the offsets the header lists
  (offsets are relative to the end of the header).  Types: f4 = float32, u4 = uint32.
"""
import argparse, io, json, os, re, struct, sys, zipfile, hashlib
from pathlib import Path
import numpy as np
from PIL import Image

Image.MAX_IMAGE_PIXELS = None

# ---------------------------------------------------------------- binary writer
def write_bin(path, header, arrays):
    """arrays: dict name -> numpy array (float32 or uint32). Offsets go into header['arrays']."""
    blobs, table, off = [], {}, 0
    for name, a in arrays.items():
        a = np.ascontiguousarray(a)
        dtype = {np.dtype('float32'): 'f4', np.dtype('uint32'): 'u4'}[a.dtype]
        b = a.tobytes()
        table[name] = {"offset": off, "count": int(a.size), "type": dtype, "shape": list(a.shape)}
        blobs.append(b); off += len(b)
        pad = (-off) % 4
        if pad: blobs.append(b"\0" * pad); off += pad
    header = dict(header, arrays=table)
    h = json.dumps(header, separators=(",", ":")).encode()
    h += b" " * ((-len(h)) % 4)
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    with open(path, "wb") as f:
        f.write(struct.pack("<I", len(h))); f.write(h)
        for b in blobs: f.write(b)

# ---------------------------------------------------------------- OBJ
def parse_obj(text, keep_groups=None):
    v, vt, faces, group = [], [], [], None
    for line in text.splitlines():
        if not line or line[0] == '#': continue
        p = line.split()
        if p[0] == 'v': v.append([float(x) for x in p[1:4]])
        elif p[0] == 'vt': vt.append([float(x) for x in p[1:3]])
        elif p[0] == 'g': group = p[1] if len(p) > 1 else None
        elif p[0] == 'f':
            if keep_groups is not None and group not in keep_groups: continue
            corners = []
            for c in p[1:]:
                s = c.split('/')
                vi = int(s[0]) - 1
                ti = int(s[1]) - 1 if len(s) > 1 and s[1] else -1
                corners.append((vi, ti))
            for k in range(1, len(corners) - 1):          # triangulate fans (quads -> 2 tris)
                faces.append((corners[0], corners[k], corners[k + 1]))
    return np.array(v, np.float32), np.array(vt or [[0, 0]], np.float32), faces

def unweld(v, vt, faces):
    """SceneKit needs one UV per vertex: split by (position, uv) pairs.
    Returns positions, uvs, triangle indices, and map unwelded -> original vertex index."""
    key_to_idx, src, uvs, tris = {}, [], [], []
    for tri in faces:
        out = []
        for vi, ti in tri:
            k = (vi, ti)
            i = key_to_idx.get(k)
            if i is None:
                i = len(src); key_to_idx[k] = i; src.append(vi)
                uvs.append(vt[ti] if ti >= 0 else (0.0, 0.0))
            out.append(i)
        tris.append(out)
    src = np.array(src, np.uint32)
    return v[src], np.array(uvs, np.float32), np.array(tris, np.uint32).reshape(-1), src

# ---------------------------------------------------------------- targets
def parse_target(text):
    idx, d = [], []
    for line in text.splitlines():
        if not line or line[0] == '#': continue
        p = line.split()
        if len(p) < 4: continue
        idx.append(int(p[0])); d.append([float(p[1]), float(p[2]), float(p[3])])
    return np.array(idx, np.uint32), np.array(d, np.float32).reshape(-1, 3)

# ---------------------------------------------------------------- materials
def parse_mhmat(text):
    m = {}
    for line in text.splitlines():
        if not line or line[0] == '#': continue
        p = line.split(None, 1)
        if len(p) == 2: m[p[0]] = p[1].strip()
    return m

def save_texture(data, dst, size, keep_alpha):
    im = Image.open(io.BytesIO(data))
    im.load()
    if max(im.size) > size:
        im.thumbnail((size, size), Image.LANCZOS)
    has_alpha = keep_alpha and (im.mode in ("RGBA", "LA") or "transparency" in im.info)
    dst = Path(dst)
    if has_alpha:
        im = im.convert("RGBA"); dst = dst.with_suffix(".png"); im.save(dst, optimize=True)
    else:
        im = im.convert("RGB"); dst = dst.with_suffix(".jpg"); im.save(dst, quality=86, optimize=True)
    return dst.name

# ---------------------------------------------------------------- slots
SLOT_BY_DIR = {"hair": "hair", "eyebrows": "eyebrows", "eyelashes": "eyelashes", "eyes": "eyes",
               "teeth": "teeth", "tongue": "tongue"}
def guess_slot(pack, rel, name, tags):
    top = rel.split("/")[0]
    if top in SLOT_BY_DIR: return SLOT_BY_DIR[top]
    n, t = name.lower(), {x.lower() for x in tags}
    pk = pack.lower()
    if pk.startswith(("bodyparts05", "bodyparts06")) or "beard" in n or "moustache" in n or "mustache" in n: return "facialhair"
    if pk.startswith("bodyparts03"): return "wings" if "wing" in n else "tail"
    if pk.startswith("glasses") or "glasses" in t or "glass" in n: return "glasses"
    if pk.startswith("hats") or t & {"hat", "hats", "helmet", "cap"} or any(k in n for k in ("hat", "cap", "fedora", "helmet", "beanie")): return "hat"
    if pk.startswith("gloves") or "glove" in n: return "gloves"
    if pk.startswith("underwear04") or "sock" in n or "stocking" in n: return "socks"
    if pk.startswith("shoes") or "shoes" in t or any(k in n for k in ("shoe", "boot", "sneaker", "sandal", "heel", "pump", "loafer")): return "shoes"
    if pk.startswith(("pants", "skirts")) or any(k in n for k in ("pant", "jean", "trouser", "short", "skirt", "legging")): return "bottom"
    if pk.startswith("shirts") or any(k in n for k in ("shirt", "top", "sweater", "cardigan", "tunic", "blouse", "hoodie", "jacket", "vest", "tee")): return "top"
    if pk.startswith(("dress", "suits")) or "suit" in n or "dress" in n or "gown" in n or "outfit" in n: return "outfit"
    return "accessory"

STYLE_WORDS = {
    "casual": ["casual", "tee", "jean", "sneaker", "hoodie"], "formal": ["formal", "suit", "elegant", "tux", "gown", "dress", "blazer"],
    "rock": ["leather", "rock", "biker", "boot", "punk", "studded"], "sport": ["sport", "track", "running", "trainer"],
    "fantasy": ["fantasy", "sci", "armor", "armour", "medieval", "elf", "wizard", "robe", "wing"], "glam": ["sequin", "glitter", "gown", "heel", "dress"],
}
def style_tags(name, tags):
    s = (name + " " + " ".join(tags)).lower()
    return sorted({k for k, words in STYLE_WORDS.items() if any(w in s for w in words)})

# ---------------------------------------------------------------- packs
class Pack:
    def __init__(self, path, meta):
        self.path, self.meta = path, meta
        self.zip = zipfile.ZipFile(path)
        self.names = self.zip.namelist()
        # some packs wrap everything in one folder; strip a common top folder that is not an asset type
        self.root = ""
        tops = {n.split("/")[0] for n in self.names if "/" in n}
        if len(tops) == 1 and next(iter(tops)) not in ("clothes", "hair", "eyebrows", "eyelashes", "skins", "targets", "eyes"):
            self.root = next(iter(tops)) + "/"
    def read(self, name): return self.zip.read(name)
    def rel(self, name): return name[len(self.root):] if name.startswith(self.root) else name

def resolve(pack, base_dir, ref):
    """Find a file referenced from an .mhclo/.mhmat inside the same pack."""
    if not ref: return None
    ref = ref.replace("\\", "/")
    for cand in (base_dir + "/" + ref, ref, pack.root + ref):
        cand = os.path.normpath(cand).replace("\\", "/")
        if cand in pack.names: return cand
    base = ref.split("/")[-1].lower()
    for n in pack.names:
        if n.lower().endswith("/" + base) and n.startswith(base_dir.split("/")[0]): return n
    for n in pack.names:
        if n.lower().endswith("/" + base): return n
    return None

def parse_mhclo(text):
    head, binds, deletes, mode = {}, [], [], None
    tags = []
    for line in text.splitlines():
        s = line.strip()
        if not s or s[0] == '#': continue
        p = s.split()
        if p[0] == 'verts': mode = 'verts'; continue
        if p[0] == 'delete_verts': mode = 'delete'; continue
        if mode == 'verts' and re.match(r'^-?\d', p[0]):
            if len(p) == 1: binds.append((int(p[0]), 0, 0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0))
            else: binds.append(tuple([int(p[0]), int(p[1]), int(p[2])] + [float(x) for x in p[3:9]]))
            continue
        if mode == 'delete' and re.match(r'^\d', p[0]):
            k = 0
            while k < len(p):
                if k + 2 < len(p) and p[k + 1] == '-':
                    deletes.extend(range(int(p[k]), int(p[k + 2]) + 1)); k += 3
                else:
                    deletes.append(int(p[k])); k += 1
            continue
        # keyword lines (material, tag, ...) may sit between "verts" and its data: keep the section
        if p[0] == 'tag': tags.append(s[4:].strip())
        elif p[0] in ('x_scale', 'y_scale', 'z_scale'): head[p[0]] = [int(p[1]), int(p[2]), float(p[3])]
        else: head[p[0]] = s[len(p[0]):].strip()
    return head, binds, deletes, tags

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mh", required=True); ap.add_argument("--packs", required=True); ap.add_argument("--out", required=True)
    ap.add_argument("--only", nargs="*", help="limit to these pack zip names (testing)")
    args = ap.parse_args()
    mh, packs_dir, out = Path(args.mh), Path(args.packs), Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    manifest = {m["file"]: m for m in json.load(open(packs_dir / "manifest.json"))}
    catalog = {"version": 1, "basemesh": "hm08", "items": [], "skins": [], "targets": [], "credits": [],
               "licenses": {"CC0": "https://creativecommons.org/publicdomain/zero/1.0/",
                            "CC-BY": "https://creativecommons.org/licenses/by/4.0/"}}

    # ---- base body: body group only (helpers and joints are construction geometry)
    v, vt, faces = parse_obj((mh / "3dobjs/base.obj").read_text(), keep_groups={"body"})
    pos, uv, tris, src = unweld(v, vt, faces)
    write_bin(out / "base.bin", {"kind": "base", "baseVertexCount": int(len(v)), "license": "CC0",
                                 "source": "MakeHuman hm08 base mesh"},
              {"positions": pos, "uvs": uv, "triangles": tris, "baseIndex": src,
               # every base vertex, helpers included: joints are averages of helper vertices,
               # so the skeleton follows any body shape the targets produce
               "allPositions": np.asarray(v, np.float32)})
    print("base:", len(v), "verts,", len(pos), "unwelded,", len(tris) // 3, "triangles")

    # ---- skeleton and skin weights (MakeHuman default rig, CC0)
    skel_path = mh / "rigs/default.mhskel"
    if skel_path.exists():
        skel = json.load(open(skel_path))
        wts = json.load(open(mh / "rigs/default_weights.mhw"))["weights"]
        names = sorted(skel["bones"])
        # parents before children
        order, placed = [], set()
        while len(order) < len(names):
            for b in names:
                if b in placed: continue
                par = skel["bones"][b].get("parent")
                if par is None or par in placed:
                    order.append(b); placed.add(b)
        index = {b: i for i, b in enumerate(order)}
        rig = {"kind": "rig", "license": "CC0", "source": "MakeHuman default skeleton",
               "bones": [{"name": b, "parent": skel["bones"][b].get("parent"),
                          "head": skel["bones"][b]["head"], "tail": skel["bones"][b]["tail"]} for b in order],
               "joints": skel["joints"]}
        json.dump(rig, open(out / "rig.json", "w"))
        # top 4 influences per base vertex, normalized
        per = [[] for _ in range(len(v))]
        for b, pairs in wts.items():
            if b not in index: continue
            for vi, w in pairs:
                if vi < len(per): per[vi].append((w, index[b]))
        bi = np.zeros((len(v), 4), np.uint32); bw = np.zeros((len(v), 4), np.float32)
        for vi, lst in enumerate(per):
            lst.sort(reverse=True); lst = lst[:4]
            tot = sum(w for w, _ in lst) or 1.0
            for k, (w, b) in enumerate(lst):
                bi[vi, k] = b; bw[vi, k] = w / tot
        write_bin(out / "weights.bin", {"kind": "weights", "boneCount": len(order)},
                  {"boneIndex": bi, "boneWeight": bw})
        catalog["rig"] = {"file": "rig.json", "weights": "weights.bin", "bones": len(order), "joints": len(skel["joints"])}
        print("rig:", len(order), "bones,", len(skel["joints"]), "joints, weights for", int((bw[:, 0] > 0).sum()), "vertices")

    # ---- shape targets: repository modeling targets + realistic deformation packs
    groups = {}
    skip_dirs = {"expression", "genitals", "stomach/images"}
    for t in sorted((mh / "targets").rglob("*.target")):
        rel = t.relative_to(mh / "targets").as_posix()
        if rel.split("/")[0] in ("expression", "genitals"): continue
        groups.setdefault(rel.split("/")[0], []).append((rel[:-7], t.read_text(), "CC0", "MakeHuman"))
    for f, meta in manifest.items():
        if args.only and f not in args.only: continue
        if not re.match(r"(nose|ears|cheek|arms|hands)01_", f): continue
        pk = Pack(packs_dir / f, meta)
        for n in pk.names:
            if n.endswith(".target"):
                groups.setdefault(f.split("_")[0], []).append(("pack/" + f.split("_")[0] + "/" + n.split("/")[-1][:-7], pk.read(n).decode("utf-8", "replace"), meta["license"], f))
    for g, items in groups.items():
        idx_all, d_all, ranges = [], [], []
        for name, text, lic, origin in items:
            idx, d = parse_target(text)
            ranges.append({"name": name, "start": int(sum(len(x) for x in idx_all)), "count": int(len(idx)), "license": lic, "source": origin})
            idx_all.append(idx); d_all.append(d)
        write_bin(out / "targets" / f"{g}.bin", {"kind": "targets", "group": g, "targets": ranges},
                  {"index": np.concatenate(idx_all) if idx_all else np.zeros(0, np.uint32),
                   "delta": (np.concatenate(d_all) if d_all else np.zeros((0, 3), np.float32)).astype(np.float32)})
        catalog["targets"].append({"group": g, "file": f"targets/{g}.bin", "names": [r["name"] for r in ranges]})
    print("targets:", sum(len(x) for x in groups.values()), "in", len(groups), "groups")

    # ---- items and skins from every pack
    seen_ids = set()
    for f, meta in sorted(manifest.items()):
        if args.only and f not in args.only: continue
        pk = Pack(packs_dir / f, meta)
        lic, packname = meta["license"], f.rsplit("_", 1)[0]
        # skins
        for n in pk.names:
            r = pk.rel(n)
            if r.startswith("skins/") and n.endswith(".mhmat"):
                m = parse_mhmat(pk.read(n).decode("utf-8", "replace"))
                d = resolve(pk, n.rsplit("/", 1)[0], m.get("diffuseTexture"))
                if not d: continue
                sid = re.sub(r"[^a-z0-9_]+", "_", (packname + "_" + m.get("name", Path(n).stem)).lower())
                if sid in seen_ids: continue
                seen_ids.add(sid)
                (out / "skins").mkdir(exist_ok=True)
                tex = save_texture(pk.read(d), out / "skins" / sid, 2048, False)
                thumb = resolve(pk, n.rsplit("/", 1)[0], Path(n).stem + ".thumb")
                th = save_texture(pk.read(thumb), out / "skins" / (sid + "_thumb"), 128, False) if thumb else None
                catalog["skins"].append({"id": sid, "name": m.get("name", sid).replace("_", " "), "texture": "skins/" + tex,
                                         "thumb": ("skins/" + th) if th else None, "license": lic, "pack": f,
                                         "author": m.get("author")})
        # fitted meshes
        for n in pk.names:
            if not n.endswith(".mhclo"): continue
            r, d0 = pk.rel(n), n.rsplit("/", 1)[0]
            head, binds, deletes, tags = parse_mhclo(pk.read(n).decode("utf-8", "replace"))
            if head.get("basemesh", "hm08").lower() not in ("hm08", ""): continue
            name = head.get("name", Path(n).stem)
            iid = re.sub(r"[^a-z0-9_]+", "_", (packname + "_" + name).lower())
            if iid in seen_ids: continue
            objn = resolve(pk, d0, head.get("obj_file"))
            if not objn or not binds: continue
            cv, cvt, cf = parse_obj(pk.read(objn).decode("utf-8", "replace"))
            if len(binds) != len(cv):
                print("  skip (binding mismatch):", f, name, len(binds), len(cv)); continue
            cpos, cuv, ctris, csrc = unweld(cv, cvt, cf)
            b = np.array(binds, np.float64)
            bidx = b[:, 0:3].astype(np.uint32)[csrc]
            bw = b[:, 3:6].astype(np.float32)[csrc]
            boff = b[:, 6:9].astype(np.float32)[csrc]
            scales = [head.get(k, [0, 0, 1.0]) for k in ("x_scale", "y_scale", "z_scale")]
            # material
            textures, mat = {}, {}
            mn = resolve(pk, d0, head.get("material"))
            if mn:
                mat = parse_mhmat(pk.read(mn).decode("utf-8", "replace"))
                idir = out / "items" / iid; idir.mkdir(parents=True, exist_ok=True)
                for key, size, alpha in (("diffuseTexture", 1024, True), ("normalmapTexture", 512, False)):
                    tn = resolve(pk, mn.rsplit("/", 1)[0], mat.get(key))
                    if tn:
                        try: textures[key] = save_texture(pk.read(tn), idir / key.replace("Texture", ""), size, alpha)
                        except Exception as e: print("  texture failed:", tn, e)
            thumbn = resolve(pk, d0, Path(n).stem + ".thumb")
            thumb = None
            if thumbn:
                try: thumb = save_texture(pk.read(thumbn), out / "items" / iid / "thumb", 128, True)
                except Exception: pass
            slot = guess_slot(packname, r, name, tags)
            write_bin(out / "items" / iid / "item.bin",
                      {"kind": "item", "id": iid, "scales": scales, "zDepth": head.get("z_depth")},
                      {"positions": cpos, "uvs": cuv, "triangles": ctris,
                       "bindIndex": bidx, "bindWeight": bw, "bindOffset": boff,
                       "deleteVerts": np.array(sorted(set(deletes)), np.uint32)})
            seen_ids.add(iid)
            color = [float(x) for x in mat.get("diffuseColor", "1 1 1").split()[:3]] if mat else [1, 1, 1]
            catalog["items"].append({
                "id": iid, "name": name.replace("_", " "), "slot": slot, "pack": f, "license": lic,
                "author": head.get("author") or mat.get("author"), "tags": tags, "styles": style_tags(name, tags),
                "gender": "female" if "female" in {t.lower() for t in tags} or "female" in name.lower() else ("male" if "male" in {t.lower() for t in tags} or name.lower().startswith("male") else "any"),
                "file": f"items/{iid}/item.bin", "textures": {k: f"items/{iid}/{v}" for k, v in textures.items()},
                "thumb": f"items/{iid}/{thumb}" if thumb else None,
                "transparent": mat.get("transparent", "False") == "True" or slot in ("hair", "eyebrows", "eyelashes"),
                "diffuseColor": color, "vertices": int(len(cpos))})
        print(f"{f}: {sum(1 for i in catalog['items'] if i['pack'] == f)} items, {sum(1 for s in catalog['skins'] if s['pack'] == f)} skins")

    # ---- credits: every CC-BY item with its author and pack
    for it in catalog["items"] + catalog["skins"]:
        if it["license"] == "CC-BY":
            catalog["credits"].append({"id": it["id"], "name": it["name"], "author": it.get("author") or "see pack " + it["pack"],
                                       "license": "CC-BY 4.0", "pack": it["pack"],
                                       "source": "https://static.makehumancommunity.org/assets/assetpacks.html"})
    json.dump(catalog, open(out / "catalog.json", "w"), indent=1)
    from collections import Counter
    print("slots:", dict(Counter(i["slot"] for i in catalog["items"])))
    print("licenses:", dict(Counter(i["license"] for i in catalog["items"])), "skins:", len(catalog["skins"]))

if __name__ == "__main__":
    main()

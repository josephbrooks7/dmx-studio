"""Assemble a MakeHuman body and fitted items from the DMX Studio Character Library.

This mirrors what the app does at runtime, so the library can be checked offline:
- body = base positions + weighted sum of shape targets (all base vertices, helpers included)
- joints = averages of their helper vertices, so the skeleton follows the body shape
- items (clothes, hair, shoes ...) = MakeHuman binding: each item vertex sits at a weighted
  point of three body vertices plus an offset scaled by the body's own measured size

Units are MakeHuman decimeters.
"""
import json, struct
from pathlib import Path
import numpy as np

TYPES = {"f4": np.float32, "u4": np.uint32}


def read_bin(path):
    data = Path(path).read_bytes()
    n = struct.unpack("<I", data[:4])[0]
    header = json.loads(data[4:4 + n])
    base = 4 + n
    arrays = {}
    for name, a in header["arrays"].items():
        dt = TYPES[a["type"]]
        arr = np.frombuffer(data, dtype=dt, count=a["count"], offset=base + a["offset"])
        arrays[name] = arr.reshape(a["shape"])
    return header, arrays


class Library:
    def __init__(self, root):
        self.root = Path(root)
        self.catalog = json.load(open(self.root / "catalog.json"))
        self.base_header, self.base = read_bin(self.root / "base.bin")
        self._targets = {}
        for g in self.catalog["targets"]:
            self._targets[g["group"]] = g

    def target(self, name):
        group = name.split("/")[0] if not name.startswith("pack/") else name.split("/")[1]
        g = self._targets.get(group)
        if g is None:
            raise KeyError("no target group for " + name)
        header, arrays = read_bin(self.root / g["file"])
        for r in header["targets"]:
            if r["name"] == name:
                s, c = r["start"], r["count"]
                return arrays["index"][s:s + c], arrays["delta"][s:s + c]
        raise KeyError(name)

    def body(self, targets):
        """targets: {name: weight}. Returns all base vertex positions (helpers included)."""
        v = self.base["allPositions"].astype(np.float64).copy()
        for name, w in targets.items():
            if w == 0:
                continue
            idx, d = self.target(name)
            v[idx] += w * d
        return v

    def skin_mesh(self, allpos):
        """Visible body mesh (unwelded positions, uvs, triangles) for a body."""
        return allpos[self.base["baseIndex"]], self.base["uvs"], self.base["triangles"].reshape(-1, 3)

    def joints(self, allpos):
        rig = json.load(open(self.root / "rig.json"))
        return {j: allpos[idx].mean(0) for j, idx in rig["joints"].items()}

    def item(self, item_id):
        meta = next(i for i in self.catalog["items"] if i["id"] == item_id)
        header, a = read_bin(self.root / meta["file"])
        return meta, header, a

    def fit_item(self, item_id, allpos):
        """Item vertex positions on this body (MakeHuman proxy binding)."""
        meta, header, a = self.item(item_id)
        bi, bw, off = a["bindIndex"].astype(np.int64), a["bindWeight"], a["bindOffset"].astype(np.float64)
        pts = (allpos[bi] * bw[..., None]).sum(1)
        # offsets scale with the body's own size along each axis, measured between reference vertices
        scale = np.ones(3)
        for k, (i1, i2, ref) in enumerate(header.get("scales") or []):
            if ref:
                scale[k] = abs(allpos[int(i1)][k] - allpos[int(i2)][k]) / float(ref)
        pts = pts + off * scale
        return meta, pts, a["uvs"], a["triangles"].reshape(-1, 3), a["deleteVerts"]


def adult(sex="male", muscle=0.5, weight=0.5, height=0.5, age="young"):
    """Macro targets for an adult: sex 'male'/'female', muscle/weight/height 0..1 (0.5 = average)."""
    t = {}
    for race in ("african", "asian", "caucasian"):
        t[f"macrodetails/{race}-{sex}-{age}"] = 1.0 / 3.0

    def blend(lo, mid, hi, x):
        # 0..0.5 blends lo->mid, 0.5..1 blends mid->hi
        if x < 0.5:
            return {lo: 1 - x * 2, mid: x * 2}
        return {mid: 2 - x * 2, hi: x * 2 - 1}
    for m, wm in blend("minmuscle", "averagemuscle", "maxmuscle", muscle).items():
        for wt, ww in blend("minweight", "averageweight", "maxweight", weight).items():
            if wm * ww > 0:
                t[f"macrodetails/universal-{sex}-{age}-{m}-{wt}"] = t.get(f"macrodetails/universal-{sex}-{age}-{m}-{wt}", 0) + wm * ww
                if height != 0.5:
                    hk = "maxheight" if height > 0.5 else "minheight"
                    t[f"macrodetails/height/{sex}-{age}-{m}-{wt}-{hk}"] = wm * ww * abs(height - 0.5) * 2
    return t

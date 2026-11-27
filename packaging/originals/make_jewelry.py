#!/usr/bin/env python3
"""Red Velvet original jewelry for the DMX Studio Character Library.

Generated from scratch (no third-party meshes), so these items are wholly Red Velvet Studios work.
Each item is built on the shared hm08 base body and saved in the library's flexible format
(every vertex bound to a base-body triangle + offset), so it follows any body shape.

  python3 make_jewelry.py --mh <makehuman data dir> --lib <library dir>
Adds items/rv_*/item.bin and appends catalog entries (slot "jewelry", license "Red Velvet original").
"""
import argparse, json, sys
from pathlib import Path
import numpy as np
from scipy.spatial import cKDTree

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "makehuman"))
from build_library import write_bin  # same binary layout as the rest of the library

REF_MACRO = "universal-male-young-averagemuscle-averageweight.target"
SCALE_PAIRS = {"x_scale": (5399, 11998), "y_scale": (791, 881), "z_scale": (962, 5320)}   # same as MakeHuman clothes

def read_base(mh):
    V = np.array([[float(x) for x in l.split()[1:4]] for l in open(mh / "3dobjs/base.obj") if l.startswith("v ")], np.float64)
    faces = []
    group = None
    global JOINTS
    JOINTS = {}
    for l in open(mh / "3dobjs/base.obj"):
        if l.startswith("g "): group = l.split()[1]
        elif l.startswith("f ") and group == "body":
            idx = [int(c.split("/")[0]) - 1 for c in l.split()[1:]]
            for k in range(1, len(idx) - 1): faces.append((idx[0], idx[k], idx[k + 1]))
        elif l.startswith("f ") and group and group.startswith("joint-"):
            JOINTS.setdefault(group, set()).update(int(c.split("/")[0]) - 1 for c in l.split()[1:])
    for l in open(mh / "targets/macrodetails" / REF_MACRO):
        if l[0] == "#" or not l.strip(): continue
        p = l.split(); V[int(p[0])] += [float(x) for x in p[1:4]]
    return V, np.array(faces)

def joint(V, name):
    return V[sorted(JOINTS[name])].mean(0)

def surface(V, F):
    body = np.unique(F)
    return body, cKDTree(V[body])

def bind(points, V, F):
    """Closest point on the body for each vertex -> (3 vertex ids, barycentric weights, offset)."""
    cent = V[F].mean(1); tree = cKDTree(cent)
    idx = np.zeros((len(points), 3), np.uint32); w = np.zeros((len(points), 3), np.float32); off = np.zeros((len(points), 3), np.float32)
    for i, p in enumerate(points):
        best = None
        for t in tree.query(p, 12)[1]:
            a, b, c = V[F[t]]
            # closest point on triangle (clamped barycentric)
            ab, ac, ap = b - a, c - a, p - a
            d00, d01, d11 = ab @ ab, ab @ ac, ac @ ac
            d20, d21 = ap @ ab, ap @ ac
            den = d00 * d11 - d01 * d01
            if den == 0: continue
            v = (d11 * d20 - d01 * d21) / den; u2 = (d00 * d21 - d01 * d20) / den
            v, u2 = np.clip(v, 0, 1), np.clip(u2, 0, 1)
            if v + u2 > 1: s = v + u2; v, u2 = v / s, u2 / s
            q = a + v * ab + u2 * ac
            dist = np.linalg.norm(p - q)
            if best is None or dist < best[0]: best = (dist, t, (1 - v - u2, v, u2), q)
        _, t, bw, q = best
        idx[i] = F[t]; w[i] = bw; off[i] = p - q
    return idx, w, off

def tube(path, radius, sides=8, closed=True):
    """Tube mesh along a polyline; returns positions, triangles, uvs."""
    n = len(path)
    T = np.gradient(path, axis=0) if not closed else (np.roll(path, -1, 0) - np.roll(path, 1, 0))
    T /= np.linalg.norm(T, axis=1, keepdims=True)
    ref = np.array([0, 0, 1.0]) if abs(T[0, 2]) < 0.9 else np.array([1.0, 0, 0])
    N = np.cross(T, ref); N /= np.linalg.norm(N, axis=1, keepdims=True)
    Bv = np.cross(T, N)
    ang = np.linspace(0, 2 * np.pi, sides, endpoint=False)
    pos = (path[:, None, :] + radius * (np.cos(ang)[None, :, None] * N[:, None, :] + np.sin(ang)[None, :, None] * Bv[:, None, :])).reshape(-1, 3)
    tris = []
    rings = n if closed else n - 1
    for i in range(rings):
        j = (i + 1) % n
        for k in range(sides):
            k2 = (k + 1) % sides
            a, b, c, d = i * sides + k, i * sides + k2, j * sides + k, j * sides + k2
            tris += [(a, c, b), (b, c, d)]
    uv = np.stack([np.repeat(np.linspace(0, 1, n), sides), np.tile(ang / (2 * np.pi), n)], 1)
    return pos, np.array(tris), uv

def smooth_closed(P, n):
    """Resample a closed control polygon to n points with Catmull-Rom smoothing."""
    m = len(P); out = []
    for i in range(m):
        p0, p1, p2, p3 = P[(i - 1) % m], P[i], P[(i + 1) % m], P[(i + 2) % m]
        for t in np.linspace(0, 1, max(2, n // m), endpoint=False):
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3))
    return np.array(out)

def rope_chain(V, F, drop_y=3.9, lift=0.3, rope_r=0.095, strand_r=0.06, twist=0.36):
    """Thick two-strand rope chain: around the back of the neck, draping in a U to mid-chest."""
    body, _ = surface(V, F)
    P = V[body]
    def front_z(x, y):  # outermost body point in front at (x, y)
        s = P[(np.abs(P[:, 0] - x) < 0.12) & (np.abs(P[:, 1] - y) < 0.12)]
        return s[:, 2].max() if len(s) else None
    def back_z(x, y):
        s = P[(np.abs(P[:, 0] - x) < 0.12) & (np.abs(P[:, 1] - y) < 0.12)]
        return s[:, 2].min() if len(s) else None
    ctrl = []
    top_y, half_w = 5.85, 0.62
    for x in np.linspace(-half_w, half_w, 15):                       # front U: sides high, center low
        y = drop_y + (top_y - drop_y) * (abs(x) / half_w) ** 1.7
        z = front_z(x, y); ctrl.append((x, y, z + lift))
    for phi in np.linspace(0.15, np.pi - 0.15, 7):                    # back of neck
        x = half_w * np.cos(phi); y = top_y + 0.12 * np.sin(phi)
        z = back_z(x, y); ctrl.append((x, y, z - lift * 0.6))
    path = smooth_closed(np.array(ctrl, float), 240)
    # two strands twisting around the path -> rope look
    T = np.roll(path, -1, 0) - np.roll(path, 1, 0); T /= np.linalg.norm(T, axis=1, keepdims=True)
    N = np.cross(T, [0, 0, 1.0]); N /= np.linalg.norm(N, axis=1, keepdims=True); Bv = np.cross(T, N)
    seg = np.r_[0, np.cumsum(np.linalg.norm(np.diff(path, axis=0), axis=1))]
    parts = []
    for phase in (0, np.pi):
        a = seg / twist * 2 * np.pi + phase
        strand = path + (rope_r - strand_r) * (np.cos(a)[:, None] * N + np.sin(a)[:, None] * Bv)
        parts.append(tube(strand, strand_r, 6))
    return merge(parts)

def watch(V, F, side=1):
    """Gold link band with a round face on the wrist (side=1 left arm, +x)."""
    body, _ = surface(V, F)
    P = V[body]
    lr = "l" if side == 1 else "r"
    elbow, hand = joint(V, f"joint-{lr}-elbow"), joint(V, f"joint-{lr}-hand")   # MakeHuman joint markers
    axis = (hand - elbow) / np.linalg.norm(hand - elbow)
    wrist_c = hand - axis * 0.35                                     # just above the wrist joint, on the forearm
    ring = P[np.abs((P - wrist_c) @ axis) < 0.08]
    ring = ring[np.linalg.norm(ring - wrist_c, axis=1) < 0.9]
    center = ring.mean(0)
    r = np.linalg.norm((ring - center) - np.outer((ring - center) @ axis, axis), axis=1).max() + 0.06
    e1 = np.cross(axis, [0, 1.0, 0]); e1 /= np.linalg.norm(e1); e2 = np.cross(axis, e1)
    ang = np.linspace(0, 2 * np.pi, 48, endpoint=False)
    parts = []
    for off in (-0.07, 0.0, 0.07):                                   # three rows of links -> band
        path = center + axis * off + r * (np.cos(ang)[:, None] * e1 + np.sin(ang)[:, None] * e2)
        parts.append(tube(path, 0.035, 6))
    # face on the back of the wrist: pick the ring direction facing most outward/up
    best = max(ang, key=lambda t: (np.cos(t) * e1 + np.sin(t) * e2) @ np.array([0, 0.6, 0.8]))
    out = np.cos(best) * e1 + np.sin(best) * e2
    fc = center + out * (r + 0.05)
    disc = np.linspace(0, 2 * np.pi, 32, endpoint=False)
    for k, (rad, h) in enumerate(((0.21, 0.0), (0.19, 0.06))):       # bezel ring + face plate
        p = fc + out * h + rad * (np.cos(disc)[:, None] * axis + np.sin(disc)[:, None] * np.cross(out, axis))
        parts.append(tube(p, 0.03 if k == 0 else 0.012, 6))
    # solid face plate (fan)
    rim = fc + out * 0.05 + 0.19 * (np.cos(disc)[:, None] * axis + np.sin(disc)[:, None] * np.cross(out, axis))
    pos = np.vstack([fc + out * 0.05, rim]); tris = np.array([(0, 1 + i, 1 + (i + 1) % 32) for i in range(32)])
    parts.append((pos, tris, np.zeros((len(pos), 2))))
    return merge(parts)


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t)

def quiff_undercut(V, F):
    """Short faded sides and back with a tall top swept up and back at the front (Red Velvet original).
    Built as a shell over the scalp region of the base head, so it fits every head shape."""
    c = joint(V, "joint-head") * 0 + np.array([0.0, (joint(V, "joint-head")[1] + joint(V, "joint-head-2")[1]) / 2, 0.55])
    top_y = V[np.unique(F)][:, 1].max()
    eye_y = joint(V, "joint-l-eye")[1]
    front_hl = eye_y + 0.68                                          # forehead hairline
    def in_scalp(p):
        d = p - c; phi = np.arctan2(d[0], d[2])                     # 0 = front
        f = (1 + np.cos(phi)) / 2
        hl = (eye_y - 0.55) + (front_hl - (eye_y - 0.55)) * f ** 0.7
        ear = abs(p[0]) > 0.78 and (eye_y - 0.4) < p[1] < (eye_y + 0.32)
        return p[1] > hl and not ear
    body = np.unique(F)
    keep = {i for i in body if in_scalp(V[i])}
    tris = np.array([t for t in F if all(i in keep for i in t)])
    ids = np.unique(tris); remap = {int(o): k for k, o in enumerate(ids)}
    P0 = V[ids].copy()
    tri = np.vectorize(remap.get)(tris)
    for _ in range(2):                                               # midpoint subdivision x2 -> smooth surface
        P0, tri = subdivide(P0, tri)
    out = P0 - c; out /= np.linalg.norm(out, axis=1, keepdims=True)
    y, x, z = P0[:, 1], np.abs(P0[:, 0]), P0[:, 2]
    top = smoothstep(front_hl - 0.3, front_hl + 0.1, y) * (1 - smoothstep(0.36, 0.6, x))
    front = smoothstep(-0.3, 1.35, z)
    crown = smoothstep(top_y - 0.5, top_y, y)
    fade = 0.02 + 0.035 * smoothstep(eye_y - 0.5, front_hl, y)
    t = fade + top * (0.10 + 0.20 * front + 0.04 * crown)
    sweep = (top * front ** 2)[:, None] * np.array([0, 0.16, -0.02])  # front lifts up and back
    P = P0 + out * t[:, None] + sweep
    P = laplacian(P, tri, 6, 0.5)
    return P, tri, np.zeros((len(P), 2))

def subdivide(P, T):
    edges = {}; newP = list(P); out = []
    def mid(a, b):
        k = (min(a, b), max(a, b))
        if k not in edges: edges[k] = len(newP); newP.append((P[a] + P[b]) / 2)
        return edges[k]
    for a, b, c in T:
        ab, bc, ca = mid(a, b), mid(b, c), mid(c, a)
        out += [(a, ab, ca), (ab, b, bc), (ca, bc, c), (ab, bc, ca)]
    return np.array(newP), np.array(out)

def laplacian(P, T, iters, lam):
    n = len(P); nb = [set() for _ in range(n)]
    for a, b, c in T: nb[a] |= {b, c}; nb[b] |= {a, c}; nb[c] |= {a, b}
    deg = np.array([len(x) for x in nb]); border = set()
    from collections import Counter
    ec = Counter(tuple(sorted(e)) for a, b, c in T for e in ((a, b), (b, c), (c, a)))
    for (a, b), k in ec.items():
        if k == 1: border |= {a, b}
    idx = [list(x) for x in nb]
    for _ in range(iters):
        avg = np.array([P[i].mean(0) if i else p for p, i in zip(P, idx)])
        m = np.ones(n); m[list(border)] = 0
        P = P + lam * m[:, None] * (avg - P)
    return P

def merge(parts):
    pos, tris, uvs, base = [], [], [], 0
    for p, t, u in parts:
        pos.append(p); tris.append(t + base); uvs.append(u); base += len(p)
    return np.vstack(pos), np.vstack(tris), np.vstack(uvs)

def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--mh", required=True); ap.add_argument("--lib", required=True)
    a = ap.parse_args(); mh, lib = Path(a.mh), Path(a.lib)
    V, F = read_base(mh)
    scales = {k: [i, j, float(abs(V[i][{'x_scale': 0, 'y_scale': 1, 'z_scale': 2}[k]] - V[j][{'x_scale': 0, 'y_scale': 1, 'z_scale': 2}[k]]))] for k, (i, j) in SCALE_PAIRS.items()}
    cat = json.load(open(lib / "catalog.json"))
    cat["items"] = [i for i in cat["items"] if not i["id"].startswith("rv_")]
    cat.setdefault("licenses", {})["Red Velvet original"] = "Original work of Red Velvet Studios"
    made = [("rv_gold_rope_chain", "Gold rope chain", rope_chain(V, F), ["chain", "necklace", "gold", "hip-hop", "streetwear"]),
            ("rv_gold_watch", "Gold watch", watch(V, F), ["watch", "gold", "wrist"]),
            ("rv_quiff_undercut", "Quiff undercut", quiff_undercut(V, F), ["hair", "short", "quiff", "undercut", "male"])]
    for iid, name, (pos, tris, uv), tags in made:
        idx, w, off = bind(pos, V, F)
        write_bin(lib / "items" / iid / "item.bin",
                  {"kind": "item", "id": iid, "scales": [scales["x_scale"], scales["y_scale"], scales["z_scale"]], "zDepth": "60"},
                  {"positions": pos.astype(np.float32), "uvs": uv.astype(np.float32), "triangles": tris.astype(np.uint32).reshape(-1),
                   "bindIndex": idx, "bindWeight": w, "bindOffset": off, "deleteVerts": np.zeros(0, np.uint32)})
        slot = "hair" if "hair" in tags else "jewelry"
        cat["items"].append({"id": iid, "name": name, "slot": slot, "pack": "red-velvet-originals", "license": "Red Velvet original",
                             "author": "Red Velvet Studios", "tags": tags, "styles": ["hip-hop", "glam"], "gender": "any",
                             "file": f"items/{iid}/item.bin", "textures": {}, "thumb": None, "transparent": False,
                             "diffuseColor": [0.32, 0.22, 0.13] if slot == "hair" else [0.93, 0.70, 0.28], "metal": slot != "hair", "roughness": 0.6 if slot == "hair" else 0.28, "vertices": int(len(pos))})
        print(iid, len(pos), "verts", len(tris), "tris", "max offset", float(np.linalg.norm(off, axis=1).max()))
    json.dump(cat, open(lib / "catalog.json", "w"), indent=1)

if __name__ == "__main__":
    main()

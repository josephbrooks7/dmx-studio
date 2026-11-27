"""Pose the hm08 body with MakeHuman's default skeleton (linear blend skinning).

pose(V, spec) -> posed copy of V. spec: {"aim": {bone: target_direction_or_point, ...}} using
helper aims for arms, or {"rot": {bone: (axis, degrees)}} for plain rotations (world rest frame).
"""
import json, numpy as np
import os
MH = os.environ.get('MH_DATA', 'makehuman/data')
SKEL = json.load(open(MH + '/rigs/default.mhskel'))
WTS = json.load(open(MH + '/rigs/default_weights.mhw'))['weights']
BONES = SKEL['bones']
CHILDREN = {}
for b, d in BONES.items():
    CHILDREN.setdefault(d['parent'], []).append(b)

def joint(V, name):
    return V[SKEL['joints'][name]].mean(0)

def head(V, b): return joint(V, BONES[b]['head'])
def tail(V, b): return joint(V, BONES[b]['tail'])

def descendants(b):
    out = [b]
    for c in CHILDREN.get(b, []): out += descendants(c)
    return out

def align(a, b):
    """Rotation matrix turning direction a onto direction b (shortest arc)."""
    a = a / np.linalg.norm(a); b = b / np.linalg.norm(b)
    v = np.cross(a, b); c = a @ b
    if np.linalg.norm(v) < 1e-9: return np.eye(3)
    vx = np.array([[0, -v[2], v[1]], [v[2], 0, -v[0]], [-v[1], v[0], 0]])
    return np.eye(3) + vx + vx @ vx * (1 / (1 + c))

def axis_angle(axis, deg):
    a = np.array(axis, float); a /= np.linalg.norm(a); t = np.radians(deg)
    K = np.array([[0, -a[2], a[1]], [a[2], 0, -a[0]], [-a[1], a[0], 0]])
    return np.eye(3) + np.sin(t) * K + (1 - np.cos(t)) * K @ K

def about(R, p):
    M = np.eye(4); M[:3, :3] = R; M[:3, 3] = p - R @ p; return M

def apply(M, p): return M[:3, :3] @ p + M[:3, 3]

def pose(V, spec):
    G = {b: np.eye(4) for b in BONES}
    def push(b, M):                       # left-multiply b and everything below it
        for d in descendants(b): G[d] = M @ G[d]
    for b, (axis, deg) in spec.get("rot", {}).items():
        push(b, about(axis_angle(axis, deg), apply(G[b], head(V, b))))
    # two-bone arm aims: {"L": {"elbow": point, "wrist": point}} in rest-body coordinates
    for side, tgt in spec.get("arms", {}).items():
        up, lo, hd = f"upperarm01.{side}", f"lowerarm01.{side}", f"wrist.{side}"
        sh = apply(G[up], head(V, up))
        el = apply(G[lo], head(V, lo))
        push(up, about(align(el - sh, tgt["elbow"] - sh), sh))
        el = apply(G[lo], head(V, lo)); wr = apply(G[hd], head(V, hd))
        push(lo, about(align(wr - el, tgt["wrist"] - el), el))
        if "hand_dir" in tgt:
            wr = apply(G[hd], head(V, hd)); fe = apply(G[hd], tail(V, hd))
            push(hd, about(align(fe - wr, np.array(tgt["hand_dir"], float)), wr))
    # finger curls: {"L": {"finger2": 25, "finger3": 70, ...}} degrees per joint, around the knuckle line
    for side, curls in spec.get("fingers", {}).items():
        k2 = apply(G[f"finger2-1.{side}"], head(V, f"finger2-1.{side}"))
        k5 = apply(G[f"finger5-1.{side}"], head(V, f"finger5-1.{side}"))
        axis = (k5 - k2) / np.linalg.norm(k5 - k2)
        if side == "R": axis = -axis
        for f, deg in curls.items():
            for seg in (1, 2, 3):
                b = f"{f}-{seg}.{side}"
                ax = axis if f != "finger1" else np.array(spec.get("thumb_axis", {}).get(side, axis))
                push(b, about(axis_angle(ax, deg), apply(G[b], head(V, b))))
    # skin
    out = np.zeros_like(V); tot = np.zeros(len(V))
    for b, lst in WTS.items():
        if b not in G or not lst: continue
        a = np.array(lst); idx = a[:, 0].astype(int); w = a[:, 1]
        M = G[b]
        out[idx] += w[:, None] * (V[idx] @ M[:3, :3].T + M[:3, 3])
        tot[idx] += w
    missing = tot < 1e-6
    out[~missing] /= tot[~missing][:, None]
    out[missing] = V[missing]
    return out

"""Render MakeHuman library bodies dressed in library items (Blender, review only).

usage: blender --background --python render_mh_review.py -- LIBRARY_DIR OUT_DIR
Renders an average young adult man and woman, each in a top, bottom, shoes, hair, brows and
lashes picked from the catalog, front / side / back. Prints what was used.
"""
import sys, json
from pathlib import Path
import bpy
import numpy as np
sys.path.insert(0, str(Path(__file__).parent))
import mhbody

lib_dir, out_dir = (Path(p) for p in sys.argv[sys.argv.index("--") + 1:])
out_dir.mkdir(parents=True, exist_ok=True)
lib = mhbody.Library(lib_dir)
items = lib.catalog["items"]


def pick(slot, sex, prefer=(), avoid=()):
    cands = [i for i in items if i["slot"] == slot and i["gender"] in (sex, "any")
             and not any(a in i["name"].lower() for a in avoid)]
    for word in prefer:
        for i in cands:
            if word in i["name"].lower():
                return i
    return cands[0] if cands else None


def material(name, tex=None, color=(0.8, 0.8, 0.8), alpha=False):
    m = bpy.data.materials.new(name); m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 0.7
    if tex and Path(tex).exists():
        img = bpy.data.images.load(str(tex))
        n = m.node_tree.nodes.new("ShaderNodeTexImage"); n.image = img
        m.node_tree.links.new(n.outputs["Color"], bsdf.inputs["Base Color"])
        if alpha:
            m.node_tree.links.new(n.outputs["Alpha"], bsdf.inputs["Alpha"])
            m.blend_method = "HASHED" if hasattr(m, "blend_method") else None
    else:
        bsdf.inputs["Base Color"].default_value = (*color, 1)
    return m


def add_mesh(name, pos, uv, tris, mat, offset_x):
    me = bpy.data.meshes.new(name)
    p = [(float(x) + offset_x, -float(z), float(y)) for x, y, z in pos]   # MakeHuman Y-up -> Blender Z-up
    me.from_pydata(p, [], [tuple(int(i) for i in t) for t in tris])
    me.update()
    if uv is not None and len(uv) == len(pos):
        layer = me.uv_layers.new(name="UV")
        for poly in me.polygons:
            for li in poly.loop_indices:
                vi = me.loops[li].vertex_index
                layer.data[li].uv = (float(uv[vi][0]), float(uv[vi][1]))
    for poly in me.polygons:
        poly.use_smooth = True
    ob = bpy.data.objects.new(name, me)
    ob.data.materials.append(mat)
    bpy.context.scene.collection.objects.link(ob)
    return ob


bpy.ops.wm.read_factory_settings(use_empty=True)
report = {}
skins = lib.catalog["skins"]
for k, sex in enumerate(("male", "female")):
    x = -4.5 if sex == "male" else 4.5
    allpos = lib.body(mhbody.adult(sex))
    pos, uv, tris = lib.skin_mesh(allpos)
    used = {}
    hidden = set()
    for slot, prefer, avoid in (("top", ("tshirt", "shirt", "tee"), ("tucked",)), ("bottom", ("jean", "pant", "trouser"), ("short",)),
                                ("shoes", ("sneaker", "shoe"), ()),
                                ("hair", ("short", "bob") if sex == "male" else ("long", "ponytail"), ()),
                                ("eyebrows", (), ()), ("eyelashes", (), ())):
        it = pick(slot, sex, prefer, avoid)
        if not it:
            continue
        meta, ipos, iuv, itri, dele = lib.fit_item(it["id"], allpos)
        hidden.update(int(d) for d in dele)
        tex = lib_dir / it["textures"]["diffuseTexture"] if "diffuseTexture" in it.get("textures", {}) else None
        add_mesh(f"{sex}_{slot}", ipos, iuv, itri,
                 material(f"{sex}_{slot}", tex, tuple(it.get("diffuseColor", (0.8, 0.8, 0.8))), it.get("transparent", False)), x)
        used[slot] = it["name"]
    # hide body skin covered by the items (MakeHuman delete_verts), anatomy itself unchanged
    base_idx = lib.base["baseIndex"]
    keep = np.array([not (set(base_idx[t].tolist()) & hidden) for t in tris]) if hidden else np.ones(len(tris), bool)
    import re as _re
    def is_sex(sk):
        words = _re.findall(r"[a-z]+", (sk["name"] + " " + sk["id"]).lower())
        return sex in words
    skin = next((sk for sk in skins if is_sex(sk) and "young" in sk["name"].lower()),
                next((sk for sk in skins if is_sex(sk) and "old" not in sk["name"].lower()), skins[0] if skins else None))
    add_mesh(f"{sex}_body", pos, uv, tris[keep],
             material(f"{sex}_skin", lib_dir / skin["texture"] if skin else None, (0.8, 0.62, 0.52)), x)
    used["skin"] = skin["name"] if skin else "none"
    ys = pos[:, 1]
    used["heightCm"] = round(float(ys.max() - ys.min()) * 10, 1)
    report[sex] = used

scene = bpy.context.scene
scene.render.engine = "CYCLES"; scene.cycles.samples = 24; scene.cycles.use_denoising = True
scene.render.resolution_x = 1200; scene.render.resolution_y = 900
scene.world = bpy.data.worlds.new("w"); scene.world.use_nodes = True
scene.world.node_tree.nodes["Background"].inputs[0].default_value = (.18, .18, .18, 1)
from mathutils import Vector
zs = [v.co.z for o in scene.objects if o.type == "MESH" for v in o.data.vertices]
xs = [v.co.x for o in scene.objects if o.type == "MESH" for v in o.data.vertices]
zlo, zhi = min(zs), max(zs)
center = Vector(((min(xs) + max(xs)) / 2, 0, (zlo + zhi) / 2))


def aim(o, p):
    o.rotation_euler = (p - o.location).to_track_quat("-Z", "Y").to_euler()


for name, off, power in [("Key", (10, -25, 20), 9000), ("Fill", (-15, -15, 8), 4000), ("Rim", (5, 20, 15), 6000)]:
    L = bpy.data.lights.new(name, "AREA"); L.energy = power; L.size = 10
    o = bpy.data.objects.new(name, L); scene.collection.objects.link(o)
    o.location = center + Vector(off); aim(o, center)
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); cam.data.type = "ORTHO"; cam.data.ortho_scale = max((zhi - zlo) * 1.12 * 1200 / 900, (max(xs) - min(xs)) * 1.08)
scene.collection.objects.link(cam); scene.camera = cam
for angle, off in (("front", (0, -40, 0)), ("side", (40, 0, 0)), ("back", (0, 40, 0))):
    cam.location = center + Vector(off); aim(cam, center)
    scene.render.filepath = str((out_dir / f"makehuman-{angle}.png").resolve())
    bpy.ops.render.render(write_still=True)
(out_dir / "review.json").write_text(json.dumps(report, indent=2) + "\n")
print("MH_REVIEW", json.dumps(report))

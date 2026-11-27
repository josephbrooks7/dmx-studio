"""Fit a rigged garment from one runtime character onto another character's body.

No garment needs to exist on the target body. Steps:
1. Skeleton retarget: each vertex follows its own skin weights from the source
   rest skeleton to the target rest skeleton (same Mixamo bone names), so sleeves
   follow the target's arms and legs follow its legs instead of a bounding box.
2. Body-surface fit: each vertex keeps its original ease (distance off the source
   body) but measured from the target body, so a bust, chest, stomach or hips
   shape the garment instead of being flattened by it.
3. The fit correction is smoothed across the garment so edges stay continuous,
   then any point still inside the target body is pushed out to a minimum clearance.
Topology, UVs, materials and skin weights are kept; the output is bound to the
target rig.

usage: blender --background --python fit-garment-cross-body.py -- SOURCE.glb TARGET.glb GARMENT OUTDIR
"""
import sys, json
from pathlib import Path
import bpy
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree

BODY_PROXY = "Outfit_original"     # the full, close-fitting body surface each character carries
MIN_EASE = 0.006                   # fabric never sits closer than 6 mm to the body
LINER_EASE = 0.0015               # the liner hugs the body, well inside every garment
CLEARANCE = 0.007                  # garment surface stays at least 7 mm off the body (liner at 1.5 mm)
FREE_START, FREE_END = 0.035, 0.09 # fabric hanging this far off the body (hems, cuffs) keeps its retargeted shape


def load(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(path.resolve()))
    return set(bpy.data.objects) - before


def named(objects, name):
    found = [o for o in objects if o.type == "MESH" and o.name.split(".")[0] == name]
    if len(found) != 1:
        raise ValueError(f"Expected one {name}, found {len(found)}")
    return found[0]


def rig_of(obj):
    mods = [m for m in obj.modifiers if m.type == "ARMATURE" and m.object]
    if len(mods) != 1:
        raise ValueError("Expected one armature on " + obj.name)
    return mods[0].object


def world_points(obj):
    return [obj.matrix_world @ v.co for v in obj.data.vertices]


def surface(obj):
    """The body as a searchable surface, with its normals checked to point outward."""
    pts = world_points(obj)
    obj.data.calc_loop_triangles()
    tris = [tuple(t.vertices) for t in obj.data.loop_triangles]
    cx = sum(p.x for p in pts) / len(pts); cy = sum(p.y for p in pts) / len(pts)
    outward = 0
    for t in tris:
        a, b, c = (pts[i] for i in t)
        n = (b - a).cross(c - a)
        m = (a + b + c) / 3
        outward += 1 if n.dot(Vector((m.x - cx, m.y - cy, 0))) > 0 else -1
    return BVHTree.FromPolygons(pts, tris, all_triangles=True), (1.0 if outward >= 0 else -1.0)


def signed_offset(body, p):
    tree, sign = body
    near, normal, _, dist = tree.find_nearest(p)
    if near is None:
        raise ValueError("Body surface not found")
    normal = normal * sign
    return near, normal, (p - near).dot(normal)


def plain_fabric(source):
    color = [0.8, 0.8, 0.8, 1.0]
    if source and source.use_nodes:
        for node in source.node_tree.nodes:
            if node.type == "BSDF_PRINCIPLED":
                base = node.inputs["Base Color"]
                image = next((l.from_node.image for l in base.links if getattr(l.from_node, "image", None)), None)
                if image and image.size[0] > 0:
                    px = list(image.pixels[:])
                    n = len(px) // 4
                    step = max(1, n // 20000)
                    samples = [px[i * 4:i * 4 + 3] for i in range(0, n, step) if px[i * 4 + 3] > 0.5]
                    if samples:
                        color = [sum(c[k] for c in samples) / len(samples) for k in range(3)] + [1.0]
                else:
                    color = list(base.default_value)
    m = bpy.data.materials.new("Liner_fabric")
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Roughness"].default_value = 0.85
    return m


def main():
    src_path, dst_path, garment_name, out = sys.argv[sys.argv.index("--") + 1:]
    src_path, dst_path, out = Path(src_path), Path(dst_path), Path(out)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    src_objs = load(src_path)
    dst_objs = load(dst_path)
    bpy.context.view_layer.update()

    garment = named(src_objs, garment_name)
    src_rig = rig_of(garment)
    src_body = named(src_objs, BODY_PROXY)
    dst_body = named(dst_objs, BODY_PROXY)
    dst_rig = rig_of(dst_body)
    src_tree, dst_tree = surface(src_body), surface(dst_body)

    # rest transforms per bone, in world space
    def rest(rig):
        return {b.name: rig.matrix_world @ b.matrix_local for b in rig.data.bones}
    src_rest, dst_rest = rest(src_rig), rest(dst_rig)
    # Each bone carries its stretch too: a bone's local Y axis runs along its length, so scaling
    # local Y by the length ratio makes a sleeve or trouser leg longer on longer arms or legs.
    def length_ratio(n):
        a, b = src_rig.data.bones[n].length, dst_rig.data.bones[n].length
        return min(max(b / a, 0.6), 1.6) if a > 1e-5 else 1.0
    deltas = {n: dst_rest[n] @ Matrix.Diagonal((1, length_ratio(n), 1, 1)) @ src_rest[n].inverted()
              for n in src_rest if n in dst_rest}
    bone_length_ratios = {n: round(length_ratio(n), 3) for n in deltas
                          if any(k in n for k in ("Arm", "ForeArm", "UpLeg", "Leg", "Spine"))}

    mesh = garment.data
    groups = {g.index: g.name for g in garment.vertex_groups}
    src_pts = world_points(garment)
    retarget, ease, free = [], [], []
    unmatched = 0
    for v, p in zip(mesh.vertices, src_pts):
        acc, total = Vector((0, 0, 0)), 0.0
        for g in v.groups:
            d = deltas.get(groups.get(g.group))
            if d is not None and g.weight > 0:
                acc += (d @ p) * g.weight
                total += g.weight
        if total <= 0:
            unmatched += 1
            acc, total = p.copy(), 1.0
        retarget.append(acc / total)
        _, _, off = signed_offset(src_tree, p)
        ease.append(max(off, MIN_EASE))
        # how much this vertex is "worn on the body" (1) versus hanging free (0)
        free.append(min(max((off - FREE_START) / (FREE_END - FREE_START), 0.0), 1.0))

    # Around the feet the body surface is the shoe, so fitting there would flare trouser hems.
    # Vertices mostly driven by foot bones follow the skeleton only.
    def foot_share(v):
        total = sum(g.weight for g in v.groups) or 1.0
        return sum(g.weight for g in v.groups if "Foot" in groups.get(g.group, "") or "Toe" in groups.get(g.group, "")) / total
    feet = [foot_share(v) for v in mesh.vertices]
    if garment_name != "Shoes":
        free = [max(f, min(1.0, ft * 2)) for f, ft in zip(free, feet)]

    # fit correction toward the target body, keeping the original ease
    delta = []
    for q, e, f in zip(retarget, ease, free):
        near, normal, _ = signed_offset(dst_tree, q)
        fitted = near + normal * e
        delta.append((fitted - q) * (1.0 - f))

    # smooth the correction across the garment so neighbouring vertices move together
    neighbours = [[] for _ in mesh.vertices]
    for e in mesh.edges:
        a, b = e.vertices
        neighbours[a].append(b); neighbours[b].append(a)
    for _ in range(12):
        delta = [d.lerp(sum((delta[j] for j in nb), Vector((0, 0, 0))) / len(nb), 0.5) if nb else d
                 for d, nb in zip(delta, neighbours)]
    final = [q + d for q, d in zip(retarget, delta)]

    # clearance: nothing stays inside the target body
    pushed, worst_inside = 0, 0.0
    for i, p in enumerate(final):
        near, normal, off = signed_offset(dst_tree, p)
        if garment_name != "Shoes" and feet[i] > 0.3:
            continue
        if off < CLEARANCE * 0.8:
            worst_inside = min(worst_inside, off)
            final[i] = near + normal * CLEARANCE
            pushed += 1
    # one light relaxation after pushing, re-checking clearance
    for _ in range(2):
        relaxed = [p.lerp(sum((final[j] for j in nb), Vector((0, 0, 0))) / len(nb), 0.25) if nb else p
                   for p, nb in zip(final, neighbours)]
        for i, p in enumerate(relaxed):
            if garment_name != "Shoes" and feet[i] > 0.3:
                final[i] = p
                continue
            near, normal, off = signed_offset(dst_tree, p)
            final[i] = p if off >= CLEARANCE * 0.8 else near + normal * CLEARANCE

    covering = {"hand": 0, "head": 0}
    for v in mesh.vertices:
        best = max(v.groups, key=lambda g: g.weight, default=None)
        name = groups.get(best.group, "") if best else ""
        if "Hand" in name:
            covering["hand"] += 1
        elif name.endswith("Head") or "Bip01" in name:
            covering["head"] += 1

    # build the fitted garment bound to the target rig, original weights/UVs/materials kept
    out_mesh = mesh.copy()
    inv = garment.matrix_world.inverted()   # vertex coords stay in the garment's object space
    fitted = bpy.data.objects.new("Fitted_" + garment_name, out_mesh)
    bpy.context.scene.collection.objects.link(fitted)
    fitted.matrix_world = Matrix.Identity(4)
    for v, p in zip(out_mesh.vertices, final):
        v.co = p
    out_mesh.update()
    for g in garment.vertex_groups:
        fitted.vertex_groups.new(name=g.name)
    for v in mesh.vertices:
        for g in v.groups:
            fitted.vertex_groups[groups[g.group]].add([v.index], g.weight, "REPLACE")
    fitted.parent = dst_rig
    fitted.matrix_parent_inverse = dst_rig.matrix_world.inverted()
    mod = fitted.modifiers.new("Target rig", "ARMATURE"); mod.object = dst_rig

    # Liner: the target's own garment in this slot, pulled in to hug its body and given the new
    # garment's fabric. Each body's skin mesh has holes where its own clothes sit; the liner closes
    # them wherever the new garment is cut differently (neckline, hem, sleeve length).
    liner = None
    own = [o for o in dst_objs if o.type == "MESH" and o.name.split(".")[0] == garment_name]
    if own and garment_name != "Shoes":
        own = own[0]
        liner_mesh = own.data.copy()
        liner = bpy.data.objects.new("Liner_" + garment_name, liner_mesh)
        bpy.context.scene.collection.objects.link(liner)
        liner.matrix_world = Matrix.Identity(4)
        for v in liner_mesh.vertices:
            p = own.matrix_world @ v.co
            near, normal, _ = signed_offset(dst_tree, p)
            v.co = near + normal * LINER_EASE
        # The liner's UV layout belongs to a different garment, so the new garment's texture would land
        # on the wrong regions. Give it a plain fabric color: the average of the garment's base color.
        liner_mesh.materials.clear()
        liner_mesh.materials.append(plain_fabric(mesh.materials[0] if mesh.materials else None))
        for poly in liner_mesh.polygons:
            poly.material_index = 0
        liner_mesh.update()
        # the liner stops at the ankle: remove faces mostly driven by the feet
        import bmesh
        own_g = {g.index: g.name for g in own.vertex_groups}
        def own_foot(v):
            t = sum(g.weight for g in v.groups) or 1.0
            return sum(g.weight for g in v.groups if "Foot" in own_g.get(g.group, "") or "Toe" in own_g.get(g.group, "")) / t
        drop = {v.index for v in own.data.vertices if own_foot(v) > 0.3}
        if drop:
            bm = bmesh.new(); bm.from_mesh(liner_mesh); bm.verts.ensure_lookup_table()
            bmesh.ops.delete(bm, geom=[bm.verts[i] for i in drop], context="VERTS")
            bm.to_mesh(liner_mesh); bm.free(); liner_mesh.update()
        # the copied mesh already carries the weights; recreate the group names in the same order
        for g in sorted(own.vertex_groups, key=lambda g: g.index):
            liner.vertex_groups.new(name=g.name)
        liner.parent = dst_rig
        liner.matrix_parent_inverse = dst_rig.matrix_world.inverted()
        lm = liner.modifiers.new("Target rig", "ARMATURE"); lm.object = dst_rig

    assert len(out_mesh.vertices) == len(mesh.vertices) and len(out_mesh.polygons) == len(mesh.polygons)
    assert list(out_mesh.materials) == list(mesh.materials)
    moved = [(a - b).length for a, b in zip(final, retarget)]
    report = {
        "source": src_path.name, "target": dst_path.name, "garment": garment_name,
        "vertices": len(final), "faces": len(out_mesh.polygons),
        "vertices_without_matching_bones": unmatched,
        "vertices_pushed_out_of_body": pushed, "deepest_penetration_before_fix_m": round(-worst_inside, 4),
        "max_body_fit_correction_m": round(max(moved), 4),
        "bone_length_ratios": bone_length_ratios,
        # Features must stay visible: garment vertices mostly driven by hand, finger or head bones
        # mean a sleeve or collar is swallowing a hand or the face.
        "vertices_covering_hands": covering["hand"], "vertices_covering_head": covering["head"],
        "liner": liner.name if liner else None,
        "degenerate_faces": sum(1 for p in out_mesh.polygons if p.area < 1e-10),
        "method": "skeleton retarget + body-surface ease transfer + smoothed correction + clearance",
    }
    out.mkdir(parents=True, exist_ok=True)
    (out / "fit-report.json").write_text(json.dumps(report, indent=2) + "\n")
    bpy.ops.object.select_all(action="DESELECT")
    fitted.select_set(True); dst_rig.select_set(True)
    if liner:
        liner.select_set(True)
    bpy.context.view_layer.objects.active = fitted
    bpy.ops.export_scene.gltf(filepath=str((out / f"{garment_name}.glb").resolve()), export_format="GLB",
                              use_selection=True, export_animations=False, export_skins=True)
    print("GARMENT_FIT_DONE", json.dumps(report))
    if garment_name != "Shoes" and (covering["hand"] > 0 or covering["head"] > 0):
        raise SystemExit(f"Garment covers hands or head: {covering}")


if __name__ == "__main__":
    main()

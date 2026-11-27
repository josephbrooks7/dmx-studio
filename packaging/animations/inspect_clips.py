"""Blender: inspect a folder of GLB animation clips and render review frames.

Usage: blender --background --factory-startup --python inspect_clips.py -- <glb_dir> <out_dir>

Writes <out_dir>/clips.json (per-file actions, frame ranges, bone names) and
<out_dir>/frames/<clip>_<n>.png (several frames of selected clips on the mannequin).
"""
import bpy, sys, os, json, math, re

argv = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT = argv[0], argv[1]
os.makedirs(os.path.join(OUT, "frames"), exist_ok=True)


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def glbs():
    found = []
    for root, _, files in os.walk(SRC):
        for f in sorted(files):
            if f.lower().endswith((".glb", ".gltf")):
                found.append(os.path.join(root, f))
    return found


files = glbs()
print("CLIPS files", len(files))
report = {"files": [], "bones": None, "mannequin": None}

# Pass 1: inventory every file on its own.
for path in files:
    reset()
    try:
        bpy.ops.import_scene.gltf(filepath=path)
    except Exception as e:  # keep going, record the failure
        report["files"].append({"file": os.path.relpath(path, SRC), "error": str(e)})
        continue
    arms = [o for o in bpy.data.objects if o.type == "ARMATURE"]
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    entry = {
        "file": os.path.relpath(path, SRC),
        "meshes": len(meshes),
        "vertices": sum(len(m.data.vertices) for m in meshes),
        "armatures": len(arms),
        "actions": [
            {"name": a.name, "frames": [int(a.frame_range[0]), int(a.frame_range[1])],
             "fcurves": len(a.fcurves)}
            for a in bpy.data.actions
        ],
    }
    if arms and report["bones"] is None:
        report["bones"] = [b.name for b in arms[0].data.bones]
    if meshes and arms and report["mannequin"] is None:
        report["mannequin"] = entry["file"]
    report["files"].append(entry)

json.dump(report, open(os.path.join(OUT, "clips.json"), "w"), indent=2)
print("CLIPS bones", len(report["bones"] or []), "mannequin", report["mannequin"])

# Pass 2: put chosen clips on the mannequin and render a few frames of each.
if report["mannequin"]:
    reset()
    bpy.ops.import_scene.gltf(filepath=os.path.join(SRC, report["mannequin"]))
    rig = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    keep = set(bpy.data.objects)
    # Load every clip's actions into this file.
    for path in files:
        if os.path.relpath(path, SRC) == report["mannequin"]:
            continue
        before = set(bpy.data.objects)
        try:
            bpy.ops.import_scene.gltf(filepath=path)
        except Exception:
            continue
        for a in bpy.data.actions:
            a.use_fake_user = True
        for o in set(bpy.data.objects) - before:
            bpy.data.objects.remove(o, do_unlink=True)

    wanted = re.compile(r"idle|walk|dance|run|crouch|sit|jump|pick", re.I)
    chosen, seen = [], set()
    for a in bpy.data.actions:
        key = re.sub(r"\W+", "", a.name.lower())
        if wanted.search(a.name) and key not in seen:
            chosen.append(a)
            seen.add(key)
    chosen = chosen[:10]

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "OBJECT"
    scene.render.resolution_x, scene.render.resolution_y = 360, 540
    for o in bpy.data.objects:
        if o.type == "MESH":
            o.color = (0.75, 0.62, 0.55, 1)
    cam_data = bpy.data.cameras.new("cam")
    cam = bpy.data.objects.new("cam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam

    # Frame from the mesh bounds in rest pose.
    import mathutils
    pts = []
    for o in bpy.data.objects:
        if o.type == "MESH":
            pts += [o.matrix_world @ mathutils.Vector(c) for c in o.bound_box]
    lo = mathutils.Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = mathutils.Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    centre, height = (lo + hi) / 2, hi.z - lo.z
    cam_data.lens = 50
    dist = height * 2.4
    cam.location = (centre.x + dist * 0.5, centre.y - dist, centre.z + height * 0.05)
    direction = centre - cam.location
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()

    rig.animation_data_create()
    rendered = []
    for a in chosen:
        rig.animation_data.action = a
        f0, f1 = int(a.frame_range[0]), int(a.frame_range[1])
        safe = re.sub(r"[^A-Za-z0-9]+", "_", a.name).strip("_")
        for i, f in enumerate(sorted({f0, (f0 + f1) // 2, f1 - 1 if f1 - 1 > f0 else f1})):
            scene.frame_set(f)
            scene.render.filepath = os.path.join(OUT, "frames", f"{safe}_{i}.png")
            bpy.ops.render.render(write_still=True)
        rendered.append(a.name)
    report["rendered"] = rendered
    json.dump(report, open(os.path.join(OUT, "clips.json"), "w"), indent=2)
    print("CLIPS rendered", rendered)

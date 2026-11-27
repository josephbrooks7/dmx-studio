"""Render a target character in its own garment and in a cross-body fitted garment.

The target's own garment in the same slot is hidden; the exposed-skin mesh that matches
the top being worn is shown (Skin_tee for tees, Skin_shirt for shirts).

usage: blender --background --python render-garment-fit-review.py -- TARGET.glb FITTED.glb GARMENT OUTDIR
"""
import sys
from pathlib import Path
import bpy
from mathutils import Vector

TOP_SKIN = {"Top_tee": "Skin_tee", "Top_shirt": "Skin_shirt"}


def load(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(path.resolve()))
    return set(bpy.data.objects) - before


def named(objects, name):
    found = [o for o in objects if o.type == "MESH" and o.name.split(".")[0] == name]
    if len(found) != 1:
        raise ValueError(f"Expected one {name}")
    return found[0]


def main():
    target, fitted_path, garment, out = sys.argv[sys.argv.index("--") + 1:]
    target, fitted_path, out = Path(target), Path(fitted_path), Path(out)
    out.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    objects = load(target)
    top = garment if garment in TOP_SKIN else "Top_tee"
    visible = {"Body", "Hair", TOP_SKIN[top], top, "Trousers", "Shoes"}
    for o in objects:
        if o.type == "MESH":
            o.hide_render = o.name.split(".")[0] not in visible
    own = named(objects, garment)
    fitted = named(load(fitted_path), "Fitted_" + garment)
    bpy.context.view_layer.update()
    pts = [o.matrix_world @ v.co for o in objects if o.type == "MESH" and not o.hide_render for v in o.data.vertices]
    lo = Vector(tuple(min(p[i] for p in pts) for i in range(3)))
    hi = Vector(tuple(max(p[i] for p in pts) for i in range(3)))
    height = hi.z - lo.z
    # frame the garment's region: tops = upper body, trousers = lower body, shoes = feet
    region = {"Trousers": (0.0, 0.62), "Shoes": (0.0, 0.2)}.get(garment, (0.45, 1.0))
    zlo, zhi = lo.z + height * region[0], lo.z + height * region[1]
    center = Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, (zlo + zhi) / 2))
    span = zhi - zlo
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"; scene.cycles.samples = 24; scene.cycles.use_denoising = True
    scene.render.resolution_x = 720; scene.render.resolution_y = 900
    scene.world = bpy.data.worlds.new("Review world"); scene.world.use_nodes = True
    bg = scene.world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (.18, .18, .18, 1); bg.inputs[1].default_value = .5

    def aim(o, p):
        o.rotation_euler = (p - o.location).to_track_quat("-Z", "Y").to_euler()
    for name, offset, power in [("Key", (2, -3, 3), 350), ("Fill", (-2, -2, 1), 180), ("Rim", (1, 2, 2), 250)]:
        light = bpy.data.lights.new(name, "AREA"); light.energy = power * height ** 2
        light.shape = "DISK"; light.size = height
        obj = bpy.data.objects.new(name, light); scene.collection.objects.link(obj)
        obj.location = center + Vector(offset) * height; aim(obj, center)
    cam_data = bpy.data.cameras.new("cam"); cam_data.type = "ORTHO"
    cam_data.ortho_scale = max(span * 1.25, (hi.x - lo.x) * 1.15 if garment.startswith("Top") else span * 1.25)
    cam = bpy.data.objects.new("cam", cam_data); scene.collection.objects.link(cam); scene.camera = cam
    for state in ("original", "fitted"):
        own.hide_render = state != "original"
        fitted.hide_render = state != "fitted"
        for angle, offset in [("front", (0, -3, 0)), ("profile", (3, 0, 0)), ("back", (0, 3, 0))]:
            cam.location = center + Vector(offset) * height; aim(cam, center)
            scene.render.filepath = str((out / f"{state}-{angle}.png").resolve())
            bpy.ops.render.render(write_still=True)


if __name__ == "__main__":
    main()

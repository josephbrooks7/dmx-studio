import bpy
import sys
from pathlib import Path

import argparse
parser = argparse.ArgumentParser()
parser.add_argument("src")
parser.add_argument("dst")
parser.add_argument("--kind", choices=("body", "hair", "clothing", "accessory", "prop"), default="body")
args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
src, dst = args.src, args.dst
bpy.ops.wm.read_factory_settings(use_empty=True)
suffix = Path(src).suffix.lower()
if suffix in {".glb", ".gltf"}:
    bpy.ops.import_scene.gltf(filepath=src)
elif suffix == ".fbx":
    bpy.ops.import_scene.fbx(filepath=src)
elif suffix == ".blend":
    bpy.ops.wm.open_mainfile(filepath=src, load_ui=False, use_scripts=False)
elif suffix == ".obj":
    bpy.ops.wm.obj_import(filepath=src)
elif suffix in {".usd", ".usda", ".usdc", ".usdz"}:
    bpy.ops.wm.usd_import(filepath=src)
elif suffix == ".stl":
    bpy.ops.wm.stl_import(filepath=src)
elif suffix == ".dae" and hasattr(bpy.ops.wm, "collada_import"):
    bpy.ops.wm.collada_import(filepath=src)
else:
    raise ValueError("Unsupported asset format: " + suffix)
# Resolve external textures relative to the source project before export.
for img in bpy.data.images:
    if img.source == "FILE" and not img.packed_file:
        candidate = Path(bpy.path.abspath(img.filepath))
        if not candidate.is_file():
            candidate = Path(src).resolve().parent / Path(img.filepath.replace(chr(92), "/")).name
        if candidate.is_file():
            img.filepath = str(candidate)
            img.pack()
        else:
            raise FileNotFoundError("Missing asset texture: " + img.filepath)
# Preserve the authored mesh, textures and bind pose; bake no animation yet.
for obj in bpy.data.objects:
    if obj.animation_data:
        obj.animation_data_clear()
for obj in list(bpy.data.objects):
    if obj.type in {"CAMERA", "LIGHT"}:
        bpy.data.objects.remove(obj, do_unlink=True)
# Rocketbox assets contain mutually exclusive outfit and exposed-skin variants.
# Export a single matching set, not all variants stacked on the same skeleton.
mesh_names = {o.name for o in bpy.data.objects if o.type == "MESH"}
if args.kind == "body" and {"Outfit_original", "Skin_original"}.issubset(mesh_names):
    formal = "formal" in Path(dst).stem.lower() and {"Outfit_formal", "Skin_formal"}.issubset(mesh_names)
    keep = {"Outfit_formal", "Skin_formal", "Shoes"} if formal else {"Outfit_original", "Skin_original"}
    variants = {"Outfit_original", "Outfit_formal", "Skin_original", "Skin_formal",
                "Skin_shirt", "Skin_tee", "Top_shirt", "Top_tee", "Trousers", "Shoes"}
    print("Selected character outfit:", sorted(keep))
    for obj in list(bpy.data.objects):
        if obj.type == "MESH" and obj.name in variants - keep:
            print("Removing inactive outfit/skin variant:", obj.name)
            bpy.data.objects.remove(obj, do_unlink=True)
# Remove only exact duplicate mesh instances (same world-space vertices,
# topology and material slots). Never guess which distinct clothing layer
# should be removed: report those for asset-specific inspection instead.
import hashlib
import struct
seen = {}
for obj in sorted(list(bpy.data.objects), key=lambda o: o.name):
    if obj.type != "MESH":
        continue
    mesh = obj.data
    digest = hashlib.sha256()
    for v in mesh.vertices:
        digest.update(struct.pack("<3d", *(obj.matrix_world @ v.co)))
    for p in mesh.polygons:
        digest.update(struct.pack("<II", len(p.vertices), p.material_index))
        for index in p.vertices:
            digest.update(struct.pack("<I", index))
    key = (digest.hexdigest(), tuple(m.name if m else "" for m in mesh.materials),
           tuple((m.type, m.name) for m in obj.modifiers),
           tuple(g.name for g in obj.vertex_groups))
    # Rigged meshes can have different weights even with identical geometry.
    if obj.modifiers or obj.vertex_groups or mesh.shape_keys:
        print("Character mesh (rigged):", obj.name, len(mesh.vertices))
        continue
    if key in seen:
        print("Removing exact duplicate mesh:", obj.name, "matches", seen[key])
        bpy.data.objects.remove(obj, do_unlink=True)
    else:
        seen[key] = obj.name
        print("Character mesh:", obj.name, len(mesh.vertices), "materials:", key[1])
assert any(o.type == "MESH" for o in bpy.data.objects), "No character meshes"
# Stage avatars are currently static. Bake evaluated bind-pose geometry before
# USD export to avoid SceneKit interpreting imported skin weights/bind transforms
# differently from Blender. Keep the original material slots and UV layers.
bpy.context.view_layer.update()
depsgraph = bpy.context.evaluated_depsgraph_get()
baked = []
for obj in list(bpy.context.scene.objects):
    if obj.type != "MESH" or obj.hide_render:
        continue
    evaluated = obj.evaluated_get(depsgraph)
    mesh = bpy.data.meshes.new_from_object(evaluated, preserve_all_data_layers=True, depsgraph=depsgraph)
    if not mesh.vertices or not mesh.polygons:
        bpy.data.meshes.remove(mesh)
        continue
    world = evaluated.matrix_world.copy()
    static = bpy.data.objects.new("Stage_" + obj.name, mesh)
    bpy.context.scene.collection.objects.link(static)
    static.matrix_world = world
    baked.append(static)
    print("Baked stage mesh:", obj.name, len(mesh.vertices), "materials:", [m.name if m else None for m in mesh.materials])
assert baked, "No evaluated stage meshes"
# Detect isolated, oversized spherical helper meshes in the bundled avatars.
# Require a nearly isotropic bounding box AND a nearly constant vertex radius;
# this avoids removing ordinary clothing, heads or elongated body geometry.
from mathutils import Vector
for obj in list(baked) if args.kind == "body" else []:
    points = [obj.matrix_world @ v.co for v in obj.data.vertices]
    lo = Vector(tuple(min(p[i] for p in points) for i in range(3)))
    hi = Vector(tuple(max(p[i] for p in points) for i in range(3)))
    extent = hi - lo
    center = (lo + hi) * 0.5
    radii = [(p - center).length for p in points]
    mean = sum(radii) / len(radii)
    spread = (sum((r - mean)**2 for r in radii) / len(radii))**0.5
    others = [other.matrix_world @ v.co for other in baked if other != obj for v in other.data.vertices]
    reference = max((max(p[i] for p in others) - min(p[i] for p in others) for i in range(3)), default=0) if others else 0
    print("Stage mesh bounds:", obj.name, tuple(extent), "radial spread:", spread / max(mean, 1e-9))
    if reference > 0 and min(extent) > reference * 0.45 and max(extent) < min(extent) * 1.18 and mean > 0 and spread / mean < 0.06:
        print("Removing oversized spherical helper:", obj.name)
        baked.remove(obj)
        bpy.data.objects.remove(obj, do_unlink=True)
assert baked, "No stage meshes after helper filtering"
for obj in list(bpy.context.scene.objects):
    if obj not in baked:
        bpy.data.objects.remove(obj, do_unlink=True)
# Export native USDZ, including material textures.
# Blender versions use different names for USD texture export options.
properties = bpy.ops.wm.usd_export.get_rna_type().properties.keys()
options = dict(filepath=dst, export_animation=False, export_materials=True)
for name, value in (("export_textures", True), ("export_armatures", False),
                    ("export_textures_mode", "NEW")):
    if name in properties:
        prop = bpy.ops.wm.usd_export.get_rna_type().properties[name]
        if prop.type != "ENUM" or value in prop.enum_items.keys():
            options[name] = value
result = bpy.ops.wm.usd_export(**options)
assert "FINISHED" in result
import zipfile
with zipfile.ZipFile(dst) as archive:
    if args.kind in {"body", "hair"}:
        assert any(name.lower().endswith((".png", ".jpg", ".jpeg", ".webp")) for name in archive.namelist()), "USDZ is missing character textures"
    assert any(name.lower().endswith((".usd", ".usda", ".usdc")) for name in archive.namelist()), "USDZ is missing scene data"
assert Path(dst).stat().st_size > 0

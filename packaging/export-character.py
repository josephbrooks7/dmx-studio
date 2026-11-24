import bpy
import sys
from pathlib import Path

src, dst = sys.argv[sys.argv.index("--") + 1:]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
# Preserve the authored mesh, textures and bind pose; bake no animation yet.
for obj in bpy.data.objects:
    if obj.animation_data:
        obj.animation_data_clear()
for obj in list(bpy.data.objects):
    if obj.type in {"CAMERA", "LIGHT"}:
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
# Export native USDZ, including material textures.
# Blender versions use different names for USD texture export options.
properties = bpy.ops.wm.usd_export.get_rna_type().properties.keys()
options = dict(filepath=dst, export_animation=False, export_materials=True)
for name, value in (("export_textures", True), ("export_armatures", True),
                    ("export_textures_mode", "NEW")):
    if name in properties:
        prop = bpy.ops.wm.usd_export.get_rna_type().properties[name]
        if prop.type != "ENUM" or value in prop.enum_items.keys():
            options[name] = value
result = bpy.ops.wm.usd_export(**options)
assert "FINISHED" in result
import zipfile
with zipfile.ZipFile(dst) as archive:
    assert any(name.lower().endswith((".png", ".jpg", ".jpeg", ".webp")) for name in archive.namelist()), "USDZ is missing character textures"
assert Path(dst).stat().st_size > 10000

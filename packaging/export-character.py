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

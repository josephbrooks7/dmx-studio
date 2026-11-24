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
bpy.ops.wm.usd_export(filepath=dst, export_animation=False, export_materials=True,
                      export_textures=True, export_armatures=True)
assert Path(dst).stat().st_size > 10000

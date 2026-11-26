#!/usr/bin/env python3
"""Inspect head geometry offline with Blender 3.6+; do not modify source assets.

Extracts only the two known model entries from the local archives into a temp
directory. Reports dimensions, vertex counts, origin, materials and UV maps.
Does not save converted models, touch the DMX Studio app, or upload assets.
"""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import zipfile

MALE_OUTER = "male-head-textured.zip"
MALE_INNER = "source/textured male head.zip"
MALE_OBJ = "textured male head.obj"
FEMALE_OUTER = "realistic-female-head-study.zip"
FEMALE_MODEL = "source/Realistic female head study.fbx"
MAX_SIZE = 64 * 1024 * 1024

BLENDER_SCRIPT = r'''
import bpy, json, sys
from pathlib import Path
args = sys.argv[sys.argv.index("--") + 1:]
filepath, kind = args[0], args[1]
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
if kind == "obj":
    if hasattr(bpy.ops.wm, "obj_import"):
        bpy.ops.wm.obj_import(filepath=filepath)
    else:
        bpy.ops.import_scene.obj(filepath=filepath)
else:
    bpy.ops.import_scene.fbx(filepath=filepath)
meshes = [o for o in bpy.data.objects if o.type == "MESH"]
if not meshes:
    raise RuntimeError("No mesh found")
from mathutils import Vector
for obj in meshes:
    verts = [obj.matrix_world @ v.co for v in obj.data.vertices]
    bounds = [[round(min(p[i] for p in verts), 4), round(max(p[i] for p in verts), 4)] for i in range(3)] if verts else []
    print("DMX_HEAD_REPORT=" + json.dumps({
      "object": obj.name, "vertices": len(obj.data.vertices), "faces": len(obj.data.polygons),
      "bounds_xyz": bounds, "dimensions_xyz": [round(float(v), 4) for v in obj.dimensions],
      "uv_maps": [uv.name for uv in obj.data.uv_layers],
      "materials": [{"name":m.name, "image_nodes":[n.image.filepath for n in m.node_tree.nodes if n.type == "TEX_IMAGE" and n.image] if m and m.use_nodes and m.node_tree else []} for m in obj.data.materials if m],
      "shape_keys": list(obj.data.shape_keys.key_blocks.keys()) if obj.data.shape_keys else [],
    }, sort_keys=True))
print("DMX_HEAD_COUNTS=" + json.dumps({"meshes":len(meshes),"armatures":sum(o.type=="ARMATURE" for o in bpy.data.objects)}))
'''

def safe_read(archive, name):
    member = archive.getinfo(name)
    if member.file_size > MAX_SIZE or member.is_dir():
        raise ValueError("Unexpected size or directory: " + name)
    with archive.open(member) as source:
        data = source.read(MAX_SIZE + 1)
    if len(data) > MAX_SIZE:
        raise ValueError("Archive entry too large")
    return data

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--downloads", type=Path, default=Path.home() / "Downloads")
    parser.add_argument("--blender", default="/Applications/Blender.app/Contents/MacOS/Blender")
    args = parser.parse_args()
    if not Path(args.blender).is_file():
        raise SystemExit("Blender not found: " + args.blender)
    with tempfile.TemporaryDirectory(prefix="dmx-head-inspect-") as tmp:
        root = Path(tmp)
        with zipfile.ZipFile(args.downloads / MALE_OUTER) as outer:
            import io
            with zipfile.ZipFile(io.BytesIO(safe_read(outer, MALE_INNER))) as nested:
                for name in (MALE_OBJ, "textured male head.mtl"):
                    (root / name).write_bytes(safe_read(nested, name))
                for name in nested.namelist():
                    if name.lower().endswith((".png", ".jpg", ".jpeg")) and "/" not in name:
                        (root / name).write_bytes(safe_read(nested, name))
        with zipfile.ZipFile(args.downloads / FEMALE_OUTER) as outer:
            (root / "female-head.fbx").write_bytes(safe_read(outer, FEMALE_MODEL))
        script = root / "report.py"
        script.write_text(BLENDER_SCRIPT)
        for name, path, kind in (("MALE HEAD",root/MALE_OBJ,"obj"),("FEMALE HEAD",root/"female-head.fbx","fbx")):
            print("\n=== " + name + " ===", flush=True)
            cmd = [args.blender,"--background","--factory-startup","--disable-autoexec","--python-exit-code","1","--python",str(script),"--",str(path),kind]
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=240)
            for line in (result.stdout+"\n"+result.stderr).splitlines():
                if line.startswith(("DMX_HEAD_REPORT=", "DMX_HEAD_COUNTS=", "Error:", "Traceback", "FBX version:")):
                    print(line, flush=True)
            if result.returncode:
                raise RuntimeError(name + " inspection failed (exit " + str(result.returncode) + ")")
    print("\nInspection complete. No assets published, modified, or saved.",flush=True)

if __name__ == "__main__":
    main()

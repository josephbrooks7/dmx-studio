"""Inspect a Blender body reference without modifying the source.
Run: blender -b --disable-autoexec --python-exit-code 1 --python inspect-body-reference.py -- source.blend report.json
"""
import json
import sys
from pathlib import Path

def main():
    import bpy
    from mathutils import Vector
    args = sys.argv[sys.argv.index("--")+1:]
    if len(args) != 2:
        raise ValueError("Expected source.blend and report.json")
    source, output = map(Path, args)
    if source.suffix.lower() != ".blend":
        raise ValueError("Expected a native Blender file")
    if source.resolve() == output.resolve():
        raise ValueError("Output must not overwrite source")
    bpy.ops.wm.open_mainfile(filepath=str(source.resolve()), use_scripts=False)
    scene = bpy.context.scene
    scale = scene.unit_settings.scale_length
    meshes, rigs = [], []
    for obj in sorted(scene.objects, key=lambda o: o.name):
        if obj.type == "MESH":
            mesh = obj.data
            corners = [obj.matrix_world @ Vector(v) for v in obj.bound_box]
            bounds = [[min(v[i] for v in corners)*scale for i in range(3)],
                      [max(v[i] for v in corners)*scale for i in range(3)]]
            meshes.append({
                "name": obj.name, "vertices": len(mesh.vertices),
                "polygons": len(mesh.polygons), "bounds_m": bounds,
                "dimensions_m": [bounds[1][i]-bounds[0][i] for i in range(3)],
                "uv_layers": [u.name for u in mesh.uv_layers],
                "materials": [m.name if m else None for m in mesh.materials],
                "shape_keys": [k.name for k in mesh.shape_keys.key_blocks] if mesh.shape_keys else [],
                "vertex_groups": [g.name for g in obj.vertex_groups],
                "armature_modifiers": [m.object.name for m in obj.modifiers if m.type == "ARMATURE" and m.object],
            })
        elif obj.type == "ARMATURE":
            rigs.append({"name": obj.name, "bones": [
                {"name": b.name, "parent": b.parent.name if b.parent else None,
                 "head_m": [v*scale for v in obj.matrix_world @ b.head_local],
                 "tail_m": [v*scale for v in obj.matrix_world @ b.tail_local]}
                for b in obj.data.bones]})
    report = {"schema_version": 1, "source": source.name, "unit_system": scene.unit_settings.system,
              "unit_scale": scale, "coordinate_space": "Blender world; meters assuming scene unit scale",
              "meshes": meshes, "armatures": rigs,
              "warnings": ["Bounds are object bounds, not verified anatomical measurements.",
                           "Body mesh selection, landmarks and garment fitting require separate validation.",
                           "Unit scale must be checked against a known body height."]}
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2, allow_nan=False)+"\n", encoding="utf-8")

if __name__ == "__main__":
    main()

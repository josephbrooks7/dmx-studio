"""Run in Blender background; read-only geometry inventory."""
import bpy
from pathlib import Path
from collections import Counter
import json

root = Path.home() / "DMX-Character-Sources"
for label, path in [("male", root/"MaleHair/source/21Fles.fbx"), ("female", root/"FemaleHair/source/upload to sketchfab.fbx")]:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=str(path))
    bpy.context.view_layer.update()
    print("COLLECTION", label)
    for obj in bpy.context.scene.objects:
        if obj.type != "MESH":
            continue
        mesh = obj.data
        parent = list(range(len(mesh.vertices)))
        def find(i):
            while parent[i] != i:
                parent[i] = parent[parent[i]]
                i = parent[i]
            return i
        for edge in mesh.edges:
            a,b = map(find, edge.vertices)
            if a != b:
                parent[b] = a
        groups = {}
        for v in mesh.vertices:
            groups.setdefault(find(v.index), []).append(obj.matrix_world @ v.co)
        def bounds(points):
            return [[round(min(p[i] for p in points),5),round(max(p[i] for p in points),5)] for i in range(3)]
        all_points = [p for g in groups.values() for p in g]
        if not all_points:
            continue
        print(json.dumps({"mesh":obj.name,"bounds":bounds(all_points),"islands":len(groups),"largest":[{"vertices":len(g),"bounds":bounds(g)} for g in sorted(groups.values(),key=len,reverse=True)[:24]],"uv_layers":len(mesh.uv_layers)}))

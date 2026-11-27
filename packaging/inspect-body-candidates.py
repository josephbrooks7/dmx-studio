"""Inventory existing USDZ body candidates in Blender before garment fitting."""
import bpy
import sys
import json
from pathlib import Path

def inspect(path):
    if not path.is_file() or path.stat().st_size < 1024:
        raise ValueError("Missing asset or unresolved Git LFS pointer: "+str(path))
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.wm.usd_import(filepath=str(path.resolve()))
    bpy.context.view_layer.update()
    meshes=[]
    for obj in sorted(bpy.context.scene.objects,key=lambda o:o.name):
        if obj.type!="MESH" or not obj.data.vertices:
            continue
        points=[obj.matrix_world @ v.co for v in obj.data.vertices]
        meshes.append({"name":obj.name,"vertices":len(points),
            "polygons":len(obj.data.polygons),
            "bounds_blender_world":[[min(p[i] for p in points) for i in range(3)],
                                    [max(p[i] for p in points) for i in range(3)]],
            "materials":[m.name if m else None for m in obj.data.materials],
            "uv_layers":[u.name for u in obj.data.uv_layers],
            "vertex_groups":[g.name for g in obj.vertex_groups],
            "armature_modifiers":[m.object.name for m in obj.modifiers if m.type=="ARMATURE" and m.object]})
    if not meshes:
        raise ValueError("No imported meshes: "+str(path))
    return {"asset":path.name,"meshes":meshes,
            "armatures":[{"name":o.name,"bones":[b.name for b in o.data.bones]}
                         for o in bpy.context.scene.objects if o.type=="ARMATURE"],
            "note":"Inventory only: anatomical landmarks, body orientation, rig and garment compatibility are not yet validated."}

def main():
    args=sys.argv[sys.argv.index("--")+1:]
    if len(args)!=3: raise ValueError("Expected male.usdz female.usdz output.json")
    paths=list(map(Path,args))
    report={"schema_version":1,"bodies":[inspect(p) for p in paths[:2]]}
    paths[2].parent.mkdir(parents=True,exist_ok=True)
    paths[2].write_text(json.dumps(report,indent=2,allow_nan=False)+"\n")
    print("BODY_CANDIDATE_INVENTORY_PASSED")
if __name__=="__main__": main()

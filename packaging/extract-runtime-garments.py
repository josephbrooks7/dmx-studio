"""Extract verified independent runtime garments into rigged GLB modules.
Each module retains original UVs, materials and armature; not yet cross-fitted.
"""
import bpy
import sys
import json
from pathlib import Path

NAMES=("Top_tee","Top_shirt","Trousers","Shoes")

def extract(src,dst):
    manifest=[]
    for name in NAMES:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.import_scene.gltf(filepath=str(src.resolve()))
        obj=bpy.data.objects.get(name)
        if not obj or obj.type!="MESH": raise ValueError("Missing garment "+name)
        rigs=[m.object for m in obj.modifiers if m.type=="ARMATURE" and m.object]
        if len(rigs)!=1: raise ValueError("Expected one garment rig")
        rig=rigs[0]
        bones={b.name for b in rig.data.bones}
        if not obj.data.uv_layers or not obj.data.materials: raise ValueError("Missing UV or materials")
        for v in obj.data.vertices:
            weights=[g.weight for g in v.groups if obj.vertex_groups[g.group].name in bones and g.weight>0]
            if not weights or abs(sum(weights)-1)>0.02: raise ValueError("Invalid skin weights "+name)
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True);rig.select_set(True)
        bpy.context.view_layer.objects.active=obj
        output=dst/(src.stem+"-"+name+".glb")
        bpy.ops.export_scene.gltf(filepath=str(output.resolve()),export_format="GLB",
            use_selection=True,export_animations=False,export_skins=True)
        if not output.is_file() or output.stat().st_size<100: raise ValueError("Empty garment export")
        manifest.append({"source":src.name,"mesh":name,"file":output.name,
            "vertices":len(obj.data.vertices),"bones":len(bones),
            "materials":[m.name if m else None for m in obj.data.materials]})
    return manifest

def main():
    a,b,dst=map(Path,sys.argv[sys.argv.index("--")+1:])
    dst.mkdir(parents=True,exist_ok=True)
    report={"schema_version":1,"garments":extract(a,dst)+extract(b,dst),
            "status":"source-body garment modules; cross-body fit not verified"}
    (dst/"manifest.json").write_text(json.dumps(report,indent=2)+"\n")
if __name__=="__main__": main()

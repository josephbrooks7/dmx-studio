#!/usr/bin/env python3
"""Preview-only detailed head fitting diagnostic (no model export / publication).

Imports the previously extracted character base GLBs and the two local head
packages, fits heads to estimated shoulders, and outputs a *diagnostic JSON*
including actual transformed bounds. Does NOT write files to the repository.
This is a geometry experiment, not a rigging or character-assembly solution.
"""
import io
import json
from pathlib import Path
import subprocess
import tempfile
import zipfile

BLENDER = "/Applications/Blender.app/Contents/MacOS/Blender"
SOURCE = Path.home() / "DMX-Character-Sources"
DOWNLOADS = Path.home() / "Downloads"
LIMIT = 64 * 1024 * 1024
BODY = {"male": SOURCE / "male_standard.glb", "female": SOURCE / "female_standard.glb"}

BLENDER_SCRIPT = r'''
import bpy, json, math, sys
from mathutils import Vector
from pathlib import Path
body_file,head_file,head_type,sex=sys.argv[sys.argv.index("--")+1:]
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=body_file)
body=[o for o in bpy.context.scene.objects if o.type=="MESH"]
if len(body)!=1: raise ValueError("Expected one selected body mesh; got "+str(len(body)))
body=body[0]
def bounds(obj):
 p=[obj.matrix_world @ v.co for v in obj.data.vertices]
 return (Vector(tuple(min(v[i] for v in p) for i in range(3))),
         Vector(tuple(max(v[i] for v in p) for i in range(3))))
bmin,bmax=bounds(body)
body_height=bmax.z-bmin.z
if body_height<=0: raise ValueError("Invalid body height")
before=set(bpy.data.objects.keys())
if head_type=="obj":
 if hasattr(bpy.ops.wm,"obj_import"): bpy.ops.wm.obj_import(filepath=head_file)
 else: bpy.ops.import_scene.obj(filepath=head_file)
else: bpy.ops.import_scene.fbx(filepath=head_file)
heads=[o for o in bpy.context.scene.objects if o.type=="MESH" and o.name not in before]
if len(heads)!=1: raise ValueError("Expected one head mesh; got "+str(len(heads)))
head=heads[0]
hmin,hmax=bounds(head)
# Imported OBJ may use Y-up. Align its longest dimension with the body Z
# only for this diagnostic; correct anatomical orientation requires review.
dimensions=hmax-hmin
up_idx=max(range(3),key=lambda i:dimensions[i])
if up_idx==1:
 head.rotation_euler[0]=math.pi/2
elif up_idx==0:
 head.rotation_euler[1]=-math.pi/2
bpy.context.view_layer.update()
hmin,hmax=bounds(head)
hheight=hmax.z-hmin.z
target_height=body_height*0.135
scale=target_height/hheight
head.scale=[v*scale for v in head.scale]
bpy.context.view_layer.update()
hmin,hmax=bounds(head)
# A typical neck line is ~0.875 body height; this is a visual placeholder,
# not a genuine neck attachment/rigged skin fit.
target=Vector(((bmin.x+bmax.x)/2,(bmin.y+bmax.y)/2,bmin.z+body_height*0.87))
hcenter=Vector(((hmin.x+hmax.x)/2,(hmin.y+hmax.y)/2,hmin.z))
head.location += target-hcenter
bpy.context.view_layer.update()
hmin,hmax=bounds(head)
print("DMX_FIT_REPORT="+json.dumps({
 "sex":sex,"body_height":round(body_height,4),
 "body_dimensions":[round(v,4) for v in bmax-bmin],
 "head_dimensions":[round(v,4) for v in hmax-hmin],
 "head_bounds":[[round(hmin[i],4),round(hmax[i],4)] for i in range(3)],
 "body_bounds":[[round(bmin[i],4),round(bmax[i],4)] for i in range(3)],
 "head_scale_factor":round(scale,4),
 "assumptions":["rough 13.5% head/body height","head at 87% height","rough axis based on largest dimension",
 "neck seam not fixed","materials not verified","not distributable"]
},sort_keys=True))
'''
def read_entry(z, name):
    info=z.getinfo(name)
    if info.file_size>LIMIT: raise ValueError("Archive member too large")
    with z.open(info) as f: data=f.read(LIMIT+1)
    if len(data)>LIMIT: raise ValueError("Archive too large")
    return data

def main():
    with tempfile.TemporaryDirectory(prefix="dmx-fitting-") as dirname:
        tmp=Path(dirname)
        with zipfile.ZipFile(DOWNLOADS/"male-head-textured.zip") as outer:
            with zipfile.ZipFile(io.BytesIO(read_entry(outer,"source/textured male head.zip"))) as inner:
                for name in ("textured male head.obj","textured male head.mtl",
                             "FACE COLOR 7.png","FACE NORMAL.png","FACE ROUGHNESS.png","FACE SPECULAR.png","FACE SUBSURFACE.png"):
                    (tmp/name).write_bytes(read_entry(inner,name))
        with zipfile.ZipFile(DOWNLOADS/"realistic-female-head-study.zip") as f:
            (tmp/"female-head.fbx").write_bytes(read_entry(f,"source/Realistic female head study.fbx"))
        script=tmp/"diagnostic.py"
        script.write_text(BLENDER_SCRIPT)
        for sex,model,kind in (("male","textured male head.obj","obj"),("female","female-head.fbx","fbx")):
            command=[BLENDER,"--background","--factory-startup","--disable-autoexec","--python-exit-code","1","--python",str(script),"--",str(BODY[sex]),str(tmp/model),kind,sex]
            if not BODY[sex].is_file(): raise FileNotFoundError(BODY[sex])
            run=subprocess.run(command,capture_output=True,text=True,timeout=240)
            print("=== "+sex.upper()+" HEAD FIT DIAGNOSTIC ===",flush=True)
            for line in (run.stdout+"\n"+run.stderr).splitlines():
                if line.startswith(("DMX_FIT_REPORT=","Traceback","Error:")): print(line,flush=True)
            if run.returncode: raise RuntimeError("Blender diagnostic failed: "+sex)
    print("Diagnostic complete. No models exported or published.")

if __name__=="__main__":
    main()

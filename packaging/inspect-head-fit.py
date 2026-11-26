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

# Optional diagnostic render (never exports or saves models).
# Remove overlapping old body-head polygons only in the temporary Blender scene.
if len(sys.argv[sys.argv.index("--")+1:]) > 4:
 import bmesh
 render_dir=Path(sys.argv[sys.argv.index("--")+5])
 render_dir.mkdir(parents=True,exist_ok=True)
 bm=bmesh.new()
 bm.from_mesh(body.data)
 bm.faces.ensure_lookup_table()
 cutoff=bmin.z+body_height*0.865
 cx=(bmin.x+bmax.x)/2
 cy=(bmin.y+bmax.y)/2
 obsolete=[]
 for face in bm.faces:
  p=body.matrix_world @ face.calc_center_median()
  if p.z>cutoff and abs(p.x-cx)<body_height*0.20 and abs(p.y-cy)<body_height*0.18:
   obsolete.append(face)
 if obsolete:
  bmesh.ops.delete(bm,geom=obsolete,context="FACES")
  bm.to_mesh(body.data)
 bm.free()
 body.data.update()
 for obj in (body,head):
  for polygon in obj.data.polygons:
   polygon.use_smooth=True
 # No automatic material replacements: preserve any imported texture maps.
 bpy.context.scene.render.engine="BLENDER_EEVEE"
 bpy.context.scene.eevee.taa_render_samples=32
 bpy.context.scene.render.resolution_x=680
 bpy.context.scene.render.resolution_y=900
 bpy.context.scene.render.resolution_percentage=100
 bpy.context.scene.render.image_settings.file_format="PNG"
 bpy.context.scene.view_settings.view_transform="Standard"
 bpy.context.scene.view_settings.look="Medium High Contrast"
 bpy.context.scene.view_settings.exposure=-0.6
 world=bpy.data.worlds.new("Diagnostic Neutral Studio")
 bpy.context.scene.world=world
 world.use_nodes=True
 bg=world.node_tree.nodes.get("Background")
 bg.inputs["Color"].default_value=(0.25,0.25,0.25,1)
 bg.inputs["Strength"].default_value=0.7
 # Lighting does not modify skin textures or material files.
 def area(name,position,energy,size):
  bpy.ops.object.light_add(type="AREA",location=position)
  light=bpy.context.object
  light.name=name
  light.data.energy=energy
  light.data.shape="DISK"
  light.data.size=size
  return light
 area("Key softbox",(cx-body_height*0.7,cy-body_height*0.8,bmin.z+body_height*1.2),450,body_height*0.85)
 area("Fill softbox",(cx+body_height*0.7,cy-body_height*0.45,bmin.z+body_height*0.95),220,body_height*1.1)
 area("Rim softbox",(cx,cy+body_height*0.8,bmin.z+body_height*1.2),350,body_height*0.7)
 bpy.ops.object.camera_add()
 camera=bpy.context.object
 camera.name="DMX Diagnostic Camera"
 camera.data.type="ORTHO"
 bpy.context.scene.camera=camera
 def shot(label,target,dist,ortho):
  camera.location=target+Vector((0,-dist,dist*0.09))
  direction=target-camera.location
  camera.rotation_euler=direction.to_track_quat("-Z","Y").to_euler()
  camera.data.ortho_scale=ortho
  bpy.context.scene.render.filepath=str(render_dir/(sex+"-"+label+".png"))
  bpy.ops.render.render(write_still=True)
  print("DMX_RENDER="+bpy.context.scene.render.filepath)
 shot("full",Vector((cx,cy,bmin.z+body_height*0.52)),body_height*2.2,body_height*1.22)
 shot("face",Vector(((hmin.x+hmax.x)/2,(hmin.y+hmax.y)/2,(hmin.z+hmax.z)/2)),body_height*0.65,body_height*0.48)
 print("DMX_RENDER_NOTE=Approximate axis and neck fitting; evaluate face orientation, duplicate geometry, clipping, and lighting before any release.")
'''
def read_entry(z, name):
    info=z.getinfo(name)
    if info.file_size>LIMIT: raise ValueError("Archive member too large")
    with z.open(info) as f: data=f.read(LIMIT+1)
    if len(data)>LIMIT: raise ValueError("Archive too large")
    return data

def main():
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--render", action="store_true", help="Also create visual diagnostic PNGs; no model exports")
    parser.add_argument("--output", type=Path, default=Path.home() / "DMX-Character-Preview-Renders")
    opts = parser.parse_args()
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
            if opts.render:
                command.append(str(opts.output.expanduser().resolve()))
            if not BODY[sex].is_file(): raise FileNotFoundError(BODY[sex])
            run=subprocess.run(command,capture_output=True,text=True,timeout=900)
            print("=== "+sex.upper()+" HEAD FIT DIAGNOSTIC ===",flush=True)
            for line in (run.stdout+"\n"+run.stderr).splitlines():
                if line.startswith(("DMX_FIT_REPORT=","DMX_RENDER=","DMX_RENDER_NOTE=","Traceback","Error:")): print(line,flush=True)
            if run.returncode: raise RuntimeError("Blender diagnostic failed: "+sex)
    print("Diagnostic complete. No models exported or published.")
    if opts.render: print("Visual diagnostic files:", opts.output.expanduser().resolve())

if __name__=="__main__":
    main()

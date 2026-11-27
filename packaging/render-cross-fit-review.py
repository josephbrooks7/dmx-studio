"""Render actual target avatar with original and experimental replacement tee.
Static rest-pose visual review only; does not certify body clearance.
"""
import sys
from pathlib import Path
import bpy
from mathutils import Vector

def load(path):
    before=set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(path.resolve()))
    return set(bpy.data.objects)-before

def named(objects,name):
    matches=[o for o in objects if o.type=="MESH" and o.name.split(".")[0]==name]
    if len(matches)!=1: raise ValueError("Expected one "+name)
    return matches[0]

def main():
    original,garment,out=map(Path,sys.argv[sys.argv.index("--")+1:])
    out.mkdir(parents=True,exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    objects=load(original)
    visible={"Body","Hair","Skin_tee","Top_tee","Trousers","Shoes"}
    for o in objects:
        if o.type=="MESH": o.hide_render=o.name.split(".")[0] not in visible
    tee=named(objects,"Top_tee")
    skin=named(objects,"Skin_tee")
    replacement=named(load(garment),"CrossFit_Tee")
    replacement.hide_render=True
    bpy.context.view_layer.update()
    pts=[o.matrix_world @ v.co for o in objects if o.type=="MESH" and not o.hide_render for v in o.data.vertices]
    lo=Vector(tuple(min(p[i] for p in pts) for i in range(3)))
    hi=Vector(tuple(max(p[i] for p in pts) for i in range(3)))
    center=(lo+hi)/2
    height=hi.z-lo.z
    if height<=0: raise ValueError("Invalid avatar height")
    scene=bpy.context.scene
    scene.render.engine="CYCLES"
    scene.cycles.samples=24
    scene.cycles.use_denoising=True
    scene.render.resolution_x=720
    scene.render.resolution_y=960
    scene.render.resolution_percentage=100
    scene.world=bpy.data.worlds.new("Review world")
    scene.world.use_nodes=True
    scene.world.node_tree.nodes["Background"].inputs[0].default_value=(.18,.18,.18,1)
    scene.world.node_tree.nodes["Background"].inputs[1].default_value=.5
    def aim(o,p): o.rotation_euler=(p-o.location).to_track_quat("-Z","Y").to_euler()
    for name,offset,power in [("Key",(2,-3,3),350),("Fill",(-2,-2,1),180),("Rim",(1,2,2),250)]:
        light=bpy.data.lights.new(name,"AREA")
        light.energy=power*height**2
        light.shape="DISK";light.size=height
        obj=bpy.data.objects.new(name,light);scene.collection.objects.link(obj)
        obj.location=center+Vector(offset)*height;aim(obj,center)
    camera=bpy.data.cameras.new("Review camera");camera.type="ORTHO";camera.ortho_scale=max(height*1.18,(hi.x-lo.x)*1.4)
    cam=bpy.data.objects.new("Review camera",camera);scene.collection.objects.link(cam);scene.camera=cam
    for state in ("original","cross-fit"):
        tee.hide_render=state!="original"
        replacement.hide_render=state!="cross-fit"
        assert not skin.hide_render
        for angle,offset in [("front",(0,-3,.05)),("profile",(3,0,.05)),("three-quarter",(2,-3,.05))]:
            cam.location=center+Vector(offset)*height;aim(cam,center)
            scene.render.filepath=str((out/(state+"-"+angle+".png")).resolve())
            bpy.ops.render.render(write_still=True)
if __name__=="__main__": main()

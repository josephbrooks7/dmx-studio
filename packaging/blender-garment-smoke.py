"""Synthetic Blender integration smoke test; no third-party assets required."""
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
import bpy
from mathutils import Matrix
from body_fit import Section
from garment_regions import Frame,Region
from garment_clearance import SurfaceSample
from blender_garment_fit import fit_blender_garment

def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    mesh=bpy.data.meshes.new("Source garment mesh")
    points=[(.1,.4,0),(.1,.6,0),(.1,.5,.02)]
    mesh.from_pydata(points,[],[(0,1,2)])
    mesh.update()
    mesh.uv_layers.new(name="Original UV")
    mesh.materials.append(bpy.data.materials.new("Original fabric"))
    garment=bpy.data.objects.new("Source garment",mesh)
    bpy.context.collection.objects.link(garment)
    arm=bpy.data.armatures.new("Target skeleton")
    rig=bpy.data.objects.new("Target rig",arm)
    bpy.context.collection.objects.link(rig)
    bpy.context.view_layer.objects.active=rig
    rig.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bone=arm.edit_bones.new("spine")
    bone.head=(0,0,0)
    bone.tail=(0,1,0)
    bpy.ops.object.mode_set(mode="OBJECT")
    arm.pose_position="REST"
    f=Frame.from_landmarks((0,0,0),(0,1,0),(0,0,1))
    a=(Section(0,0,0,.1,.1),Section(1,0,0,.1,.1))
    b=(Section(0,0,0,.2,.1),Section(1,0,0,.2,.1))
    samples=[SurfaceSample((.2,y,z),(1,0,0),"torso") for _,y,z in points]
    fitted,result=fit_blender_garment(garment,rig,Matrix.Identity(4),
        assignments=[{"torso":1}]*3,regions={"torso":Region(f,f,a,b)},
        surface_regions=["torso"]*3,surface_samples=samples,
        body_vertices=[s.point for s in samples],body_weights=[{"spine":1}]*3,
        bone_map={})
    assert fitted is not garment and fitted.data is not mesh
    assert result.ready_for_review
    assert len(fitted.data.polygons)==1 and len(fitted.data.vertices)==3
    assert fitted.data.uv_layers.get("Original UV") is not None
    assert fitted.data.materials[0]==mesh.materials[0]
    assert fitted.modifiers[0].object==rig
    for original,new in zip(mesh.vertices,fitted.data.vertices):
        assert abs(original.co.x-.1)<1e-6
        assert abs(new.co.x-.205)<1e-6
        assert abs(fitted.vertex_groups["spine"].weight(new.index)-1)<1e-6
    print("BLENDER_GARMENT_SMOKE_TEST_PASSED")

if __name__=="__main__":
    main()

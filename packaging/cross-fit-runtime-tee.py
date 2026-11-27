"""Cross-body shirt trial using an authored target shirt as a fitting cage.

This is a geometry correspondence experiment, not arbitrary-body fitting.
Target garment provides a reference surface and target rig; original source
shirt topology, UVs and material slots are retained.
"""
import sys,json
from pathlib import Path
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from mathutils.kdtree import KDTree

def load(path):
    before=set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(path.resolve()))
    objects=set(bpy.data.objects)-before
    shirts=[o for o in objects if o.type=="MESH" and o.name.split(".")[0]=="Top_tee"]
    if len(shirts)!=1: raise ValueError("Expected one Top_tee in "+str(path))
    return shirts[0]

def bounds(points):
    lo=Vector(tuple(min(p[i] for p in points) for i in range(3)))
    hi=Vector(tuple(max(p[i] for p in points) for i in range(3)))
    if min(hi-lo)<1e-6: raise ValueError("Degenerate shirt bounds")
    return lo,hi

def main():
    src,dst,out=map(Path,sys.argv[sys.argv.index("--")+1:])
    bpy.ops.wm.read_factory_settings(use_empty=True)
    source=load(src);target=load(dst)
    bpy.context.view_layer.update()
    sp=[source.matrix_world @ v.co for v in source.data.vertices]
    tp=[target.matrix_world @ v.co for v in target.data.vertices]
    a,b=bounds(sp);c,d=bounds(tp)
    target.data.calc_loop_triangles()
    tree=BVHTree.FromPolygons(tp,[tuple(t.vertices) for t in target.data.loop_triangles],all_triangles=True)
    kd=KDTree(len(tp))
    for i,p in enumerate(tp): kd.insert(p,i)
    kd.balance()
    rigmods=[m for m in target.modifiers if m.type=="ARMATURE" and m.object]
    if len(rigmods)!=1: raise ValueError("Target shirt must have one rig")
    rig=rigmods[0].object
    bones={b.name for b in rig.data.bones if b.use_deform}
    mapped=[];weight_rows=[];distances=[];affine=[];projected=[]
    for p in sp:
        q=Vector(tuple(c[i]+(p[i]-a[i])/(b[i]-a[i])*(d[i]-c[i]) for i in range(3)))
        near,n,face,dist=tree.find_nearest(q)
        if near is None or dist>.15: raise ValueError("Unreliable surface match")
        distances.append(dist)
        affine.append(q.copy());projected.append(near.copy())
        accum={}
        for _,idx,r in kd.find_n(near,4):
            for g in target.data.vertices[idx].groups:
                name=target.vertex_groups[g.group].name
                if name in bones and g.weight>0: accum[name]=accum.get(name,0)+g.weight/max(r,1e-5)**2
        keep=sorted(accum.items(),key=lambda x:-x[1])[:4]
        total=sum(w for _,w in keep)
        if total<=0: raise ValueError("No target skin weights")
        weight_rows.append({k:w/total for k,w in keep})
    # A hard nearest-surface projection can map neighboring vertices to
    # the same edge. Retain a bounded fraction of the original affine
    # geometry and reject candidates that collapse previously valid faces.
    faces=[tuple(p.vertices) for p in source.data.polygons]
    def area(points,face):
        a=points[face[0]]
        return sum((points[face[i]]-a).cross(points[face[i+1]]-a).length*.5
                   for i in range(1,len(face)-1))
    baseline=[area(affine,f) for f in faces]
    existing=sum(a<1e-10 for a in baseline)
    valid=[i for i,a in enumerate(baseline) if a>=1e-10]
    if not valid: raise ValueError("Source has no valid faces")
    for strength in (.95,.85,.70,.50,.25):
        candidate=[q.lerp(p,strength) for q,p in zip(affine,projected)]
        ratios=[area(candidate,faces[i])/baseline[i] for i in valid]
        if min(ratios)>=.02:
            mapped=candidate
            break
    if not mapped: raise ValueError("No topology-preserving projection candidate")
    mesh=source.data.copy()
    fitted=bpy.data.objects.new("CrossFit_Tee",mesh)
    bpy.context.scene.collection.objects.link(fitted)
    for v,p in zip(mesh.vertices,mapped): v.co=p
    mesh.update()
    groups={}
    for i,row in enumerate(weight_rows):
        for name,w in row.items():
            if name not in groups: groups[name]=fitted.vertex_groups.new(name=name)
            groups[name].add([i],w,"REPLACE")
    mod=fitted.modifiers.new("Target rig","ARMATURE");mod.object=rig
    assert len(mesh.vertices)==len(source.data.vertices)
    assert len(mesh.polygons)==len(source.data.polygons)
    assert len(mesh.uv_layers)==len(source.data.uv_layers)
    assert list(mesh.materials)==list(source.data.materials)
    degenerate=sum(1 for p in mesh.polygons if p.area<1e-10)
    newly_degenerate=sum(mesh.polygons[i].area<1e-10 for i in valid)
    out.mkdir(parents=True,exist_ok=True)
    report={"source":src.name,"target":dst.name,"vertices":len(mapped),"faces":len(mesh.polygons),
            "max_projection_m":max(distances),"projection_strength":strength,"minimum_face_area_ratio":min(ratios),"degenerate_faces":degenerate,"baseline_degenerate_faces":existing,"newly_degenerate_faces":newly_degenerate,
            "limitations":["Target authored tee required","Nearest-surface projection may distort topology","No skin collision or posed visual validation","Experimental output only"]}
    (out/"cross-fit-report.json").write_text(json.dumps(report,indent=2)+"\n")
    if newly_degenerate: raise ValueError("Newly collapsed garment faces; inspect report")
    bpy.ops.object.select_all(action="DESELECT")
    fitted.select_set(True);rig.select_set(True)
    bpy.context.view_layer.objects.active=fitted
    bpy.ops.export_scene.gltf(filepath=str((out/"cross-fit-tee.glb").resolve()),export_format="GLB",use_selection=True,export_animations=False,export_skins=True)
    print("CROSS_BODY_TEE_TRIAL_PASSED")
if __name__=="__main__": main()

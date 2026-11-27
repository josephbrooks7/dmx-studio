"""Static fit trial against an actual imported human skin mesh.

Creates a reference fabric panel from a connected skin patch, not an authored
outfit. Verifies surface clearance on real triangles without requiring a rig.
"""
import sys
from pathlib import Path
import json
import bpy
from mathutils.bvhtree import BVHTree
from mathutils import Vector

def main():
    src,dst=map(Path,sys.argv[sys.argv.index("--")+1:])
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.wm.usd_import(filepath=str(src.resolve()))
    bpy.context.view_layer.update()
    matches=[o for o in bpy.context.scene.objects if o.type=="MESH" and
             o.name.startswith("CC_Base_Body_001")]
    if len(matches)!=1:
        raise ValueError("Expected exactly one verified female skin mesh; found "+str([o.name for o in matches]))
    body=matches[0]
    mesh=body.data
    mesh.calc_loop_triangles()
    world=body.matrix_world
    vertices=[world @ v.co for v in mesh.vertices]
    triangles=[tuple(t.vertices) for t in mesh.loop_triangles]
    tree=BVHTree.FromPolygons(vertices,triangles,all_triangles=True)
    # Select a contiguous torso-facing surface patch by verified body bounds.
    # Front direction is deliberately chosen from the surface, not assumed.
    lo=min(p.z for p in vertices); hi=max(p.z for p in vertices)
    height=hi-lo
    if not 1.3<height<2.2: raise ValueError("Unexpected body height; verify units/orientation")
    center_x=(min(p.x for p in vertices)+max(p.x for p in vertices))/2
    pool=[]
    normal_transform=world.to_3x3().inverted().transposed()
    for poly in mesh.polygons:
        p=world @ poly.center
        n=(normal_transform @ poly.normal).normalized()
        if lo+.52*height<p.z<lo+.68*height and abs(p.x-center_x)<.08 and abs(n.y)>.65:
            pool.append((poly.index,p,n))
    if not pool: raise ValueError("No suitable torso patch")
    seed=max(pool,key=lambda item:item[1].y)
    sign=1 if seed[2].y>0 else -1
    selected={i for i,p,n in pool if n.y*sign>.65}
    # Keep only the edge-connected component containing the seed.
    edge_faces={}
    for i in selected:
        for e in mesh.polygons[i].edge_keys:
            edge_faces.setdefault(tuple(sorted(e)),[]).append(i)
    seen={seed[0]}; todo=[seed[0]]
    while todo:
        i=todo.pop()
        for e in mesh.polygons[i].edge_keys:
            for j in edge_faces[tuple(sorted(e))]:
                if j not in seen: seen.add(j);todo.append(j)
    used=sorted({v for i in seen for v in mesh.polygons[i].vertices})
    if len(used)<10: raise ValueError("Surface patch too small")
    remap={v:i for i,v in enumerate(used)}
    points=[]; gaps=[]
    for i in used:
        p=vertices[i]
        n=(normal_transform @ mesh.vertices[i].normal).normalized()
        q=p+.008*n
        near,normal,index,distance=tree.find_nearest(q)
        if near is None: raise ValueError("Missing nearest body surface")
        gap=(q-near).dot(normal)
        if gap<.002: raise ValueError("Reference panel clearance failed")
        points.append(tuple(q));gaps.append(gap)
    faces=[tuple(remap[v] for v in mesh.polygons[i].vertices) for i in sorted(seen)]
    fabric=bpy.data.meshes.new("Reference fabric patch")
    fabric.from_pydata(points,[],faces);fabric.update()
    obj=bpy.data.objects.new("Reference fabric patch",fabric)
    bpy.context.scene.collection.objects.link(obj)
    mat=bpy.data.materials.new("Reference fabric");mat.diffuse_color=(.12,.22,.65,1)
    fabric.materials.append(mat)
    dst.mkdir(parents=True,exist_ok=True)
    report={"source":src.name,"skin":body.name,"vertices":len(used),"faces":len(faces),
            "minimum_vertex_clearance_m":min(gaps),"maximum_vertex_clearance_m":max(gaps),
            "limitations":["Generated surface patch, not an existing outfit","Vertex clearance only; no full triangle collision or animation verification","Side chosen geometrically; not verified front"]}
    (dst/"fit-trial.json").write_text(json.dumps(report,indent=2)+"\n")
    bpy.ops.wm.save_as_mainfile(filepath=str((dst/"fit-trial.blend").resolve()))
    print("HUMAN_BODY_STATIC_PATCH_TRIAL_PASSED",json.dumps(report))
if __name__=="__main__": main()

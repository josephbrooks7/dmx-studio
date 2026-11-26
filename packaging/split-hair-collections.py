import bpy, bmesh, json
from pathlib import Path
from mathutils import Vector, Matrix
root=Path.home()/"DMX-Character-Sources"
out=Path.home()/"DMX-Hair-Staging"
out.mkdir(exist_ok=True)
for gender,path,cols,rows in [
 ("female",root/"FemaleHair/source/upload to sketchfab.fbx",[-1.5,-1.2,-.9,-.6,-.3,0],[(0,0),(.4,.25)]),
 ("male",root/"MaleHair/source/21Fles.fbx",[-2.1,-1.75,-1.4,-1.05,-.7,-.35,0],[(0,0),(-.5,0),(-1,0)])]:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=str(path))
    bpy.context.view_layer.update()
    anchors=[Vector((x,y,z+1.65072)) for y,z in rows for x in cols]
    sources=[o for o in bpy.context.scene.objects if o.type=="MESH" and "basemesh" not in o.name.lower()]
    buckets=[[] for _ in anchors]
    for obj in sources:
        bm=bmesh.new()
        bm.from_mesh(obj.data)
        bm.transform(obj.matrix_world)
        remaining=set(bm.verts)
        while remaining:
            seed=remaining.pop()
            group=[seed]
            stack=[seed]
            while stack:
                v=stack.pop()
                for e in v.link_edges:
                    w=e.other_vert(v)
                    if w in remaining:
                        remaining.remove(w)
                        group.append(w)
                        stack.append(w)
            top=max(v.co.z for v in group)
            upper=[v.co for v in group if v.co.z>=top-.04]
            center=sum(upper,Vector())/len(upper)
            idx=min(range(len(anchors)),key=lambda i:(center.x-anchors[i].x)**2+(center.y-anchors[i].y)**2+(center.z-anchors[i].z)**2*.2)
            buckets[idx].append((obj.name,[v.index for v in group]))
        bm.free()
    material=bpy.data.materials.new("Provisional brown hair")
    material.use_nodes=True
    shader=material.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value=(.075,.035,.018,1)
    shader.inputs["Roughness"].default_value=.55
    report=[]
    for i,parts in enumerate(buckets):
        if not parts: continue
        by_source={}
        for name,ids in parts: by_source.setdefault(name,set()).update(ids)
        bpy.ops.object.select_all(action="DESELECT")
        created=[]
        for name,ids in by_source.items():
            src=bpy.data.objects[name]
            bm=bmesh.new()
            bm.from_mesh(src.data)
            bm.verts.ensure_lookup_table()
            bmesh.ops.delete(bm,geom=[v for v in bm.verts if v.index not in ids],context="VERTS")
            bm.transform(Matrix.Translation(-anchors[i]) @ src.matrix_world)
            mesh=bpy.data.meshes.new("Hair")
            bm.to_mesh(mesh)
            bm.free()
            obj=bpy.data.objects.new("Hair",mesh)
            bpy.context.collection.objects.link(obj)
            mesh.materials.clear()
            mesh.materials.append(material)
            for face in mesh.polygons:
                face.material_index=0
                face.use_smooth=True
            obj.select_set(True)
            created.append(obj)
        bpy.context.view_layer.objects.active=created[0]
        target=out/f"{gender}-{i+1:02d}.glb"
        bpy.ops.export_scene.gltf(filepath=str(target),use_selection=True,export_animations=False)
        report.append({"file":target.name,"vertices":sum(len(o.data.vertices) for o in created),"anchor":list(anchors[i])})
        for obj in created: bpy.data.objects.remove(obj,do_unlink=True)
    (out/f"{gender}-inventory.json").write_text(json.dumps(report,indent=2))
    print("HAIR EXPORT",gender,json.dumps(report))

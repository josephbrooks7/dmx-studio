import bpy, json, zipfile, hashlib
from pathlib import Path
src=Path.home()/"DMX-Hair-Staging"
dst=Path.home()/"DMX-Hair-USDZ"
dst.mkdir(exist_ok=True)
report=[]
for gender,count in [("male",21),("female",12)]:
    for i in range(1,count+1):
        name=f"{gender}-{i:02d}"
        source=src/(name+".glb")
        target=dst/(name+".usdz")
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.import_scene.gltf(filepath=str(source))
        meshes=[o for o in bpy.context.scene.objects if o.type=="MESH"]
        if not meshes or not sum(len(o.data.polygons) for o in meshes):
            raise RuntimeError("Empty hair: "+name)
        bpy.context.view_layer.update()
        points=[o.matrix_world @ v.co for o in meshes for v in o.data.vertices]
        bounds=[[min(p[j] for p in points),max(p[j] for p in points)] for j in range(3)]
        bpy.ops.wm.usd_export(filepath=str(target),export_animation=False,export_materials=True)
        with zipfile.ZipFile(target) as z:
            if z.testzip() or not any(n.endswith((".usd",".usdc",".usda")) for n in z.namelist()):
                raise RuntimeError("Invalid USDZ: "+name)
        report.append({"file":target.name,"sha256":hashlib.sha256(target.read_bytes()).hexdigest(),"bounds":bounds,"material":"provisional","license":"unverified"})
        print("EXPORTED",name,target.stat().st_size,bounds)
(dst/"preview-inventory.json").write_text(json.dumps(report,indent=2))
print("TOTAL VALID USDZ",len(report))

# Usage: python3 packaging/normalize-hair-module.py SRC.usdz DST.usdz  (needs: pip install usd-core numpy)
# Convert a Z-up hair module (front = -Y) to Y-up (front = +Z), crown top at origin, plain material.
import sys, numpy as np
from pxr import Usd, UsdGeom, Sdf, UsdShade, UsdUtils, Gf, Vt
src, dst = sys.argv[1], sys.argv[2]
st = Usd.Stage.Open(src)
pts_all, counts, idx, offs = [], [], [], 0
for p in st.Traverse():
    if not p.IsA(UsdGeom.Mesh): continue
    m = UsdGeom.Mesh(p)
    xf = UsdGeom.Xformable(p).ComputeLocalToWorldTransform(Usd.TimeCode.Default())
    P = [list(xf.Transform(v)) for v in m.GetPointsAttr().Get()]
    pts_all += P
    counts += list(m.GetFaceVertexCountsAttr().Get())
    idx += [i + offs for i in m.GetFaceVertexIndicesAttr().Get()]
    offs += len(P)
P = np.array(pts_all, dtype=float)
P = np.stack([P[:,0], P[:,2], -P[:,1]], axis=1)          # Z-up/-Y-front  ->  Y-up/+Z-front
top = P[:,1].max()
crown = P[P[:,1] > top - 0.10]
cx = (crown[:,0].min() + crown[:,0].max()) / 2
cz = (crown[:,2].min() + crown[:,2].max()) / 2
P -= np.array([cx, top, cz])
tmp = dst.replace('.usdz', '.usdc')
out = Usd.Stage.CreateNew(tmp)
UsdGeom.SetStageUpAxis(out, UsdGeom.Tokens.y); UsdGeom.SetStageMetersPerUnit(out, 1.0)
root = UsdGeom.Xform.Define(out, '/HairModule'); out.SetDefaultPrim(root.GetPrim())
mesh = UsdGeom.Mesh.Define(out, '/HairModule/hair')
mesh.CreatePointsAttr(Vt.Vec3fArray([Gf.Vec3f(*v) for v in P]))
mesh.CreateFaceVertexCountsAttr(Vt.IntArray(counts)); mesh.CreateFaceVertexIndicesAttr(Vt.IntArray(idx))
mesh.CreateSubdivisionSchemeAttr('none'); mesh.CreateDoubleSidedAttr(True)
mesh.CreateExtentAttr([Gf.Vec3f(*P.min(0)), Gf.Vec3f(*P.max(0))])
mat = UsdShade.Material.Define(out, '/HairModule/hair_material')
sh = UsdShade.Shader.Define(out, '/HairModule/hair_material/surface'); sh.CreateIdAttr('UsdPreviewSurface')
sh.CreateInput('diffuseColor', Sdf.ValueTypeNames.Color3f).Set(Gf.Vec3f(0.075, 0.035, 0.018))
sh.CreateInput('roughness', Sdf.ValueTypeNames.Float).Set(0.6)
mat.CreateSurfaceOutput().ConnectToSource(sh.ConnectableAPI(), 'surface')
UsdShade.MaterialBindingAPI.Apply(mesh.GetPrim()).Bind(mat)
out.GetRootLayer().Save()
UsdUtils.CreateNewUsdzPackage(Sdf.AssetPath(tmp), dst)
import os; os.remove(tmp)
print(dst, 'pts', len(P), 'w', round(np.ptp(P[:,0]),3), 'h', round(np.ptp(P[:,1]),3), 'd', round(np.ptp(P[:,2]),3))

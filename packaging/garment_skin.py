"""Reference skin-weight transfer from fitted body surface samples.

Uses nearest sample interpolation, not triangle projection. Run offline on
normalized, aligned rest-pose meshes. Bone names must be mapped explicitly.
"""
from math import isfinite
from heapq import nsmallest

def transfer_weights(vertices, body_vertices, body_weights, bone_map,
                     target_bones, neighbors=4, max_influences=4,
                     max_distance=0.05):
    if not body_vertices or len(body_vertices)!=len(body_weights):
        raise ValueError("Missing body skin weights")
    if not isinstance(neighbors,int) or not isinstance(max_influences,int) or min(neighbors,max_influences)<1:
        raise ValueError("Invalid influence limits")
    if not isfinite(max_distance) or max_distance<=0:
        raise ValueError("Invalid maximum distance")
    def point(p):
        if len(p)!=3 or not all(isfinite(v) for v in p):
            raise ValueError("Invalid vertex")
        return tuple(p)
    samples=[point(p) for p in body_vertices]
    valid=set(target_bones)
    weights=[]
    for row in body_weights:
        mapped={}
        for name,w in row.items():
            if not isfinite(w) or w<0: raise ValueError("Invalid weight")
            if not w: continue
            name=bone_map.get(name,name)
            if name not in valid: raise ValueError("Unmapped bone: "+name)
            mapped[name]=mapped.get(name,0)+w
        total=sum(mapped.values())
        if not isfinite(total) or total<=0: raise ValueError("Unweighted body sample")
        weights.append({k:w/total for k,w in mapped.items()})
    out=[]
    for vertex in vertices:
        p=point(vertex)
        near=nsmallest(neighbors,((sum((a-b)**2 for a,b in zip(p,q)),i)
                                    for i,q in enumerate(samples)))
        near=[(d,i) for d,i in near if d<=max_distance**2]
        if not near: raise ValueError("Garment vertex too far from body")
        exact=[(d,i) for d,i in near if d<=1e-18]
        if exact: near=exact
        acc={}
        for d,i in near:
            factor=1.0 if exact else 1.0/max(d,1e-18)
            for bone,w in weights[i].items():
                acc[bone]=acc.get(bone,0)+factor*w
        kept=sorted(acc.items(),key=lambda item:(-item[1],item[0]))[:max_influences]
        total=sum(w for _,w in kept)
        out.append({bone:w/total for bone,w in kept})
    return out

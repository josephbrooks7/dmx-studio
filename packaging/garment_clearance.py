"""Offline garment clearance correction using oriented body surface samples.

Local tangent-plane approximation. Not a watertight collision solver.
Use normalized meters and aligned rest-pose meshes. Supply region-matched
surface samples with outward normals; validate against actual triangles.
"""
from dataclasses import dataclass
from math import isfinite, sqrt

@dataclass(frozen=True)
class SurfaceSample:
    point: tuple
    normal: tuple
    region: str

def _vec(v):
    if len(v)!=3 or not all(isfinite(x) for x in v):
        raise ValueError("Expected finite 3D vector")
    return tuple(v)

def _dot(a,b):
    return sum(x*y for x,y in zip(a,b))

def _sub(a,b):
    return tuple(x-y for x,y in zip(a,b))

def correct_clearance(vertices, regions, samples, clearance=.005,
                      max_search=.05, max_correction=.025, iterations=3):
    """Return corrected points plus unresolved vertex indices.

    Nearest region-matched sample defines a local tangent plane. A bounded
    outward displacement enforces the requested signed clearance from that
    plane. Requery after each correction. Missing samples, excessive required
    displacement or residual penetration are explicitly reported.
    """
    if len(vertices)!=len(regions):
        raise ValueError("Each vertex needs a region")
    if not all(isfinite(x) for x in (clearance,max_search,max_correction)):
        raise ValueError("Nonfinite limits")
    if clearance<0 or max_search<=0 or max_correction<0:
        raise ValueError("Invalid correction limits")
    if not isinstance(iterations,int) or not 1<=iterations<=100:
        raise ValueError("Invalid iteration count")
    grouped={}
    for s in samples:
        p,n=_vec(s.point),_vec(s.normal)
        length=sqrt(_dot(n,n))
        if not isfinite(length) or length<1e-9:
            raise ValueError("Invalid surface normal")
        grouped.setdefault(s.region,[]).append((p,tuple(v/length for v in n)))
    def nearest(p,region):
        pool=grouped.get(region,[])
        if not pool: return None
        q,n=min(pool,key=lambda item:_dot(_sub(p,item[0]),_sub(p,item[0])))
        d=_sub(p,q)
        if _dot(d,d)>max_search**2: return None
        return n,_dot(d,n)
    output=[]; unresolved=[]
    for i,(vertex,region) in enumerate(zip(vertices,regions)):
        p=_vec(vertex); budget=max_correction
        for _ in range(iterations):
            hit=nearest(p,region)
            if hit is None: break
            n,signed=hit
            needed=clearance-signed
            if needed<=1e-9 or budget<=1e-9: break
            step=min(needed,budget)
            p=tuple(a+step*b for a,b in zip(p,n))
            budget-=step
        hit=nearest(p,region)
        if hit is None or hit[1]<clearance-1e-8:
            unresolved.append(i)
        output.append(p)
    return output,unresolved

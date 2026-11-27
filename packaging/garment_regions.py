"""Rest-pose garment region fitting using explicit orthonormal frames.

Region assignments are supplied by the author; no automatic segmentation,
seam welding, skinning or collision guarantees are implied.
"""
from dataclasses import dataclass
from math import isfinite, sqrt
from body_fit import fit_vertices

def dot(a,b): return sum(x*y for x,y in zip(a,b))
def sub(a,b): return tuple(x-y for x,y in zip(a,b))
def cross(a,b): return (a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0])
def unit(v):
    n=sqrt(dot(v,v))
    if not isfinite(n) or n<1e-9: raise ValueError("Degenerate frame")
    return tuple(x/n for x in v)

@dataclass(frozen=True)
class Frame:
    origin: tuple
    x: tuple
    y: tuple
    z: tuple

    @classmethod
    def from_landmarks(cls, start, end, forward):
        if any(len(v)!=3 or not all(isfinite(x) for x in v) for v in (start,end,forward)):
            raise ValueError("Expected finite 3D landmarks")
        y=unit(sub(end,start))
        x=unit(cross(y,forward))
        z=cross(x,y)
        return cls(tuple(start),x,y,z)

    def local(self,p):
        d=sub(p,self.origin)
        return tuple(dot(d,a) for a in (self.x,self.y,self.z))

    def world(self,p):
        return tuple(self.origin[i]+sum(p[j]*a[i] for j,a in enumerate((self.x,self.y,self.z))) for i in range(3))

@dataclass(frozen=True)
class Region:
    source_frame: Frame
    target_frame: Frame
    source_sections: tuple
    target_sections: tuple
    clearance: float=0.0

def fit_regions(vertices, assignments, regions):
    """Fit explicitly assigned regions; blend shared seam vertices by weights.

    assignments[i] is a dict {region_name: nonnegative weight}, sum positive.
    Regions may represent torso, left/right arm or left/right leg. Section
    coordinates must be measured in each region's frame, not world space.
    """
    if len(vertices)!=len(assignments): raise ValueError("Missing assignments")
    output=[]
    for p,weights in zip(vertices,assignments):
        if len(p)!=3 or not all(isfinite(v) for v in p): raise ValueError("Invalid vertex")
        if not weights or any(not isfinite(w) or w<0 for w in weights.values()):
            raise ValueError("Invalid region weights")
        total=sum(weights.values())
        if not isfinite(total) or total<=0: raise ValueError("Invalid total weight")
        result=[0.,0.,0.]
        for name,w in weights.items():
            if not w: continue
            r=regions[name]
            q=r.source_frame.local(p)
            q=fit_vertices([q],r.source_sections,r.target_sections,r.clearance)[0]
            q=r.target_frame.world(q)
            for i in range(3): result[i]+=q[i]*(w/total)
        output.append(tuple(result))
    return output

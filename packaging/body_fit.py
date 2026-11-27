"""Pure Python reference garment fitting by measured body cross sections.

Inputs must share normalized coordinates: meters, Y up, +Z front.
This is a rest-pose approximation, not collision detection or skinning.
"""
from dataclasses import dataclass
from math import isfinite

@dataclass(frozen=True)
class Section:
    y: float
    cx: float
    cz: float
    half_width: float
    half_depth: float

def validate(sections):
    if len(sections) < 2:
        raise ValueError("At least two measured sections required")
    for i, s in enumerate(sections):
        if not all(isfinite(v) for v in (s.y,s.cx,s.cz,s.half_width,s.half_depth)):
            raise ValueError("Nonfinite section")
        if min(s.half_width,s.half_depth) <= 0:
            raise ValueError("Section extents must be positive")
        if i and s.y <= sections[i-1].y:
            raise ValueError("Sections must be in ascending anatomical order")

def fit_vertices(vertices, source, target, clearance=0.0):
    """Map corresponding anatomical levels, preserving normalized offsets.

    Intended for torso garments only. Sleeves, legs, asymmetric poses and
    collision corrections require region-specific fitting.
    Clearance is an optional radial expansion in meters.
    """
    validate(source)
    validate(target)
    if len(source) != len(target):
        raise ValueError("Source and target must have corresponding landmarks")
    if not isfinite(clearance) or clearance < 0:
        raise ValueError("Clearance must be finite and nonnegative")
    def mix(a,b,t):
        return a+(b-a)*t
    result=[]
    for x,y,z in vertices:
        if not all(isfinite(v) for v in (x,y,z)):
            raise ValueError("Nonfinite vertex")
        if y < source[0].y or y > source[-1].y:
            raise ValueError("Vertex outside measured torso; use appropriate region")
        i=next((i for i in range(len(source)-1) if y <= source[i+1].y),len(source)-2)
        a,b=source[i:i+2]
        c,d=target[i:i+2]
        t=(y-a.y)/(b.y-a.y)
        u=(x-mix(a.cx,b.cx,t))/mix(a.half_width,b.half_width,t)
        v=(z-mix(a.cz,b.cz,t))/mix(a.half_depth,b.half_depth,t)
        result.append((mix(c.cx,d.cx,t)+u*(mix(c.half_width,d.half_width,t)+clearance),
                       mix(c.y,d.y,t),
                       mix(c.cz,d.cz,t)+v*(mix(c.half_depth,d.half_depth,t)+clearance)))
    return result

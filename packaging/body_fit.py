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


@dataclass(frozen=True)
class AnatomySection:
    y: float
    cx: float
    cz: float
    half_width: float
    front_depth: float
    back_depth: float

def fit_anatomical_torso(vertices, source, target, clearance=0.0):
    """Independent anterior/posterior fitting with absolute exterior ease.
    
    Landmarks must be measured from the actual bodies, not clothing.
    Only garment vertices are returned; body geometry is never modified.
    This is an envelope approximation, not individual breast contours.
    """
    if len(source)!=len(target) or len(source)<2:
        raise ValueError("Corresponding anatomical sections required")
    if not isfinite(clearance) or clearance<0:
        raise ValueError("Invalid clearance")
    for sections in (source,target):
        for i,s in enumerate(sections):
            if not all(isfinite(v) for v in (s.y,s.cx,s.cz,s.half_width,s.front_depth,s.back_depth)):
                raise ValueError("Nonfinite anatomy")
            if min(s.half_width,s.front_depth,s.back_depth)<=0 or (i and s.y<=sections[i-1].y):
                raise ValueError("Invalid anatomical section")
    def mix(a,b,t): return a+(b-a)*t
    def ease(v,old,new):
        sign=1 if v>=0 else -1
        magnitude=abs(v)
        return sign*(new*min(magnitude/old,1)+max(0,magnitude-old)+clearance*min(magnitude/old,1))
    result=[]
    for x,y,z in vertices:
        if not all(isfinite(v) for v in (x,y,z)) or not source[0].y<=y<=source[-1].y:
            raise ValueError("Invalid torso vertex")
        i=next(i for i in range(len(source)-1) if y<=source[i+1].y)
        a,b=source[i:i+2];c,d=target[i:i+2]
        t=(y-a.y)/(b.y-a.y)
        def interp(p,q,k): return mix(getattr(p,k),getattr(q,k),t)
        sx=interp(a,b,"cx");sz=interp(a,b,"cz")
        depth="front_depth" if z>=sz else "back_depth"
        result.append((interp(c,d,"cx")+ease(x-sx,interp(a,b,"half_width"),interp(c,d,"half_width")),
                       interp(c,d,"y"),
                       interp(c,d,"cz")+ease(z-sz,interp(a,b,depth),interp(c,d,depth))))
    return result

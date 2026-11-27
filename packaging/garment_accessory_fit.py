"""Reference accessory attachment in anatomical landmark frames (meters).

Only accessory vertices are transformed. Hair draping and collision handling
require separate surface-aware fitting. Eyewear lenses can use rigid mode.
"""
from math import isfinite
from garment_regions import Frame

def fit_accessory(vertices, source_frame, target_frame, source_size, target_size, *, adjustable_axes=(True,True,True), max_scale_ratio=2.0):
    """Retarget an accessory around its attachment origin.
    
    Sizes correspond to lateral, vertical, forward anatomical directions.
    Rigid components can disable scaling on any axis. Frames must be constructed
    from homologous landmarks via Frame.from_landmarks.
    """
    if not isinstance(source_frame,Frame) or not isinstance(target_frame,Frame):
        raise ValueError("Expected anatomical frames")
    if any(len(v)!=3 for v in (source_size,target_size,adjustable_axes)):
        raise ValueError("Expected three dimensions")
    if not isfinite(max_scale_ratio) or max_scale_ratio<1:
        raise ValueError("Invalid scaling limit")
    if not all(isfinite(v) and v>0 for v in (*source_size,*target_size)):
        raise ValueError("Invalid anatomical dimensions")
    ratios=tuple(t/s if enabled else 1.0 for s,t,enabled in zip(source_size,target_size,adjustable_axes))
    if any(r>max_scale_ratio or r<1/max_scale_ratio for r in ratios):
        raise ValueError("Accessory requires a different authored size")
    output=[]
    for p in vertices:
        if len(p)!=3 or not all(isfinite(v) for v in p):
            raise ValueError("Invalid accessory vertex")
        q=source_frame.local(p)
        output.append(target_frame.world(tuple(x*r for x,r in zip(q,ratios))))
    return output

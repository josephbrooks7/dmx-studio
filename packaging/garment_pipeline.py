"""Offline garment fitting orchestration for normalized, aligned reference meshes."""
from dataclasses import dataclass
from garment_regions import fit_regions
from garment_clearance import correct_clearance
from garment_skin import transfer_weights

@dataclass(frozen=True)
class FitResult:
    vertices: tuple
    weights: tuple
    unresolved: tuple

    @property
    def ready_for_review(self):
        return not self.unresolved

def fit_garment(vertices, assignments, regions, surface_regions, surface_samples,
                body_vertices, body_weights, bone_map, target_bones, *,
                clearance=.005, max_search=.05, max_correction=.025,
                max_skin_distance=.05, strict=True):
    """Fit, correct clearance, then transfer target-body skin weights.

    Inputs use meters and normalized rest-pose coordinates. Vertex order stays
    unchanged. Caller retains faces, UVs, materials and other mesh attributes.
    Region assignments and surface labels must already be validated.
    Strict mode refuses output with unresolved local clearance checks.
    Successful output still requires mesh and posed visual validation.
    """
    if not vertices:
        raise ValueError("Empty garment")
    fitted=fit_regions(vertices,assignments,regions)
    corrected,unresolved=correct_clearance(fitted,surface_regions,surface_samples,
        clearance=clearance,max_search=max_search,max_correction=max_correction)
    if strict and unresolved:
        raise ValueError("Unresolved garment clearance at %d vertices" % len(unresolved))
    weights=transfer_weights(corrected,body_vertices,body_weights,bone_map,
        target_bones,max_distance=max_skin_distance)
    return FitResult(tuple(corrected),tuple(weights),tuple(unresolved))

"""Blender adapter for applying a validated offline garment fit.

Run inside Blender. All input coordinates must be normalized world-space
meters with Y up, +Z front. Matrices explicitly map Blender world to that
space and back; callers must supply and verify the transform.
"""
from math import isfinite
from garment_pipeline import fit_garment

def fit_blender_garment(garment, target_armature, to_normalized, *,
                        assignments, regions, surface_regions, surface_samples,
                        body_vertices, body_weights, bone_map, name=None, **options):
    """Create a separate fitted object; leave source mesh and rig unchanged.

    Requires Object mode, a writable collection and a rest-pose garment
    without shape keys or geometry modifiers. Retains faces, UVs and materials.
    The caller supplies validated region and body sampling data.
    """
    import bpy
    from mathutils import Vector
    if bpy.context.mode != "OBJECT":
        raise ValueError("Object mode required")
    if garment.type != "MESH" or target_armature.type != "ARMATURE":
        raise ValueError("Expected garment mesh and target armature")
    if garment.data.shape_keys:
        raise ValueError("Shape-key transfer is not implemented")
    if any(m.type != "ARMATURE" for m in garment.modifiers):
        raise ValueError("Apply or explicitly handle geometry modifiers first")
    if not garment.users_collection:
        raise ValueError("Garment must belong to a collection")
    if target_armature.data.pose_position != "REST":
        raise ValueError("Target armature must be in rest position")
    world = garment.matrix_world.copy()
    inverse = (to_normalized @ world).inverted()
    points = [tuple(to_normalized @ world @ v.co) for v in garment.data.vertices]
    bones = {b.name for b in target_armature.data.bones if b.use_deform}
    if options.get("strict", True) is not True:
        raise ValueError("Blender adapter requires strict fitting")
    result = fit_garment(points, assignments, regions, surface_regions,
        surface_samples, body_vertices, body_weights, bone_map, bones, **options)
    if not result.ready_for_review:
        raise ValueError("Unresolved clearance")
    local = [inverse @ Vector(p) for p in result.vertices]
    if any(not all(isfinite(x) for x in p) for p in local):
        raise ValueError("Nonfinite fitted geometry")
    mesh = garment.data.copy()
    output = None
    try:
        output = garment.copy()
        output.data = mesh
        output.name = name or garment.name + "_fitted"
        output.parent = None
        output.animation_data_clear()
        output.constraints.clear()
        output.modifiers.clear()
        output.vertex_groups.clear()
        output.matrix_world = world
        for v,p in zip(mesh.vertices,local):
            v.co = p
        groups = {}
        for i,row in enumerate(result.weights):
            for bone,w in row.items():
                if bone not in groups:
                    groups[bone] = output.vertex_groups.new(name=bone)
                groups[bone].add([i],w,"REPLACE")
        modifier = output.modifiers.new(name="Target body rig",type="ARMATURE")
        modifier.object = target_armature
        modifier.use_vertex_groups = True
        mesh.update()
        garment.users_collection[0].objects.link(output)
        return output,result
    except Exception:
        if output is not None:
            bpy.data.objects.remove(output,do_unlink=True)
        if mesh.users == 0:
            bpy.data.meshes.remove(mesh)
        raise

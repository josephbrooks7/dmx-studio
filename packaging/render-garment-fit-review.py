"""Render a target character in its own garment and in a cross-body fitted garment.

The target's own garment in the same slot is hidden; the exposed-skin mesh that matches
the top being worn is shown (Skin_tee for tees, Skin_shirt for shirts).

usage: blender --background --python render-garment-fit-review.py -- TARGET.glb FITTED.glb GARMENT OUTDIR
"""
import sys
from pathlib import Path
import bpy
from mathutils import Vector, Matrix, Quaternion
from math import radians

TOP_SKIN = {"Top_tee": "Skin_tee", "Top_shirt": "Skin_shirt"}


def load(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(path.resolve()))
    return set(bpy.data.objects) - before


def named(objects, name):
    found = [o for o in objects if o.type == "MESH" and o.name.split(".")[0] == name]
    if len(found) != 1:
        raise ValueError(f"Expected one {name}")
    return found[0]


def main():
    target, fitted_path, garment, out = sys.argv[sys.argv.index("--") + 1:]
    target, fitted_path, out = Path(target), Path(fitted_path), Path(out)
    out.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    objects = load(target)
    top = garment if garment in TOP_SKIN else "Top_tee"
    visible = {"Body", "Hair", TOP_SKIN[top], top, "Trousers", "Shoes"}
    for o in objects:
        if o.type == "MESH":
            o.hide_render = o.name.split(".")[0] not in visible
    own = named(objects, garment)
    fitted_objs = load(fitted_path)
    fitted = named(fitted_objs, "Fitted_" + garment)
    liner = [o for o in fitted_objs if o.type == "MESH" and o.name.startswith("Liner_")]
    # Bind the fitted garment (and liner) to the character's own posed skeleton, exactly as the app
    # does, instead of the rest-pose copy of the rig that came in with the garment file.
    rig = [m.object for m in own.modifiers if m.type == "ARMATURE" and m.object][0]
    for o in [fitted] + liner:
        mw = o.matrix_world.copy()
        for m in o.modifiers:
            if m.type == "ARMATURE":
                m.object = rig
        o.parent = rig
        o.matrix_world = mw
    for o in fitted_objs:
        if o.type == "ARMATURE":
            o.hide_render = True
    bpy.context.view_layer.update()
    pts = [o.matrix_world @ v.co for o in objects if o.type == "MESH" and not o.hide_render for v in o.data.vertices]
    lo = Vector(tuple(min(p[i] for p in pts) for i in range(3)))
    hi = Vector(tuple(max(p[i] for p in pts) for i in range(3)))
    height = hi.z - lo.z
    # frame the garment's region: tops = upper body, trousers = lower body, shoes = feet
    region = {"Trousers": (0.0, 0.62), "Shoes": (0.0, 0.2)}.get(garment, (0.45, 1.0))
    zlo, zhi = lo.z + height * region[0], lo.z + height * region[1]
    center = Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, (zlo + zhi) / 2))
    span = zhi - zlo
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"; scene.cycles.samples = 24; scene.cycles.use_denoising = True
    scene.render.resolution_x = 720; scene.render.resolution_y = 900
    scene.world = bpy.data.worlds.new("Review world"); scene.world.use_nodes = True
    bg = scene.world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (.18, .18, .18, 1); bg.inputs[1].default_value = .5

    def aim(o, p):
        o.rotation_euler = (p - o.location).to_track_quat("-Z", "Y").to_euler()
    for name, offset, power in [("Key", (2, -3, 3), 350), ("Fill", (-2, -2, 1), 180), ("Rim", (1, 2, 2), 250)]:
        light = bpy.data.lights.new(name, "AREA"); light.energy = power * height ** 2
        light.shape = "DISK"; light.size = height
        obj = bpy.data.objects.new(name, light); scene.collection.objects.link(obj)
        obj.location = center + Vector(offset) * height; aim(obj, center)
    cam_data = bpy.data.cameras.new("cam"); cam_data.type = "ORTHO"
    cam_data.ortho_scale = max(span * 1.25, (hi.x - lo.x) * 1.15 if garment.startswith("Top") else span * 1.25)
    cam = bpy.data.objects.new("cam", cam_data); scene.collection.objects.link(cam); scene.camera = cam
    for state in ("original", "fitted"):
        own.hide_render = state != "original"
        fitted.hide_render = state != "fitted"
        for l in liner:
            l.hide_render = state != "fitted"
        for angle, offset in [("front", (0, -3, 0)), ("profile", (3, 0, 0)), ("back", (0, 3, 0))]:
            cam.location = center + Vector(offset) * height; aim(cam, center)
            scene.render.filepath = str((out / f"{state}-{angle}.png").resolve())
            bpy.ops.render.render(write_still=True)

    # Pose test: the same fitted garment on the character in other poses. Clothes are bound to the
    # body's skeleton, so they must follow; anything poking through shows up here.
    from math import radians
    from mathutils import Quaternion
    own.hide_render = True; fitted.hide_render = False
    for l in liner:
        l.hide_render = False
    # Performance gestures (shared with the stage performer's gesture set).
    # ("aim", (x, y, z)): point that limb bone in a world direction. The character faces -Y, its
    # left is +X and up is +Z. ("tilt", axis, deg): turn a bone about a world axis (head, spine).
    # ("curl", deg): bend a finger joint. ("drop", metres): lower the hips (crouches).
    def curl(side, fingers, deg=80):
        return {f"mixamorig:{side}Hand{f}{k}": ("curl", deg) for f in fingers for k in (1, 2, 3)}
    def mirror(d):
        out = {}
        for k, v in d.items():
            if v[0] == "aim":
                out[k.replace("Left", "#").replace("Right", "Left").replace("#", "Right")] = ("aim", (-v[1][0], v[1][1], v[1][2]))
        return out
    A = "aim"
    mic = {"mixamorig:RightArm": (A, (-0.3, -0.5, -0.8)), "mixamorig:RightForeArm": (A, (0.35, -0.45, 0.85)),
           **curl("Right", ("Index", "Middle", "Ring", "Pinky"), 85)}
    arms_up = {"mixamorig:LeftArm": (A, (0.25, 0, 1)), "mixamorig:LeftForeArm": (A, (0.15, 0, 1))}
    arms_out = {"mixamorig:LeftArm": (A, (1, 0, 0.05)), "mixamorig:LeftForeArm": (A, (1, 0, 0.05))}
    victory = {"mixamorig:LeftArm": (A, (0.6, 0, 1)), "mixamorig:LeftForeArm": (A, (0.6, 0, 1))}
    wide_legs = {"mixamorig:LeftUpLeg": (A, (0.4, 0, -1)), "mixamorig:LeftLeg": (A, (0.4, 0, -1))}
    poses = {
        "pose-arms-up": {**arms_up, **mirror(arms_up)},
        "pose-arms-out": {**arms_out, **mirror(arms_out)},
        "pose-mic-hold": {**mic, "mixamorig:LeftArm": (A, (0.2, 0, -1))},
        "pose-arms-crossed": {"mixamorig:LeftArm": (A, (0.2, -0.45, -0.85)), "mixamorig:LeftForeArm": (A, (-1, -0.3, 0.15)),
                              "mixamorig:RightArm": (A, (-0.2, -0.5, -0.85)), "mixamorig:RightForeArm": (A, (1, -0.35, 0.25))},
        "pose-peace-sign": {"mixamorig:RightArm": (A, (-0.55, -0.2, 0.8)), "mixamorig:RightForeArm": (A, (-0.2, -0.1, 1)),
                            **curl("Right", ("Ring", "Pinky"), 90), "mixamorig:RightHandThumb2": ("curl", 45)},
        "pose-rock-horns": {"mixamorig:RightArm": (A, (-0.3, -0.1, 1)), "mixamorig:RightForeArm": (A, (-0.1, 0, 1)),
                            **curl("Right", ("Middle", "Ring"), 90), "mixamorig:RightHandThumb2": ("curl", 45)},
        # from real stage photos
        "pose-mic-stand-sing": {**mic, "mixamorig:LeftArm": (A, (0.15, 0.05, -1)),
                                "mixamorig:Spine1": ("tilt", (1, 0, 0), -8), "mixamorig:Head": ("tilt", (1, 0, 0), 10)},
        "pose-wide-stance-bass": {**wide_legs, **mirror(wide_legs),
                                  "mixamorig:LeftArm": (A, (0.35, -0.5, -0.8)), "mixamorig:LeftForeArm": (A, (-0.8, -0.55, 0.1)),
                                  "mixamorig:RightArm": (A, (-0.3, -0.3, -0.9)), "mixamorig:RightForeArm": (A, (0.6, -0.6, -0.4)),
                                  "mixamorig:Head": ("tilt", (1, 0, 0), -20)},
        "pose-victory-v": {**victory, **mirror(victory), **curl("Right", ("Index", "Middle", "Ring", "Pinky"), 85)},
        "pose-crouch-peace": {"mixamorig:Hips": ("drop", 0.38),
                              "mixamorig:LeftUpLeg": (A, (0.45, -0.9, -0.05)), "mixamorig:LeftLeg": (A, (0.15, 0.25, -1)),
                              "mixamorig:RightUpLeg": (A, (-0.45, -0.9, -0.05)), "mixamorig:RightLeg": (A, (-0.15, 0.25, -1)),
                              **mic, "mixamorig:LeftArm": (A, (0.7, -0.2, 0.7)), "mixamorig:LeftForeArm": (A, (0.2, -0.1, 1)),
                              **curl("Left", ("Ring", "Pinky"), 90)},
        "pose-fist-up-wide": {**wide_legs, **mirror(wide_legs),
                              "mixamorig:LeftArm": (A, (0.1, 0, 1)), "mixamorig:LeftForeArm": (A, (0.05, 0, 1)),
                              **curl("Left", ("Index", "Middle", "Ring", "Pinky"), 90),
                              "mixamorig:RightArm": (A, (-0.35, -0.1, -0.95)), "mixamorig:Head": ("tilt", (1, 0, 0), 20)},
        "pose-step": {"mixamorig:LeftUpLeg": (A, (0.05, -0.5, -0.85)), "mixamorig:LeftLeg": (A, (0.05, 0.1, -1)),
                      "mixamorig:RightUpLeg": (A, (-0.05, 0.25, -1))},
    }
    # full-body framing with headroom for raised arms
    cam_data.ortho_scale = height * 1.45
    center = Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z + height * 0.6))
    # The character file carries an animation that would reset the bones every frame. Freeze its
    # current pose, drop the animation, then layer each gesture on top of that pose.
    base_pose = {pb.name: (pb.location.copy(), pb.rotation_quaternion.copy(), pb.scale.copy()) for pb in rig.pose.bones}
    for pb in rig.pose.bones:
        pb.rotation_mode = "QUATERNION"
    for o in bpy.data.objects:   # drop the action and any stacked NLA tracks on every rig
        if o.animation_data:
            o.animation_data_clear()
    for name, (loc, rot, scl) in base_pose.items():
        pb = rig.pose.bones[name]; pb.location, pb.rotation_quaternion, pb.scale = loc, rot, scl
    bpy.context.view_layer.update()
    world3 = rig.matrix_world.to_3x3()
    to_arm = world3.inverted()

    def apply(name, spec):
        pb = rig.pose.bones.get(name)
        if pb is None:
            return
        m = pb.matrix.copy()
        if spec[0] == "aim":
            want = (to_arm @ Vector(spec[1])).normalized()
            have = m.to_3x3().col[1].normalized()   # a bone points along its local Y
            rot = have.rotation_difference(want).to_matrix()
            pb.matrix = Matrix.Translation(m.translation) @ (rot @ m.to_3x3()).to_4x4()
            bpy.context.view_layer.update()
            # where the bone really points now, in world space, as measured from its head and tail
            got = (rig.matrix_world @ pb.tail - rig.matrix_world @ pb.head).normalized()
            print("POSE_AIM", name, "want", tuple(round(c, 2) for c in Vector(spec[1]).normalized()),
                  "got", tuple(round(c, 2) for c in got), "match", round(got.dot(Vector(spec[1]).normalized()), 2))
        elif spec[0] == "tilt":
            rot = Quaternion(to_arm @ Vector(spec[1]), radians(spec[2])).to_matrix()
            pb.matrix = Matrix.Translation(m.translation) @ (rot @ m.to_3x3()).to_4x4()
        elif spec[0] == "drop":
            m.translation -= to_arm @ Vector((0, 0, spec[1] * height / 1.75))
            pb.matrix = m
        elif spec[0] == "curl":
            pb.rotation_quaternion = pb.rotation_quaternion @ Quaternion((1, 0, 0), radians(spec[1]))
        bpy.context.view_layer.update()

    order = ["Hips", "Spine", "Spine1", "Spine2", "Neck", "Head", "UpLeg", "Leg", "Shoulder", "Arm", "ForeArm", "Hand"]
    def rank(name):
        base = name.split(":")[-1].replace("Left", "").replace("Right", "")
        return order.index(base) if base in order else len(order)
    print("RIG", rig.name, "parent", rig.parent.name if rig.parent else None,
          "world", [tuple(round(c, 3) for c in row) for row in rig.matrix_world])
    if garment != "Top_tee":   # pose tests on the tee only until posing is verified
        poses = {}
    for pose_name, bones in poses.items():
        print("POSE", pose_name)
        for name in sorted(bones, key=rank):
            apply(name, bones[name])
        # Does the rendered body follow the posed skeleton? Compare the evaluated (deformed) skin
        # vertex most attached to each hand with that hand bone's head.
        dg = bpy.context.evaluated_depsgraph_get()
        for side in ("Left", "Right"):
            bone = f"mixamorig:{side}Hand"
            pbh = rig.pose.bones.get(bone)
            if pbh is None:
                continue
            want = rig.matrix_world @ pbh.head
            best = None
            for o in objects:
                if o.type != "MESH" or o.hide_render or bone not in o.vertex_groups:
                    continue
                gi = o.vertex_groups[bone].index
                ev = o.evaluated_get(dg)
                me = ev.to_mesh()
                for v in o.data.vertices:
                    w = next((g.weight for g in v.groups if g.group == gi), 0)
                    if w > 0.9 and v.index < len(me.vertices):
                        p = ev.matrix_world @ me.vertices[v.index].co
                        d = (p - want).length
                        if best is None or d < best[0]:
                            best = (d, o.name, tuple(round(c, 2) for c in p))
                ev.to_mesh_clear()
            print("POSE_CHECK", pose_name, side, "bone", tuple(round(c, 2) for c in want), "skin", best)
        for angle, offset in [("front", (0.8, -3, 0))]:
            cam.location = center + Vector(offset) * height; aim(cam, center)
            scene.render.filepath = str((out / f"{pose_name}-{angle}.png").resolve())
            bpy.ops.render.render(write_still=True)
        for name, (loc, rot, scl) in base_pose.items():
            pb = rig.pose.bones[name]; pb.location, pb.rotation_quaternion, pb.scale = loc, rot, scl
        bpy.context.view_layer.update()

if __name__ == "__main__":
    main()

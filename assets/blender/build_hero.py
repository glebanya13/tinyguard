"""Hero: young guardian knight (chibi proportions, ~1.2 m). Faces -Y.

Hierarchy (all pivots placed for the idle animation):
Hero (empty) -> Legs, Body -> Head, ArmL (shield), ArmR -> Sword, Cape
"""
import math

import bmesh
import bpy
from mathutils import Matrix, Vector

import tg_common as tg

HEAD_C = Vector((0, 0, 0.90))
HEAD_R = Vector((0.205, 0.185, 0.195))  # head ellipsoid radii


def head_front_y(x: float, z: float, lift: float = 0.0) -> float:
    """y of the head surface (front, -Y side) at (x, z), pushed out by lift."""
    k = 1 - (x / HEAD_R.x) ** 2 - ((z - HEAD_C.z) / HEAD_R.z) ** 2
    return -HEAD_R.y * math.sqrt(max(k, 0.0)) - lift


def build_legs():
    """Two legs pivoting at the hips (for the walk cycle)."""
    legs = []
    for sx in (-1, 1):
        x = 0.085 * sx
        boot = tg.sphere(f"boot{sx}", (0.13, 0.20, 0.12), (x, -0.025, 0.06), "leather", seg=16, rings=8)
        tg.deform(boot, lambda c: Vector((c.x, c.y, max(c.z, -0.055))))  # flat sole
        cuff = tg.cylinder(f"cuff{sx}", 0.066, 0.07, 0.045, (x, 0, 0.095), "leather", verts=14)
        band = tg.torus(f"band{sx}", 0.068, 0.009, (x, 0, 0.14), "gold", seg=16, minor_seg=6)
        leg = tg.cylinder(f"leg{sx}", 0.056, 0.06, 0.14, (x, 0, 0.12), "cream", verts=12)
        part = tg.join([boot, cuff, band, leg], "LegR" if sx < 0 else "LegL")
        tg.pivot(part, (x, 0, 0.24))
        legs.append(part)
    return legs


def build_skirt():
    skirt = tg.lathe("skirt", [(0.20, 0.205), (0.21, 0.23), (0.19, 0.30), (0.165, 0.38)], "cream", steps=20)
    hem = tg.torus("hem", 0.203, 0.013, (0, 0, 0.212), "gold", seg=24, minor_seg=6)
    return [skirt, hem]


def build_body():
    torso = tg.lathe("torso", [(0.15, 0.36), (0.175, 0.42), (0.19, 0.50), (0.182, 0.58), (0.15, 0.645), (0.085, 0.69)],
                     "armor", steps=20)
    tg.deform(torso, lambda c: Vector((c.x, c.y * 0.82, c.z)))
    tg.add_subsurf(torso, 1)
    tg.shade(torso, 60)
    belt = tg.torus("belt", 0.17, 0.024, (0, 0, 0.40), "leather", seg=24, minor_seg=6, scale=(1, 0.84, 1))
    buckle = tg.box("buckle", (0.065, 0.025, 0.05), (0, -0.145, 0.40), "gold", bevel=0.008)
    gem = tg.sphere("crest", (0.085, 0.03, 0.10), (0, -0.152, 0.53), "gold", seg=8, rings=4)
    gem_core = tg.sphere("crest_core", (0.04, 0.02, 0.05), (0, -0.165, 0.535), "armor_dark", seg=8, rings=4)
    neck = tg.cylinder("neck", 0.055, 0.05, 0.07, (0, 0.0, 0.66), "skin", verts=12)
    parts = [torso, belt, buckle, gem, gem_core, neck, *build_skirt()]
    for sx in (-1, 1):
        pad = tg.sphere(f"pauldron{sx}", (0.17, 0.16, 0.12), (0.19 * sx, 0.0, 0.635), "armor", seg=16, rings=8)
        tg.deform(pad, lambda c: Vector((c.x, c.y, max(c.z, -0.02))))
        rim = tg.torus(f"pauldron_rim{sx}", 0.083, 0.011, (0.19 * sx, 0.0, 0.618), "gold", seg=20, minor_seg=6,
                       scale=(1, 0.95, 1))
        clasp = tg.sphere(f"clasp{sx}", (0.04, 0.03, 0.04), (0.11 * sx, -0.11, 0.655), "gold", seg=10, rings=6)
        parts += [pad, rim, clasp]
    body = tg.join(parts, "Body")
    tg.pivot(body, (0, 0, 0.38))
    return body


def build_head():
    c = HEAD_C
    head = tg.sphere("skull", (HEAD_R.x * 2, HEAD_R.y * 2, HEAD_R.z * 2), c, "skin", seg=26, rings=14)
    # Fuller cheeks, slightly narrower top: a friendlier chibi face.
    tg.deform(head, lambda v: Vector((v.x * (1.0 + 0.06 * max(0.0, -(v.z) / HEAD_R.z)), v.y, v.z)))
    parts = [head]
    for sx in (-1, 1):
        ex, ez = 0.08 * sx, 0.88
        ey = head_front_y(ex, ez) + 0.02
        eye = tg.sphere(f"eye{sx}", (0.084, 0.044, 0.112), (ex, ey, ez), "eye", seg=14, rings=8)
        hl1 = tg.sphere(f"hl{sx}", (0.03, 0.012, 0.03), (ex + 0.018, ey - 0.021, ez + 0.03), "white", seg=8, rings=4)
        hl2 = tg.sphere(f"hl2{sx}", (0.014, 0.008, 0.014), (ex - 0.018, ey - 0.02, ez - 0.026), "white", seg=6, rings=4)
        bx, bz = 0.088 * sx, 0.968
        brow = tg.sphere(f"brow{sx}", (0.065, 0.02, 0.016), (bx, head_front_y(bx, bz) + 0.006, bz), "hair",
                         seg=10, rings=4, rot=(0, -8 * sx, 0))
        cx, cz = 0.128 * sx, 0.828
        cheek = tg.sphere(f"blush{sx}", (0.06, 0.016, 0.03), (cx, head_front_y(cx, cz) + 0.006, cz), "blush",
                          seg=10, rings=4, rot=(0, 0, 22 * sx))
        ear = tg.sphere(f"ear{sx}", (0.05, 0.045, 0.075), (0.2 * sx, 0.01, 0.89), "skin", seg=10, rings=6)
        parts += [eye, hl1, hl2, brow, cheek, ear]
    nose = tg.sphere("nose", (0.032, 0.022, 0.026), (0, head_front_y(0, 0.85) + 0.004, 0.85), "skin", seg=8, rings=4)
    mouth = tg.sphere("mouth", (0.05, 0.014, 0.02), (0, head_front_y(0, 0.808) + 0.005, 0.808), "mouth", seg=12, rings=4)
    tg.deform(mouth, lambda v: Vector((v.x, v.y, v.z + 6.0 * v.x * v.x)))  # smile
    parts += [nose, mouth]

    # Hair: back volume plus bangs swept to one side, all below the helmet rim.
    back = tg.sphere("hair_back", (0.425, 0.37, 0.27), (0, 0.04, 0.93), "hair", seg=16, rings=8)
    parts.append(back)
    for i, (x, ang, sz) in enumerate([(-0.11, 28, 0.13), (-0.035, 12, 0.14), (0.045, -6, 0.13), (0.12, -22, 0.11)]):
        z = 1.025
        lock = tg.sphere(f"bang{i}", (sz, 0.06, 0.075), (x, head_front_y(x, z) + 0.035, z - 0.005), "hair",
                         seg=10, rings=5, rot=(10, ang, ang * 0.6))
        parts.append(lock)
    for sx in (-1, 1):
        side = tg.sphere(f"sidelock{sx}", (0.06, 0.08, 0.15), (0.185 * sx, -0.03, 0.9), "hair", seg=10, rings=6,
                         rot=(0, 12 * sx, 0))
        parts.append(side)

    # Open-face helmet: dome cut by a plane tilted towards the back.
    dome = tg.sphere("helmet", (0.455, 0.43, 0.43), (0, 0.012, 0.935), "armor", seg=24, rings=14)
    bm = bmesh.new()
    bm.from_mesh(dome.data)
    plane_co = Vector((0, -0.2, 1.035)) - dome.location
    plane_no = Vector((0, 0.5, 1)).normalized()  # kept side: higher at the front, lower at the back
    geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
    bmesh.ops.bisect_plane(bm, geom=geom, plane_co=plane_co, plane_no=plane_no, clear_inner=True)
    # Gold rim: extrude the open edge outwards.
    boundary = [e for e in bm.edges if e.is_boundary]
    ret = bmesh.ops.extrude_edge_only(bm, edges=boundary)
    new_verts = [v for v in ret["geom"] if isinstance(v, bmesh.types.BMVert)]
    for v in new_verts:
        d = Vector((v.co.x, v.co.y, 0)).normalized()
        v.co += d * 0.022 + Vector((0, 0, -0.012))
    gold_index = 1
    dome.data.materials.append(tg.swatch("gold"))
    for f in [g for g in ret["geom"] if isinstance(g, bmesh.types.BMFace)]:
        f.material_index = gold_index
    bm.to_mesh(dome.data)
    bm.free()
    tg.add_solidify(dome, 0.016)
    tg.shade(dome, 60)
    crest = tg.sphere("crest_fin", (0.034, 0.36, 0.15), (0, 0.035, 1.14), "gold", seg=12, rings=6)
    parts += [dome, crest]
    # Plume sweeping back from the crest.
    for i, (y, z, rx, m) in enumerate([(0.10, 1.22, -30, "cream"), (0.19, 1.18, -48, "armor"), (0.25, 1.11, -66, "cream")]):
        plume = tg.sphere(f"plume{i}", (0.07, 0.2, 0.075), (0, y, z), m, seg=10, rings=5, rot=(rx, 0, 0))
        parts.append(plume)

    head_obj = tg.join(parts, "Head")
    tg.pivot(head_obj, (0, 0, 0.70))
    return head_obj


def build_sword():
    # Blade: diamond cross-section, tapering to a point. Built pointing +Z.
    L, w, t = 0.44, 0.058, 0.016
    rows = [(0.0, 1.0), (0.30, 0.95), (0.37, 0.75)]
    verts, faces = [], []
    for z, k in rows:
        verts += [(-w / 2 * k, 0, z), (0, -t / 2 * k, z), (w / 2 * k, 0, z), (0, t / 2 * k, z)]
    verts.append((0, 0, L))
    for r in range(len(rows) - 1):
        a, b = r * 4, (r + 1) * 4
        for i in range(4):
            faces.append((a + i, a + (i + 1) % 4, b + (i + 1) % 4, b + i))
    tip = len(verts) - 1
    last = (len(rows) - 1) * 4
    for i in range(4):
        faces.append((last + i, last + (i + 1) % 4, tip))
    faces.append((3, 2, 1, 0))
    blade = tg.from_pydata("blade", verts, faces, "steel", smooth=False)
    blade.location = (0, 0, 0.065)
    tg.apply_all_transforms(blade)
    fuller = tg.box("fuller", (0.012, t * 1.15, 0.24), (0, 0, 0.065 + 0.14), "gold")
    guard = tg.box("guard", (0.175, 0.04, 0.036), (0, 0, 0.055), "gold", bevel=0.012)
    gems = [tg.sphere(f"guard_end{s}", (0.04, 0.04, 0.04), (0.09 * s, 0, 0.055), "gold", seg=10, rings=6)
            for s in (-1, 1)]
    gem = tg.sphere("guard_gem", (0.03, 0.05, 0.03), (0, 0, 0.055), "armor", seg=8, rings=4)
    grip = tg.cylinder("grip", 0.018, 0.018, 0.1, (0, 0, -0.055), "armor_dark", verts=10)
    pommel = tg.sphere("pommel", (0.045, 0.045, 0.045), (0, 0, -0.07), "gold", seg=12, rings=6)
    sword = tg.join([blade, fuller, guard, *gems, gem, grip, pommel], "Sword")
    return sword


def build_arm(side: int):
    """side -1 = hero's right (-X, sword), +1 = left (+X, shield)."""
    sx = side
    sh = Vector((0.205 * sx, 0.0, 0.615))
    upper = tg.sphere("upper", (0.1, 0.1, 0.19), (0.228 * sx, 0, 0.535), "cream", seg=12, rings=8, rot=(0, -8 * sx, 0))
    fore = tg.sphere("fore", (0.108, 0.108, 0.13), (0.245 * sx, -0.025, 0.44), "armor", seg=12, rings=8)
    cuff = tg.torus("cuff", 0.05, 0.011, (0.247 * sx, -0.03, 0.395), "gold", seg=14, minor_seg=6)
    glove = tg.sphere("glove", (0.105, 0.1, 0.1), (0.25 * sx, -0.045, 0.355), "leather", seg=12, rings=8)
    arm = tg.join([upper, fore, cuff, glove], "ArmR" if side < 0 else "ArmL")
    if side > 0:
        disc = tg.lathe("shield", [(0.0, 0.03), (0.08, 0.026), (0.14, 0.016), (0.155, 0.0)], "armor", steps=24)
        rim = tg.torus("shield_rim", 0.152, 0.014, (0, 0, 0.004), "gold", seg=28, minor_seg=6)
        boss = tg.sphere("shield_boss", (0.07, 0.07, 0.04), (0, 0, 0.032), "gold", seg=12, rings=6)
        cross_v = tg.box("shield_cross_v", (0.035, 0.2, 0.012), (0, 0, 0.027), "cream", bevel=0.005)
        cross_h = tg.box("shield_cross_h", (0.2, 0.035, 0.012), (0, 0, 0.027), "cream", bevel=0.005)
        shield = tg.join([disc, rim, cross_v, cross_h, boss], "Shield")
        # Face outwards and a little to the front.
        shield.rotation_euler = (0, math.radians(90), math.radians(-38))
        shield.location = (0.33, -0.05, 0.43)
        tg.apply_all_transforms(shield)
        arm = tg.join([arm, shield], "ArmL")
    tg.pivot(arm, sh)
    return arm


def build_cape():
    cols, rows = 10, 6
    verts, faces = [], []
    for j in range(rows + 1):
        v = j / rows
        for i in range(cols + 1):
            u = i / cols * 2 - 1
            a = math.radians(78) * u
            r = 0.16 + 0.07 * v
            wave = 0.018 * math.sin(u * math.pi * 2.0) * v
            verts.append((r * math.sin(a), 0.03 + r * math.cos(a) + wave, 0.665 - 0.37 * v))
    for j in range(rows):
        for i in range(cols):
            a = j * (cols + 1) + i
            faces.append((a, a + 1, a + cols + 2, a + cols + 1))
    cape = tg.from_pydata("Cape", verts, faces, "cape")
    tg.add_solidify(cape, 0.014, inner_mat="cream")
    tg.add_subsurf(cape, 1)
    tg.shade(cape, 70)
    collar = tg.torus("collar", 0.135, 0.02, (0, 0.025, 0.665), "gold", seg=20, minor_seg=6, scale=(1, 0.8, 1))
    tg.deform(collar, lambda v: Vector((v.x, max(v.y, -0.04), v.z)))
    cape = tg.join([cape, collar], "Cape")
    tg.pivot(cape, (0, 0.06, 0.665))
    return cape


def idle(body, head, arm_l, arm_r, cape) -> None:
    tg.make_track("idle", {
        body: [(0, {}), (24, {"scale": (1.0, 1.0, 1.025)}), (48, {})],
        head: [(0, {}), (24, {"rot": (-4, 0, 3)}), (48, {})],
        arm_r: [(0, {}), (24, {"rot": (-5, 0, 0)}), (48, {})],
        arm_l: [(0, {}), (24, {"rot": (4, 0, -2)}), (48, {})],
        cape: [(0, {"rot": (2, 0, 0)}), (16, {"rot": (10, 0, 2)}), (32, {"rot": (5, 0, -2)}), (48, {"rot": (2, 0, 0)})],
    }, 48)


def walk(body, head, arm_l, arm_r, cape, leg_l, leg_r) -> None:
    """One stride cycle (16 frames = 0.67 s); the game moves the hero ~3 m/s."""
    swing = 26
    tg.make_track("walk", {
        leg_l: [(0, {"rot": (swing, 0, 0)}), (8, {"rot": (-swing, 0, 0)}), (16, {"rot": (swing, 0, 0)})],
        leg_r: [(0, {"rot": (-swing, 0, 0)}), (8, {"rot": (swing, 0, 0)}), (16, {"rot": (-swing, 0, 0)})],
        arm_l: [(0, {"rot": (-22, 0, 0)}), (8, {"rot": (22, 0, 0)}), (16, {"rot": (-22, 0, 0)})],
        arm_r: [(0, {"rot": (12, 0, 0)}), (8, {"rot": (-12, 0, 0)}), (16, {"rot": (12, 0, 0)})],
        body: [(0, {"rot": (5, 0, 0)}), (4, {"rot": (5, 0, 2), "loc": (0, 0, 0.028)}), (8, {"rot": (5, 0, 0)}),
               (12, {"rot": (5, 0, -2), "loc": (0, 0, 0.028)}), (16, {"rot": (5, 0, 0)})],
        head: [(0, {}), (4, {"rot": (-3, 0, 0)}), (8, {}), (12, {"rot": (-3, 0, 0)}), (16, {})],
        cape: [(0, {"rot": (20, 0, 0)}), (4, {"rot": (26, 0, 3)}), (8, {"rot": (20, 0, 0)}),
               (12, {"rot": (26, 0, -3)}), (16, {"rot": (20, 0, 0)})],
    }, 16)


def build() -> dict:
    root = tg.empty("Hero")
    leg_r, leg_l = build_legs()
    body = build_body()
    head = build_head()
    arm_l = build_arm(1)
    arm_r = build_arm(-1)
    sword = build_sword()
    # Sword in the right hand: blade up, leaning out and slightly forward.
    sword.rotation_euler = (math.radians(12), math.radians(-14), 0)
    sword.location = (-0.252, -0.05, 0.355)
    cape = build_cape()
    for part in (leg_l, leg_r, body):
        tg.parent(part, root)
    for part in (head, arm_l, arm_r, cape):
        tg.parent(part, body)
    tg.parent(sword, arm_r)
    idle(body, head, arm_l, arm_r, cape)
    walk(body, head, arm_l, arm_r, cape, leg_l, leg_r)
    return tg.finish_asset("hero_knight", root, ao_distance=0.12, ao_strength=0.7)

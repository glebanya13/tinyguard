"""Archer tower (stone keep with a swivelling crossbow) and its arrow.

tower_archer.glb: Tower -> Base, Turret -> Bow, Flag. The turret faces -Y
(Godot +Z); the game rotates Turret around Y to aim. Animation: attack (Bow).
arrow.glb: points +Y (Godot -Z) so Node3D.look_at() aims it.
"""
import math
import random

import bpy
from mathutils import Vector

import tg_common as tg

TOP = 0.88  # height of the parapet floor


def build_base(rng: random.Random):
    parts = []
    body = tg.lathe("keep", [(0.41, 0.0), (0.39, 0.07), (0.345, 0.2), (0.325, 0.62), (0.335, 0.74),
                             (0.37, 0.8), (0.37, 0.8)], "stone", steps=14)
    tg.shade(body, 30)
    parts.append(body)
    # Hand-placed look: stones protruding from the wall.
    for i in range(14):
        a = rng.uniform(0, 2 * math.pi)
        z = rng.uniform(0.12, 0.7)
        if abs(math.atan2(math.sin(a + math.pi / 2), math.cos(a + math.pi / 2))) < 0.5 and z < 0.4:
            continue  # keep the door clear
        r = 0.345 - (z - 0.2) * 0.03 if z > 0.2 else 0.36
        w = rng.uniform(0.09, 0.15)
        st = tg.box(f"stone{i}", (w, 0.05, rng.uniform(0.05, 0.08)), (r * math.cos(a), r * math.sin(a), z),
                    rng.choice(["stone_light", "stone_dark", "stone_light"]), bevel=0.012, bevel_seg=1,
                    rot=(0, 0, math.degrees(a) + 90))
        parts.append(st)
    # Door with a rounded arch, frame and gold studs.
    frame = tg.box("door_frame", (0.2, 0.05, 0.25), (0, -0.335, 0.125), "stone_light", bevel=0.015, bevel_seg=1)
    arch_f = tg.cylinder("arch_frame", 0.1, 0.1, 0.05, (0, -0.31, 0.25), "stone_light", verts=14, rot=(90, 0, 0))
    door = tg.box("door", (0.15, 0.05, 0.22), (0, -0.35, 0.11), "wood_dark", bevel=0.008, bevel_seg=1)
    arch = tg.cylinder("arch", 0.075, 0.075, 0.05, (0, -0.325, 0.22), "wood_dark", verts=14, rot=(90, 0, 0))
    knob = tg.sphere("knob", (0.025, 0.02, 0.025), (0.04, -0.378, 0.13), "gold", seg=8, rings=4)
    parts += [frame, arch_f, door, arch, knob]
    for a in (60, 180, 300):
        rad = math.radians(a - 90)
        win = tg.box(f"window{a}", (0.04, 0.05, 0.12), (0.33 * math.cos(rad), 0.33 * math.sin(rad), 0.52), "window",
                     bevel=0.01, bevel_seg=1, rot=(0, 0, a))
        parts.append(win)
    plinth = tg.cylinder("plinth", 0.44, 0.415, 0.07, (0, 0, 0.0), "stone_dark", verts=14)
    tg.shade(plinth, 30)
    parts.append(plinth)
    # Royal banner on the front wall under the parapet.
    banner = tg.box("banner", (0.2, 0.02, 0.3), (0, -0.345, 0.6), "cape", bevel=0.006, bevel_seg=1)
    tg.deform(banner, lambda c: Vector((c.x, c.y, c.z - (0.06 - abs(c.x) * 0.6 if c.z < -0.14 else 0))))
    b_trim = tg.box("banner_trim", (0.22, 0.024, 0.03), (0, -0.347, 0.75), "gold", bevel=0.008, bevel_seg=1)
    b_emblem = tg.sphere("banner_emblem", (0.08, 0.02, 0.1), (0, -0.358, 0.6), "gold", seg=8, rings=4)
    parts += [banner, b_trim, b_emblem]
    ledge = tg.cylinder("ledge", 0.4, 0.43, 0.06, (0, 0, 0.8), "stone_light", verts=16)
    floor = tg.cylinder("floor", 0.36, 0.36, 0.02, (0, 0, 0.86), "wood", verts=16)
    tg.shade(ledge, 30)
    parts += [ledge, floor]
    for i in range(8):
        a = 2 * math.pi * (i + 0.5) / 8
        merlon = tg.box(f"merlon{i}", (0.15, 0.09, 0.13), (0.37 * math.cos(a), 0.37 * math.sin(a), 0.92),
                        "stone", bevel=0.018, bevel_seg=2, rot=(0, 0, math.degrees(a) + 90))
        parts.append(merlon)
    for i in range(12):
        a = 2 * math.pi * i / 12
        corbel = tg.box(f"corbel{i}", (0.07, 0.07, 0.06), (0.36 * math.cos(a), 0.36 * math.sin(a), 0.77),
                        "stone_dark", bevel=0.01, bevel_seg=1, rot=(0, 0, math.degrees(a)))
        parts.append(corbel)
    return tg.join(parts, "Base")


def build_turret():
    swivel = tg.cylinder("swivel", 0.11, 0.1, 0.06, (0, 0, TOP), "wood_dark", verts=14)
    ring = tg.torus("swivel_ring", 0.105, 0.012, (0, 0, TOP + 0.03), "gold", seg=16, minor_seg=6)
    post = tg.cylinder("post", 0.04, 0.035, 0.1, (0, 0, TOP + 0.05), "wood", verts=10)
    stock = tg.box("stock", (0.07, 0.42, 0.055), (0, -0.04, TOP + 0.16), "wood", bevel=0.015, bevel_seg=2,
                   rot=(-6, 0, 0))
    rail = tg.box("rail", (0.025, 0.36, 0.02), (0, -0.05, TOP + 0.195), "wood_dark", bevel=0.006, bevel_seg=1,
                  rot=(-6, 0, 0))
    bolt = tg.cylinder("bolt", 0.009, 0.009, 0.3, (0, 0.04, TOP + 0.215), "wood_light", verts=6, rot=(90, 0, 0))
    bolt_tip = tg.cylinder("bolt_tip", 0.022, 0.0, 0.05, (0, -0.26, TOP + 0.215), "steel", verts=6, rot=(90, 0, 0))
    plate = tg.box("plate", (0.1, 0.1, 0.03), (0, 0.15, TOP + 0.13), "gold", bevel=0.01, bevel_seg=1)
    turret = tg.join([swivel, ring, post, stock, rail, bolt, bolt_tip, plate], "Turret")
    tg.pivot(turret, (0, 0, TOP))

    # Bow: curved limbs with gold tips and a string, at the front of the stock.
    limb = tg.box("limb", (0.5, 0.035, 0.03), (0, 0, 0), "wood_dark", bevel=0.01, bevel_seg=1)
    tg.deform(limb, lambda c: Vector((c.x, c.y + 0.55 * c.x * c.x, c.z * (1 - 1.2 * abs(c.x)))))
    tg.add_subsurf(limb, 1)
    tg.shade(limb, 60)
    tips = [tg.sphere(f"tip{s}", (0.04, 0.04, 0.04), (0.25 * s, 0.035, 0), "gold", seg=10, rings=6) for s in (-1, 1)]
    string = tg.box("string", (0.5, 0.008, 0.008), (0, 0.04, 0), "string")
    band = tg.box("bow_band", (0.06, 0.05, 0.045), (0, 0.0, 0), "gold", bevel=0.01, bevel_seg=1)
    bow = tg.join([limb, *tips, string, band], "Bow")
    bow.location = (0, -0.22, TOP + 0.17)
    bow.rotation_euler = (math.radians(-6), 0, 0)
    tg.apply_all_transforms(bow)
    tg.pivot(bow, (0, -0.22, TOP + 0.17))
    # Enlarge the crossbow so it reads at game distance (scale about the swivel).
    s = 1.35
    from mathutils import Matrix
    for obj in (turret, bow):
        obj.data.transform(Matrix.Scale(s, 4))
    bow.location = turret.location + (bow.location - turret.location) * s
    return turret, bow


def build_flag():
    x, y = 0.24, 0.24
    pole = tg.cylinder("pole", 0.016, 0.013, 0.78, (x, y, TOP), "wood_dark", verts=8)
    ball = tg.sphere("pole_ball", (0.05, 0.05, 0.05), (x, y, TOP + 0.8), "gold", seg=10, rings=6)
    # Swallow-tailed pennant, slightly waved.
    pts, faces = [], []
    cols = 6
    for i in range(cols + 1):
        u = i / cols
        h = 0.2 * (1 - 0.35 * u)
        wave = 0.03 * math.sin(u * math.pi * 1.6)
        notch = 0.07 if i == cols else 0.0
        pts += [(x - 0.01 - 0.32 * u, y + wave, TOP + 0.75 - 0.0 * u), (x - 0.01 - 0.32 * u + notch, y + wave, TOP + 0.75 - h)]
    for i in range(cols):
        a = i * 2
        faces.append((a, a + 2, a + 3, a + 1))
    cloth = tg.from_pydata("pennant", pts, faces, "cape")
    tg.add_solidify(cloth, 0.012, inner_mat="cape")
    trim = tg.box("pennant_trim", (0.025, 0.02, 0.21), (x - 0.02, y, TOP + 0.645), "gold")
    return tg.join([pole, ball, cloth, trim], "Flag")


def build_levels():
    """Decorations shown from level 2 and level 3 (hidden at level 1 by the game)."""
    lv2 = []
    for z in (0.3, 0.62):
        r = 0.345 - (z - 0.2) * 0.03
        lv2.append(tg.torus(f"lv2_band{z}", r + 0.012, 0.018, (0, 0, z), "gold", seg=24, minor_seg=6))
    for a in (90, 270):
        rad = math.radians(a - 90)
        x, y = 0.352 * math.cos(rad), 0.352 * math.sin(rad)
        ban = tg.box(f"lv2_banner{a}", (0.16, 0.02, 0.26), (x, y, 0.56), "cape", bevel=0.006, bevel_seg=1,
                     rot=(0, 0, a))
        tg.deform(ban, lambda c: Vector((c.x, c.y, c.z - (0.05 - abs(c.x if a in (0, 180) else c.y) * 0.6
                                                        if c.z < -0.12 else 0))))
        lv2.append(ban)
        lv2.append(tg.sphere(f"lv2_emblem{a}", (0.06, 0.06, 0.08), (x * 1.04, y * 1.04, 0.57), "gold", seg=8, rings=4,
                             rot=(0, 0, a)))
    lv3 = [tg.torus("lv3_crown", 0.42, 0.022, (0, 0, 0.99), "gold", seg=28, minor_seg=6)]
    for i in range(8):
        a = 2 * math.pi * (i + 0.5) / 8
        lv3.append(tg.cylinder(f"lv3_spike{i}", 0.035, 0.0, 0.11, (0.37 * math.cos(a), 0.37 * math.sin(a), 0.985),
                               "gold", verts=6))
    lv3.append(tg.sphere("lv3_gem", (0.09, 0.09, 0.12), (0.24, 0.24, TOP + 0.92), "portal_glow", seg=10, rings=6))
    return tg.join(lv2, "Lv2"), tg.join(lv3, "Lv3")


def attack(bow) -> None:
    tg.make_track("attack", {
        bow: [(0, {}), (2, {"loc": (0, 0.07, 0), "scale": (1.12, 1, 1)}), (5, {"loc": (0, -0.025, 0), "scale": (0.94, 1, 1)}),
              (9, {"loc": (0, 0.008, 0)}), (12, {})],
    }, 12)


def build_arrow():
    shaft = tg.cylinder("shaft", 0.009, 0.009, 0.3, (0, -0.15, 0), "wood_light", verts=6, rot=(-90, 0, 0))
    head = tg.cylinder("head", 0.024, 0.0, 0.07, (0, 0.15, 0), "steel", verts=6, rot=(-90, 0, 0))
    fl = []
    for i, m in enumerate(("white", "armor", "white")):
        a = i * 120
        f = tg.box(f"fletch{i}", (0.004, 0.07, 0.035), (0, -0.12, 0.022), m, rot=(0, 0, 0))
        f.rotation_euler = (0, math.radians(a), 0)
        tg.apply_all_transforms(f)
        fl.append(f)
    arrow = tg.join([shaft, head, *fl], "Arrow")
    return arrow


def build_slot_ring(rng):
    """Ring of cut stones framing a build slot (inner disc is a Godot mesh). Baked into
    the level terrain by build_terrain.py; at the origin its mesh is offset, move the object."""
    parts = []
    n = 10
    for i in range(n):
        a = 2 * math.pi * i / n
        st = tg.box(f"ring{i}", (0.24, 0.1, 0.07), (0.5 * math.cos(a), 0.5 * math.sin(a), 0.035),
                    rng.choice(["stone_light", "stone", "stone_light"]), bevel=0.02, bevel_seg=2,
                    rot=(0, 0, math.degrees(a) + 90 + rng.uniform(-6, 6)))
        parts.append(st)
    for i in range(3):
        a = rng.uniform(0, 2 * math.pi)
        parts.append(tg.box(f"chip{i}", (0.06, 0.05, 0.03), (0.62 * math.cos(a), 0.62 * math.sin(a), 0.015),
                            "stone_dark", bevel=0.01, bevel_seg=1, rot=(0, 0, rng.uniform(0, 90))))
    return tg.join(parts, "SlotRing")


def build_cannon_turret():
    """Iron cannon on a wooden carriage. Turret yaws; Gun recoils."""
    swivel = tg.cylinder("swivel", 0.15, 0.14, 0.06, (0, 0, TOP), "wood_dark", verts=14)
    ring = tg.torus("swivel_ring", 0.145, 0.014, (0, 0, TOP + 0.03), "gold", seg=18, minor_seg=6)
    cheeks = [tg.box(f"cheek{s}", (0.04, 0.26, 0.16), (0.11 * s, 0.0, TOP + 0.13), "wood", bevel=0.015, bevel_seg=1)
              for s in (-1, 1)]
    wheels = [tg.cylinder(f"wheel{s}", 0.075, 0.075, 0.035, (0.15 * s, 0.05, TOP + 0.08), "wood_dark", verts=12,
                          rot=(0, 90, 0)) for s in (-1, 1)]
    hubs = [tg.sphere(f"hub{s}", (0.04, 0.04, 0.04), (0.17 * s, 0.05, TOP + 0.08), "gold", seg=8, rings=4)
            for s in (-1, 1)]
    turret = tg.join([swivel, ring, *cheeks, *wheels, *hubs], "Turret")
    tg.pivot(turret, (0, 0, TOP))
    barrel = tg.lathe("barrel", [(0.085, -0.12), (0.095, -0.08), (0.075, 0.0), (0.065, 0.2), (0.075, 0.24),
                                 (0.07, 0.27)], "iron", steps=14)
    barrel.rotation_euler = (math.radians(-90 + 10), 0, 0)  # points -Y, tilted up
    tg.apply_all_transforms(barrel)
    bands = [tg.torus(f"band{i}", 0.08, 0.012, (0, -y, 0.012 * i), "gold", seg=16, minor_seg=5,
                      rot=(90 - 10, 0, 0)) for i, y in enumerate((0.0, 0.2))]
    breech = tg.sphere("breech", (0.15, 0.15, 0.15), (0, 0.12, -0.02), "iron_dark", seg=12, rings=6)
    muzzle = tg.torus("muzzle", 0.072, 0.018, (0, -0.27, 0.05), "iron_dark", seg=16, minor_seg=5, rot=(80, 0, 0))
    gun = tg.join([barrel, *bands, breech, muzzle], "Gun")
    gun.location = (0, 0, TOP + 0.2)
    tg.apply_all_transforms(gun)
    tg.pivot(gun, (0, 0, TOP + 0.2))
    return turret, gun


def build_frost_turret():
    """Stone pedestal holding a floating ice crystal. Crystal pulses on attack."""
    pedestal = tg.lathe("pedestal", [(0.2, TOP), (0.16, TOP + 0.05), (0.1, TOP + 0.12), (0.14, TOP + 0.2),
                                     (0.17, TOP + 0.22)], "stone_light", steps=12)
    prongs = []
    for i in range(4):
        a = math.pi / 2 * i + math.pi / 4
        pr = tg.cylinder(f"prong{i}", 0.03, 0.012, 0.22, (0.15 * math.cos(a), 0.15 * math.sin(a), TOP + 0.2),
                         "gold", verts=6, rot=(math.degrees(-0.4 * math.sin(a)), math.degrees(0.4 * math.cos(a)), 0))
        prongs.append(pr)
    turret = tg.join([pedestal, *prongs], "Turret")
    tg.pivot(turret, (0, 0, TOP))
    # Crystal: two hexagonal pyramids, plus small shards around.
    def bipyramid(name, r, h_top, h_bot, loc, mat):
        verts = [(0, 0, h_top), (0, 0, -h_bot)]
        for i in range(6):
            a = math.pi / 3 * i
            verts.append((r * math.cos(a), r * math.sin(a), 0))
        faces = []
        for i in range(6):
            j = (i + 1) % 6
            faces.append((0, 2 + i, 2 + j))
            faces.append((1, 2 + j, 2 + i))
        obj = tg.from_pydata(name, [(x + loc[0], y + loc[1], z + loc[2]) for x, y, z in verts], faces, mat, smooth=False)
        return obj
    core = bipyramid("core", 0.13, 0.32, 0.16, (0, 0, TOP + 0.45), "ice")
    inner = bipyramid("inner", 0.07, 0.2, 0.1, (0, -0.02, TOP + 0.47), "ice_light")
    shards = [bipyramid(f"shard{i}", 0.04, 0.1, 0.05,
                        (0.21 * math.cos(a), 0.21 * math.sin(a), TOP + 0.38 + 0.05 * (i % 2)), "ice_dark")
              for i, a in enumerate([0.3, 2.4, 4.4])]
    crystal = tg.join([core, inner, *shards], "Crystal")
    tg.pivot(crystal, (0, 0, TOP + 0.45))
    return turret, crystal


def build_lightning_turret():
    """Iron mast wound with gold coils; a glowing orb floats on top and flares on attack."""
    mast = tg.cylinder("mast", 0.07, 0.05, 0.42, (0, 0, TOP), "iron", verts=10)
    plate = tg.cylinder("plate", 0.22, 0.18, 0.06, (0, 0, TOP), "iron_dark", verts=14)
    coils = [tg.torus(f"coil{i}", 0.1 - 0.012 * i, 0.022, (0, 0, TOP + 0.1 + 0.1 * i), "gold", seg=16, minor_seg=6)
             for i in range(3)]
    rods = [tg.cylinder(f"rod{i}", 0.018, 0.01, 0.2, (0.16 * math.cos(a), 0.16 * math.sin(a), TOP + 0.05), "steel",
                        verts=6, rot=(math.degrees(-0.5 * math.sin(a)), math.degrees(0.5 * math.cos(a)), 0))
            for i, a in enumerate([0.4, 2.5, 4.6])]
    turret = tg.join([mast, plate, *coils, *rods], "Turret")
    tg.pivot(turret, (0, 0, TOP))
    orb = tg.sphere("orb", (0.2, 0.2, 0.2), (0, 0, TOP + 0.58), "portal_glow", seg=16, rings=8)
    core = tg.sphere("core", (0.1, 0.1, 0.1), (0, -0.05, TOP + 0.6), "white", seg=10, rings=5)
    ring = tg.torus("halo", 0.16, 0.012, (0, 0, TOP + 0.58), "ice_light", seg=20, minor_seg=4, rot=(70, 0, 20))
    part = tg.join([orb, core, ring], "Orb")
    tg.pivot(part, (0, 0, TOP + 0.58))
    return turret, part


def build_cannonball():
    ball = tg.sphere("ball", (0.16, 0.16, 0.16), (0, 0, 0), "iron_dark", seg=12, rings=6)
    shine = tg.sphere("shine", (0.05, 0.03, 0.04), (-0.04, -0.06, 0.04), "steel", seg=6, rings=3)
    return tg.join([ball, shine], "Ball")


def build_frost_shard():
    verts = [(0, 0.16, 0), (0, -0.08, 0)]
    for i in range(6):
        a = math.pi / 3 * i
        verts.append((0.04 * math.cos(a), 0.0, 0.04 * math.sin(a)))
    faces = []
    for i in range(6):
        j = (i + 1) % 6
        faces.append((0, 2 + j, 2 + i))
        faces.append((1, 2 + i, 2 + j))
    shard = tg.from_pydata("Shard", verts, faces, "ice", smooth=False)
    glow = tg.sphere("glow", (0.06, 0.12, 0.06), (0, 0.03, 0), "ice_light", seg=8, rings=4)
    return tg.join([shard, glow], "Shard")


def tower_track(kind, part) -> None:
    if kind == "archer":
        attack(part)
    elif kind == "cannon":
        tg.make_track("attack", {
            part: [(0, {}), (2, {"loc": (0, 0.12, -0.02), "rot": (8, 0, 0)}), (8, {"loc": (0, -0.02, 0)}),
                   (12, {})],
        }, 12)
    else:
        tg.make_track("attack", {
            part: [(0, {}), (3, {"scale": (1.35, 1.35, 1.35), "rot": (0, 0, 40)}), (8, {"scale": (0.92, 0.92, 0.92),
                   "rot": (0, 0, 70)}), (12, {"rot": (0, 0, 90)})],
        }, 12)


def build_tower_kind(kind: str, rng) -> dict:
    root = tg.empty("Tower")
    base = build_base(rng)
    flag = build_flag()
    if kind == "archer":
        turret, part = build_turret()
    elif kind == "cannon":
        turret, part = build_cannon_turret()
    elif kind == "lightning":
        turret, part = build_lightning_turret()
    else:
        turret, part = build_frost_turret()
    base = tg.join([base, flag], "Base")  # static parts share one mesh (one draw call)
    lv2, lv3 = build_levels()
    collider = tg.collider_cylinder("TowerBody", 0.43, 1.0)
    # Upgrade decorations are baked into body variants (Base2 = Base + Lv2, Base3 = Base + Lv2 +
    # Lv3); the game swaps the mesh of "Base" per level, so a tower is one body mesh at any level.
    base2 = tg.join([tg.duplicate(base, "Base2_src"), tg.duplicate(lv2, "Lv2_src")], "Base2")
    base3 = tg.join([tg.duplicate(base, "Base3_src"), lv2, lv3], "Base3")
    for obj in (collider, base, base2, base3, turret):
        tg.parent(obj, root)
    tg.parent(part, turret)
    tower_track(kind, part)
    return tg.finish_asset(f"tower_{kind}", root, ao_distance=0.25, ao_strength=0.75)


def _clear() -> None:
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)


def build() -> list:
    out = []
    for kind in ("archer", "cannon", "frost", "lightning"):
        _clear()
        out.append(build_tower_kind(kind, random.Random(3)))
    for name, fn, ao in (("arrow", build_arrow, 0.05), ("cannonball", build_cannonball, 0.05),
                         ("frost_shard", build_frost_shard, 0.05)):
        _clear()
        out.append(tg.finish_asset(name, fn(), ao_distance=ao, ao_strength=0.4, ground=False))
    return out

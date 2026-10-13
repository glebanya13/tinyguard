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
    """Ring of cut stones framing a build slot (inner disc is a Godot mesh)."""
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


def build() -> list:
    rng = random.Random(3)
    root = tg.empty("Tower")
    base = build_base(rng)
    turret, bow = build_turret()
    flag = build_flag()
    base = tg.join([base, flag], "Base")  # static parts share one mesh (one draw call)
    tg.parent(base, root)
    tg.parent(turret, root)
    tg.parent(bow, turret)
    attack(bow)
    tower = tg.finish_asset("tower_archer", root, ao_distance=0.25, ao_strength=0.75)
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    arrow = build_arrow()
    out = [tower, tg.finish_asset("arrow", arrow, ao_distance=0.05, ao_strength=0.4, ground=False)]
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    out.append(tg.finish_asset("slot_ring", build_slot_ring(rng), ao_distance=0.08, ao_strength=0.6))
    return out

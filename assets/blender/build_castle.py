"""Castle (the base the player defends) and the enemy spawn portal.

castle.glb: gate faces -Y (Godot +Z); the level rotates it towards the path.
spawn_portal.glb: opening faces -Y as well.
"""
import math
import random

import bpy
from mathutils import Vector

import tg_common as tg


def wall_stones(rng, parts, center, half_x, y_face, z_range, count, skip=None):
    """Protruding stones on a flat wall facing -Y (y_face is the wall surface)."""
    for i in range(count):
        x = center + rng.uniform(-half_x, half_x)
        z = rng.uniform(*z_range)
        if skip and skip(x, z):
            continue
        parts.append(tg.box(f"wst{len(parts)}", (rng.uniform(0.1, 0.17), 0.04, rng.uniform(0.05, 0.08)),
                            (x, y_face - 0.012, z), rng.choice(["stone_light", "stone_dark", "stone_light"]),
                            bevel=0.012, bevel_seg=1))


def round_tower(name, x, y, rng, s=1.0):
    """Round corner tower with a conical roof; s scales it uniformly."""
    obj = _round_tower(name, rng)
    obj.scale = (s, s, s)
    obj.location = (x, y, 0)
    tg.apply_all_transforms(obj)
    return obj


def _round_tower(name, rng):
    parts = []
    body = tg.lathe(name, [(0.34, 0.0), (0.32, 0.1), (0.3, 1.2), (0.33, 1.27), (0.33, 1.32)], "stone", steps=14)
    tg.shade(body, 30)
    parts.append(body)
    for i in range(6):
        a = rng.uniform(0, 2 * math.pi)
        z = rng.uniform(0.15, 1.1)
        parts.append(tg.box(f"{name}_st{i}", (0.11, 0.04, 0.06), (0.305 * math.cos(a), 0.305 * math.sin(a), z),
                            rng.choice(["stone_light", "stone_dark"]), bevel=0.01, bevel_seg=1,
                            rot=(0, 0, math.degrees(a) + 90)))
    for a in (-90, 30, 150):
        rad = math.radians(a)
        parts.append(tg.box(f"{name}_win{a}", (0.05, 0.05, 0.13), (0.3 * math.cos(rad), 0.3 * math.sin(rad), 0.85),
                            "window", bevel=0.012, bevel_seg=1, rot=(0, 0, a + 90)))
    ring = tg.torus(f"{name}_ring", 0.33, 0.025, (0, 0, 1.3), "stone_light", seg=20, minor_seg=6)
    roof = tg.lathe(f"{name}_roof", [(0.42, 1.3), (0.385, 1.36), (0.33, 1.46), (0.25, 1.6), (0.15, 1.77),
                                     (0.06, 1.92), (0.015, 1.98)], "roof", steps=16)
    tg.shade(roof, 60)
    trim = tg.torus(f"{name}_trim", 0.41, 0.022, (0, 0, 1.31), "gold", seg=24, minor_seg=6)
    finial = tg.sphere(f"{name}_fin", (0.07, 0.07, 0.07), (0, 0, 2.0), "gold", seg=10, rings=6)
    spike = tg.cylinder(f"{name}_spike", 0.012, 0.0, 0.12, (0, 0, 2.03), "gold", verts=6)
    flag = tg.from_pydata(f"{name}_flag", [(0.0, 0, 2.06), (0.24, -0.02, 2.02), (0.0, 0, 1.94)], [(0, 1, 2)], "cape")
    tg.add_solidify(flag, 0.01)
    parts += [ring, roof, trim, finial, spike, flag]
    return tg.join(parts, name)


def build_castle(rng):
    parts = []
    plinth = tg.box("plinth", (2.05, 1.95, 0.1), (0, 0.13, 0.05), "stone_dark", bevel=0.04, bevel_seg=2)
    parts.append(plinth)
    # Keep with a pyramid roof.
    keep = tg.box("keep", (1.0, 0.9, 1.15), (0, 0.35, 0.1 + 0.575), "stone", bevel=0.03, bevel_seg=2)
    parts.append(keep)
    wall_stones(rng, parts, 0, 0.42, -0.1, (0.95, 1.2), 5)
    for sx in (-1, 1):
        win = tg.box(f"keep_win{sx}", (0.13, 0.05, 0.2), (0.24 * sx, -0.105, 1.0), "window", bevel=0.02, bevel_seg=2)
        sill = tg.box(f"keep_sill{sx}", (0.17, 0.06, 0.03), (0.24 * sx, -0.12, 0.89), "gold", bevel=0.008, bevel_seg=1)
        arch = tg.cylinder(f"keep_arch{sx}", 0.065, 0.065, 0.05, (0.24 * sx, -0.08, 1.1), "window", verts=12,
                           rot=(90, 0, 0))
        parts += [win, sill, arch]
    # The level camera sees the castle from its right (+X) side and back (+Y):
    # windows, banners and stones on every face of the keep.
    for (px, py, rz) in ((0.505, 0.35, 90), (-0.505, 0.35, -90), (0, 0.805, 180)):
        for off in (-0.22, 0.22):
            dx, dy = (0, off) if rz in (90, -90) else (off, 0)
            parts.append(tg.box(f"kw{px}{py}{off}", (0.12, 0.05, 0.19), (px + dx, py + dy, 1.0), "window",
                                bevel=0.02, bevel_seg=2, rot=(0, 0, rz)))
            parts.append(tg.box(f"ks{px}{py}{off}", (0.16, 0.06, 0.03), (px + dx * 1.0, py + dy, 0.89), "gold",
                                bevel=0.008, bevel_seg=1, rot=(0, 0, rz)))
    for (px, py, rz) in ((0.512, 0.35, 90), (0, 0.812, 180)):
        ban = tg.box(f"keep_banner{rz}", (0.2, 0.02, 0.36), (px, py, 0.62), "cape", bevel=0.006, bevel_seg=1,
                     rot=(0, 0, rz))
        tg.deform(ban, lambda c: Vector((c.x, c.y, c.z - (0.06 - abs(c.x if rz == 180 else c.y) * 0.6
                                                        if c.z < -0.16 else 0))))
        parts.append(ban)
        parts.append(tg.box(f"keep_banner_t{rz}", (0.23, 0.03, 0.03), (px, py, 0.8), "gold", bevel=0.008,
                            bevel_seg=1, rot=(0, 0, rz)))
        parts.append(tg.sphere(f"keep_banner_e{rz}", (0.08, 0.02, 0.1), (px, py, 0.64), "gold", seg=8, rings=4,
                               rot=(0, 0, rz)))
    # Side walls joining the front towers to the rear towers.
    for sx in (-1, 1):
        sw = tg.box(f"side_wall{sx}", (0.24, 1.2, 0.62), (0.74 * sx, 0.18, 0.1 + 0.31), "stone", bevel=0.025,
                    bevel_seg=2)
        parts.append(sw)
        for i in range(4):
            parts.append(tg.box(f"side_merlon{sx}{i}", (0.24, 0.13, 0.12), (0.74 * sx, -0.22 + i * 0.27, 0.78),
                                "stone", bevel=0.02, bevel_seg=1))
        for i in range(5):
            y = rng.uniform(-0.3, 0.7)
            z = rng.uniform(0.2, 0.62)
            parts.append(tg.box(f"side_st{sx}{i}", (0.04, rng.uniform(0.1, 0.16), rng.uniform(0.05, 0.08)),
                                (0.86 * sx, y, z), rng.choice(["stone_light", "stone_dark"]), bevel=0.012,
                                bevel_seg=1))
    roof = tg.cylinder("keep_roof", 0.78, 0.0, 0.72, (0, 0.35, 1.25), "roof", verts=4, rot=(0, 0, 45), smooth=False)
    roof_band = tg.box("keep_roof_band", (1.08, 0.98, 0.06), (0, 0.35, 1.26), "roof_dark", bevel=0.02, bevel_seg=1)
    keep_fin = tg.sphere("keep_fin", (0.1, 0.1, 0.1), (0, 0.35, 1.99), "gold", seg=12, rings=6)
    keep_spike = tg.cylinder("keep_spike", 0.015, 0.0, 0.16, (0, 0.35, 2.03), "gold", verts=6)
    parts += [roof, roof_band, keep_fin, keep_spike]
    # Front curtain wall with crenellations, gate and banners.
    wall = tg.box("wall", (1.2, 0.32, 0.78), (0, -0.5, 0.1 + 0.39), "stone", bevel=0.025, bevel_seg=2)
    parts.append(wall)
    gate_skip = lambda x, z: abs(x) < 0.3 and z < 0.65  # noqa: E731
    wall_stones(rng, parts, 0, 0.55, -0.66, (0.15, 0.8), 12, skip=gate_skip)
    for i in range(5):
        x = -0.48 + i * 0.24
        parts.append(tg.box(f"wall_merlon{i}", (0.14, 0.32, 0.13), (x, -0.5, 0.94), "stone", bevel=0.02, bevel_seg=1))
    gate_frame = tg.box("gate_frame", (0.5, 0.06, 0.42), (0, -0.665, 0.1 + 0.21), "stone_light", bevel=0.02, bevel_seg=1)
    gate_arch_f = tg.cylinder("gate_arch_f", 0.25, 0.25, 0.06, (0, -0.635, 0.52), "stone_light", verts=16,
                              rot=(90, 0, 0))
    door = tg.box("gate_door", (0.4, 0.06, 0.4), (0, -0.68, 0.1 + 0.2), "wood_dark", bevel=0.01, bevel_seg=1)
    door_arch = tg.cylinder("gate_door_arch", 0.2, 0.2, 0.06, (0, -0.65, 0.5), "wood_dark", verts=16, rot=(90, 0, 0))
    parts += [gate_frame, gate_arch_f, door, door_arch]
    for i in range(3):
        parts.append(tg.box(f"gate_band{i}", (0.42, 0.07, 0.025), (0, -0.69, 0.18 + i * 0.14), "gold"))
    # Coat of arms above the gate.
    crest = tg.box("crest", (0.24, 0.05, 0.26), (0, -0.68, 0.78), "cape", bevel=0.05, bevel_seg=3)
    tg.deform(crest, lambda c: Vector((c.x * (1 - max(0.0, -c.z) * 2.2), c.y, c.z)))
    crest_rim = tg.torus("crest_rim", 0.12, 0.014, (0, -0.71, 0.8), "gold", seg=18, minor_seg=6, rot=(90, 0, 0),
                         scale=(1, 1, 1.1))
    crest_gem = tg.sphere("crest_gem", (0.08, 0.04, 0.1), (0, -0.715, 0.79), "gold", seg=8, rings=4)
    parts += [crest, crest_rim, crest_gem]
    for sx in (-1, 1):
        ban = tg.box(f"banner{sx}", (0.17, 0.02, 0.42), (0.42 * sx, -0.675, 0.58), "cape", bevel=0.006, bevel_seg=1)
        tg.deform(ban, lambda c: Vector((c.x, c.y, c.z - (0.07 - abs(c.x) * 0.8 if c.z < -0.2 else 0))))
        ban_t = tg.box(f"banner_t{sx}", (0.2, 0.03, 0.03), (0.42 * sx, -0.68, 0.8), "gold", bevel=0.008, bevel_seg=1)
        ban_e = tg.sphere(f"banner_e{sx}", (0.07, 0.02, 0.09), (0.42 * sx, -0.69, 0.6), "gold", seg=8, rings=4)
        parts += [ban, ban_t, ban_e]
    # Steps down to the path.
    for i, (w, d, h) in enumerate([(0.62, 0.28, 0.1), (0.52, 0.18, 0.06)]):
        parts.append(tg.box(f"step{i}", (w, d, h), (0, -0.78 - 0.07 * (1 - i), h / 2), "stone_light",
                            bevel=0.02, bevel_seg=1))
    parts.append(round_tower("tower_l", -0.72, -0.45, rng))
    parts.append(round_tower("tower_r", 0.72, -0.45, rng))
    parts.append(round_tower("tower_bl", -0.68, 0.84, rng, 0.82))
    parts.append(round_tower("tower_br", 0.68, 0.84, rng, 0.82))
    castle = tg.join(parts, "Castle")
    tg.parent(tg.collider_box("CastleBody", (2.0, 2.05, 1.2), (0, 0.12, 0.6)), castle)
    return castle


def build_portal(rng):
    parts = []
    # Arch of rough stones around a swirling opening.
    n = 11
    for i in range(n):
        a = math.pi * i / (n - 1)  # 0..180 deg
        r = 0.5
        x, z = r * math.cos(a), 0.42 + r * math.sin(a) * 1.05
        st = tg.box(f"arch{i}", (0.2, 0.26, 0.17), (x, 0, z), rng.choice(["rock", "rock_dark", "rock"]),
                    bevel=0.04, bevel_seg=2, rot=(0, -math.degrees(a) + 90, rng.uniform(-8, 8)))
        tg.displace_noise(st, 0.012, 0.08, seed=i)
        parts.append(st)
    for sx in (-1, 1):
        pillar = tg.box(f"pillar{sx}", (0.22, 0.28, 0.45), (0.5 * sx, 0, 0.22), "rock_dark", bevel=0.05, bevel_seg=2)
        tg.displace_noise(pillar, 0.015, 0.1, seed=10 + sx)
        parts.append(pillar)
    disc = tg.cylinder("vortex", 0.42, 0.42, 0.04, (0, 0.02, 0.48), "portal", verts=24, rot=(90, 0, 0))
    tg.deform(disc, lambda c: Vector((c.x, c.y, c.z * 1.12 if c.z > 0 else c.z)))
    parts.append(disc)
    for i, (r, z) in enumerate([(0.3, 0.5), (0.18, 0.52), (0.08, 0.53)]):
        parts.append(tg.torus(f"swirl{i}", r, 0.018, (0.02 * i, -0.01, z), "portal_glow", seg=20, minor_seg=5,
                              rot=(90, 0, 0)))
    puddle = tg.cylinder("goo", 0.5, 0.46, 0.02, (0, -0.25, 0), "slime_dark", verts=18)
    tg.deform(puddle, lambda c: Vector((c.x * 1.1, c.y * 0.8, c.z)))
    tg.shade(puddle, 70)
    parts.append(puddle)
    for i in range(4):
        a = rng.uniform(0, 2 * math.pi)
        rk = tg.sphere(f"rubble{i}", (0.16, 0.13, 0.1), (0.7 * math.cos(a), 0.35 * math.sin(a) + 0.1, 0.03),
                       "rock", seg=8, rings=5)
        tg.displace_noise(rk, 0.015, 0.06, seed=20 + i)
        parts.append(rk)
    portal = tg.join(parts, "Portal")
    tg.parent(tg.collider_box("PortalBody", (1.3, 0.4, 1.0), (0, 0, 0.5)), portal)
    return portal


def build() -> list:
    rng = random.Random(11)
    tg.MAX_BEVEL_SEG = 1  # triangle budget: one bevel segment on every box
    castle = build_castle(rng)
    out = [tg.finish_asset("castle", castle, ao_distance=0.35, ao_strength=0.75)]
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    portal = build_portal(rng)
    out.append(tg.finish_asset("spawn_portal", portal, ao_distance=0.25, ao_strength=0.7))
    return out

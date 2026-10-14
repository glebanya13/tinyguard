"""World map for the level select screen: an island with three level sites.

worldmap.glb: Map (empty) -> Island, Sites, and empties Site1..Site3 marking
where the game puts the level buttons. Faces the default camera (-Y is south).
"""
import math
import random

from mathutils import Vector, noise

import build_castle
import build_environment as env
import tg_common as tg

SITE_BIOMES = ["meadow", "meadow", "meadow", "winter", "autumn", "desert"]  # colours trees near a site
SITES = [(-9.0, 1.0), (-5.0, -3.6), (-1.2, 2.6), (2.6, -3.4), (6.2, 2.4), (9.6, -1.8)]  # Blender x, y


def island():
    """Grass island with sand beach in a sea plane."""
    verts, faces = [], []
    rings, seg = 14, 64
    for r in range(rings + 1):
        for s in range(seg):
            a = 2 * math.pi * s / seg
            edge = 9.5 + 1.2 * noise.noise(Vector((math.cos(a) * 1.5, math.sin(a) * 1.5, 0.3)))
            k = r / rings
            rx, ry = edge * 1.25 * k, edge * 0.85 * k
            x, y = rx * math.cos(a), ry * math.sin(a)
            z = 0.25 * (1 - k ** 3) - (0.25 if r == rings else 0.0)
            verts.append((x, y, z))
    verts.append((0, 0, 0.25))
    c = len(verts) - 1
    for r in range(rings):
        for s in range(seg):
            s2 = (s + 1) % seg
            faces.append(((r + 1) * seg + s, (r + 1) * seg + s2, r * seg + s2, r * seg + s))  # CCW from above
    for s in range(seg):
        faces.append((c, s, (s + 1) % seg))
    land = tg.from_pydata("Land", verts, faces, "grass")
    land.data.materials.append(tg.swatch("sand"))
    for f in land.data.polygons:
        r = min(f.vertices) // seg
        if r >= rings - 1 and f.vertices[0] != c:
            f.material_index = 1
    sea = tg.cylinder("Sea", 22, 22, 0.05, (0, 0, -0.12), "sea", verts=48)
    return tg.join([land, sea], "Island")


def mountain(x, y, s, rng):
    m = tg.cylinder("mount", 1.0 * s, 0.0, 1.6 * s, (x, y, 0.1), "rock", verts=9, smooth=False)
    tg.displace_noise(m, 0.08 * s, 0.4, seed=rng.randint(0, 99))
    cap = tg.cylinder("cap", 0.38 * s, 0.0, 0.62 * s, (x, y, 0.1 + 0.98 * s), "snow", verts=9, smooth=False)
    return [m, cap]


def road(rng):
    parts = []
    for (ax, ay), (bx, by) in zip(SITES, SITES[1:]):
        n = 14
        for i in range(1, n):
            t = i / n
            x = ax + (bx - ax) * t
            y = ay + (by - ay) * t + 1.0 * math.sin(t * math.pi)
            parts.append(tg.cylinder(f"dot{i}", 0.13, 0.13, 0.04, (x, y, 0.25), "path", verts=8))
    return parts


def build() -> dict:
    rng = random.Random(4)
    root = tg.empty("Map")
    parts = [island()]
    for x, y, s in [(-3.5, 5.4, 1.3), (-1.6, 6.0, 1.0), (2.6, 5.6, 1.2), (8.0, 5.0, 0.9), (-8.6, -4.4, 0.8)]:
        parts += mountain(x, y, s, rng)
    for i in range(70):
        a, r = rng.uniform(0, 2 * math.pi), rng.uniform(1.5, 9.5)
        x, y = r * 1.2 * math.cos(a), r * 0.75 * math.sin(a)
        if min(math.hypot(x - sx, y - sy) for sx, sy in SITES) < 1.7 or (abs(y - 5.5) < 1.2 and abs(x) < 4.5):
            continue
        dark = x > 0 and y < 0  # the dark forest (level 2) in the south
        tree = env.tree_pine(rng) if dark or rng.random() < 0.5 else env.tree_round_lite(rng)
        s = rng.uniform(0.55, 0.85)
        tree.scale = (s, s, s)
        tree.location = (x, y, 0.22)
        tg.apply_all_transforms(tree)
        nearest = min(range(len(SITES)), key=lambda k: math.hypot(x - SITES[k][0], y - SITES[k][1]))
        tg.recolor(tree, SITE_BIOMES[nearest])
        parts.append(tree)
    parts += road(rng)
    for i, (x, y) in enumerate(SITES):
        keep = build_castle.round_tower(f"site_tower{i}", 0, 0, rng, 0.75 + 0.15 * i)
        keep.location = (x, y, 0.2)
        tg.apply_all_transforms(keep)
        pad_mat = {"winter": "snow", "autumn": "slime_fast", "desert": "sand"}.get(SITE_BIOMES[i], "stone_light")
        pad = tg.cylinder(f"pad{i}", 0.8, 0.85, 0.12, (x, y, 0.15), pad_mat, verts=16)
        parts += [keep, pad]
    island_mesh = tg.join(parts, "Island")
    tg.parent(island_mesh, root)
    for i, (x, y) in enumerate(SITES):
        tg.parent(tg.empty(f"Site{i + 1}", (x, y, 1.8)), root)
    return tg.finish_asset("worldmap", root, ao_distance=0.3, ao_strength=0.6, ground=False)

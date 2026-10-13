"""Reusable environment props: trees, rocks, a bush and a flower patch.

Each prop is exported as its own GLB (one mesh, origin on the ground).
"""
import math
import random

import bpy
from mathutils import Vector

import tg_common as tg


def _clear() -> None:
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)


def blob(name, size, loc, mat, seed, noise=0.03, seg=12, rings=7):
    obj = tg.sphere(name, size, loc, mat, seg=seg, rings=rings)
    tg.displace_noise(obj, noise, 0.18, seed=seed)
    return obj


def tree_round(rng):
    trunk = tg.lathe("trunk", [(0.11, 0.0), (0.075, 0.08), (0.06, 0.3), (0.05, 0.62)], "wood", steps=8)
    branch = tg.cylinder("branch", 0.03, 0.02, 0.22, (0.03, 0, 0.42), "wood", verts=6, rot=(0, 40, 0))
    parts = [trunk, branch]
    for i, (x, y, z, s, m) in enumerate([(0, 0, 0.98, 0.62, "leaf"), (0.2, -0.08, 0.8, 0.45, "leaf_dark"),
                                         (-0.2, 0.06, 0.82, 0.46, "leaf"), (0.05, 0.18, 0.86, 0.44, "leaf_dark"),
                                         (-0.05, -0.16, 1.12, 0.38, "leaf_light"), (0.12, 0.05, 1.2, 0.32, "leaf_light")]):
        parts.append(blob(f"canopy{i}", (s, s, s * 0.88), (x, y, z), m, seed=i + 1, noise=0.035))
    for i in range(5):
        a = rng.uniform(0, 2 * math.pi)
        r = rng.uniform(0.18, 0.3)
        parts.append(tg.sphere(f"fruit{i}", (0.05, 0.05, 0.05), (r * math.cos(a), r * math.sin(a), rng.uniform(0.75, 1.1)),
                               "berry", seg=8, rings=4))
    return tg.join(parts, "Tree")


def tree_round_lite(rng):
    """Cheaper round tree (~400 tris) for the distant forest."""
    trunk = tg.lathe("trunk", [(0.11, 0.0), (0.07, 0.1), (0.05, 0.62)], "wood", steps=6)
    parts = [trunk]
    for i, (x, y, z, s, m) in enumerate([(0, 0, 0.95, 0.66, "leaf"), (0.17, -0.06, 0.8, 0.46, "leaf_dark"),
                                         (-0.12, 0.1, 1.15, 0.42, "leaf_light")]):
        parts.append(blob(f"canopy{i}", (s, s, s * 0.88), (x, y, z), m, seed=rng.randint(0, 99), noise=0.035,
                          seg=10, rings=6))
    return tg.join(parts, "Tree")


def tree_pine(rng):
    trunk = tg.cylinder("trunk", 0.08, 0.05, 0.35, (0, 0, 0), "wood_dark", verts=8)
    parts = [trunk]
    for i, (z, r, h, m) in enumerate([(0.25, 0.42, 0.55, "pine"), (0.62, 0.33, 0.48, "pine_light"),
                                      (0.95, 0.23, 0.48, "pine")]):
        tier = tg.lathe(f"tier{i}", [(0.0, z), (r, z + 0.02), (r * 0.92, z + 0.08), (r * 0.45, z + h * 0.6),
                                     (0.0, z + h)], m, steps=9)
        tg.displace_noise(tier, 0.02, 0.15, seed=i + 3)
        tg.shade(tier, 40)
        parts.append(tier)
    return tg.join(parts, "Tree")


def rock(name, rng, seed, size=(0.45, 0.36, 0.3), moss=True):
    r = tg.sphere(name, size, (0, 0, size[2] * 0.3), "rock", seg=9, rings=6)
    tg.displace_noise(r, 0.04, 0.12, seed=seed)
    tg.deform(r, lambda c: Vector((c.x, c.y, max(c.z, -size[2] * 0.25))))
    tg.shade(r, 35)
    parts = [r]
    if moss:
        m = tg.sphere(name + "_moss", (size[0] * 0.6, size[1] * 0.55, size[2] * 0.25),
                      (rng.uniform(-0.03, 0.03), rng.uniform(-0.03, 0.03), size[2] * 0.62), "grass_dark", seg=9, rings=5)
        tg.displace_noise(m, 0.015, 0.08, seed=seed + 50)
        parts.append(m)
    return tg.join(parts, name)


def rock_cluster(rng):
    a = rock("ra", rng, 31, (0.36, 0.3, 0.26))
    b = rock("rb", rng, 32, (0.22, 0.2, 0.17), moss=False)
    b.location = (0.22, 0.1, 0)
    c = rock("rc", rng, 33, (0.16, 0.14, 0.12), moss=False)
    c.location = (-0.17, 0.14, 0)
    for o in (b, c):
        tg.apply_all_transforms(o)
    return tg.join([a, b, c], "Rock")


def bush(rng):
    parts = []
    for i, (x, y, z, s, m) in enumerate([(0, 0, 0.16, 0.36, "leaf"), (0.15, 0.05, 0.12, 0.27, "leaf_dark"),
                                         (-0.15, -0.02, 0.12, 0.28, "leaf_dark"), (0.03, -0.12, 0.13, 0.25, "leaf_light")]):
        parts.append(blob(f"b{i}", (s, s, s * 0.85), (x, y, z), m, seed=40 + i, noise=0.025, seg=10, rings=6))
    for i in range(6):
        a = rng.uniform(0, 2 * math.pi)
        parts.append(tg.sphere(f"berry{i}", (0.045, 0.045, 0.045),
                               (0.17 * math.cos(a), 0.15 * math.sin(a), rng.uniform(0.12, 0.27)), "berry", seg=8, rings=4))
    return tg.join(parts, "Bush")


def flowers(rng):
    """Flower clump (~400 tris): reads as coloured dots from the game camera."""
    parts = []
    for i in range(5):
        a = 2 * math.pi * i / 5 + rng.uniform(-0.3, 0.3)
        r = rng.uniform(0.04, 0.12)
        x, y = r * math.cos(a), r * math.sin(a)
        h = rng.uniform(0.06, 0.1)
        parts.append(tg.cylinder(f"stem{i}", 0.01, 0.008, h, (x, y, 0), "leaf_dark", verts=3, smooth=False))
        petal = rng.choice(["flower_pink", "flower_white", "flower_yellow", "flower_pink"])
        for k in range(5):
            pa = 2 * math.pi * k / 5
            parts.append(tg.sphere(f"p{i}{k}", (0.055, 0.034, 0.016), (x + 0.032 * math.cos(pa), y + 0.032 * math.sin(pa), h),
                                   petal, seg=5, rings=2, rot=(0, 0, math.degrees(pa))))
        parts.append(tg.sphere(f"c{i}", (0.032, 0.032, 0.024), (x, y, h + 0.008), "flower_yellow" if petal != "flower_yellow"
                               else "wood_light", seg=5, rings=2))
    # Leafy base so the patch reads as a clump from the game camera.
    for i, (x, y, s) in enumerate([(0, 0, 0.2), (0.09, 0.05, 0.14), (-0.08, 0.04, 0.15)]):
        parts.append(blob(f"leafy{i}", (s, s, s * 0.45), (x, y, 0.02), "leaf_dark" if i % 2 else "leaf",
                          seed=60 + i, noise=0.012, seg=7, rings=4))
    return tg.join(parts, "Flowers")


def build() -> list:
    rng = random.Random(21)
    out = []
    for name, fn, ao in (("tree_round", tree_round, 0.3), ("tree_pine", tree_pine, 0.3), ("rock_a", lambda r: rock("Rock", r, 30), 0.15),
                         ("rock_b", rock_cluster, 0.15), ("bush", bush, 0.15), ("flowers", flowers, 0.06)):
        _clear()
        obj = fn(rng)
        out.append(tg.finish_asset(name, obj, ao_distance=ao, ao_strength=0.7))
    return out

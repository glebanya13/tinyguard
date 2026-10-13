"""Level 01 terrain: grass island with dirt cliffs, the enemy path and path details.

Built in world coordinates so it is placed at the origin in Godot.
Godot (x, y, z) == Blender (x, -z, y). The path follows Level/EnemyPath in
scenes/main.tscn; its corners are rounded but stay within half a metre of the
sharp curve enemies walk on.
"""
import math
import random

import bmesh
from mathutils import Vector, noise

import build_environment as env
import tg_common as tg

HALF_X, HALF_Z = 6.0, 4.0
STEP = 0.25
# Godot XZ: spawn portal -> curve points -> castle steps.
PATH = [(-6.05, -2.5), (-1.5, -2.5), (-1.5, 1.5), (4.05, 1.5)]
PATH_HALF = 0.5
CORNER_R = 0.75  # > path half width + shoulder (0.6), else the inner edge folds
SLOTS = [(-3.5, -1.5), (0.5, 0.5), (2.5, 2.5)]
HERO = (4.3, 3.2)
# Decoration layout (Godot x, z, yaw degrees, scale). Tall props become
# level_01_decor.glb (casts shadows); small ones are merged into the terrain.
TALL = [
    ("pine", -4.8, -3.45, 0, 1.0), ("pine", -3.1, -3.55, 40, 0.85), ("round", -0.4, -3.4, 10, 1.0),
    ("pine", 1.1, -3.5, 70, 1.1), ("round", 2.7, -3.2, 120, 0.9), ("pine", 4.3, -3.45, 15, 1.0),
    ("round", 5.35, -2.3, 200, 1.05), ("pine", 5.45, -0.55, 80, 0.9), ("round", -5.4, 0.7, 30, 1.0),
    ("pine", -5.3, 2.5, 0, 1.1), ("round", -3.9, 3.35, 300, 0.85),
    ("bush", -2.6, 0.9, 0, 1.0), ("bush", 0.9, -1.4, 90, 0.9), ("bush", -0.3, 2.9, 200, 1.1),
    ("bush", 2.2, -1.0, 45, 0.85), ("bush", 5.4, 3.4, 10, 1.0),
]
SMALL = [
    ("rock_a", -2.6, -1.0, 30, 1.0), ("rock_b", 3.3, -0.6, 120, 1.0), ("rock_a", -4.6, 1.6, 200, 0.8),
    ("rock_b", 1.6, 3.45, 60, 0.9), ("rock_a", 3.2, 3.6, 0, 0.7),
    ("flowers", -2.2, 2.5, 0, 1.2), ("flowers", 1.3, -0.4, 60, 1.2), ("flowers", -4.4, -0.6, 120, 1.2),
    ("flowers", 3.7, 3.65, 0, 1.0), ("flowers", 0.3, 3.3, 200, 1.2), ("flowers", -0.4, -1.6, 30, 1.1),
]


def b(gx, gz, h=0.0) -> tuple:
    """Godot ground point -> Blender coordinates."""
    return (gx, -gz, h)


def centerline() -> list:
    """Path centre with corners replaced by quadratic Bezier arcs."""
    pts = []
    for i in range(len(PATH) - 1):
        p0, p1 = Vector(PATH[i]), Vector(PATH[i + 1])
        d = (p1 - p0).normalized()
        start = p0 + d * (CORNER_R if i > 0 else 0)
        end = p1 - d * (CORNER_R if i < len(PATH) - 2 else 0)
        n = max(2, int((end - start).length / STEP))
        pts += [start.lerp(end, k / n) for k in range(n)]
        if i < len(PATH) - 2:
            p2 = Vector(PATH[i + 2])
            a, c = end, p1 + (p2 - p1).normalized() * CORNER_R
            for k in range(8):
                t = k / 8
                pts.append(a * (1 - t) ** 2 + p1 * 2 * (1 - t) * t + c * t * t)
    pts.append(Vector(PATH[-1]))
    return pts


def dist_to_path(x, z) -> float:
    p = Vector((x, z))
    best = 1e9
    for i in range(len(PATH) - 1):
        a, c = Vector(PATH[i]), Vector(PATH[i + 1])
        ab = c - a
        t = max(0.0, min(1.0, (p - a).dot(ab) / ab.length_squared))
        best = min(best, (a + ab * t - p).length)
    return best


def free_spot(x, z, margin=0.75) -> bool:
    """True where decoration may go: off the path, slots, castle, hero and portal."""
    if abs(x) > HALF_X - 0.3 or abs(z) > HALF_Z - 0.3:
        return False
    if dist_to_path(x, z) < margin:
        return False
    if any(math.hypot(x - sx, z - sz) < 0.75 for sx, sz in SLOTS):
        return False
    if x > 3.6 and 0.2 < z < 2.8:  # castle
        return False
    if math.hypot(x - HERO[0], z - HERO[1]) < 0.55:
        return False
    if x < -4.9 and abs(z + 2.5) < 1.1:  # portal
        return False
    return True


def build_ground():
    nx, nz = int(2 * HALF_X / STEP), int(2 * HALF_Z / STEP)
    verts, faces = [], []
    for j in range(nz + 1):
        for i in range(nx + 1):
            gx, gz = -HALF_X + i * STEP, -HALF_Z + j * STEP
            # Gentle undulation away from the path keeps the board readable.
            h = 0.0
            if dist_to_path(gx, gz) > 1.0:
                h = 0.03 * noise.noise(Vector((gx * 0.6, gz * 0.6, 0.5)))
            verts.append(b(gx, gz, h))
    for j in range(nz):
        for i in range(nx):
            a = j * (nx + 1) + i
            faces.append((a, a + nx + 1, a + nx + 2, a + 1))
    ground = tg.from_pydata("Ground", verts, faces, "grass")

    # Cliff skirt around the border, following the grid's border vertices.
    border = []
    border += [(i, 0) for i in range(nx)]
    border += [(nx, j) for j in range(nz)]
    border += [(i, nz) for i in range(nx, 0, -1)]
    border += [(0, j) for j in range(nz, 0, -1)]
    rows = [(0.0, 0.0), (0.04, -0.045), (0.035, -0.13), (0.0, -0.3), (-0.06, -0.5), (-0.18, -0.72)]
    mats = ["grass_dark", "dirt", "dirt", "dirt_dark", "rock_dark"]
    sverts, sfaces, smat = [], [], []
    for (i, j) in border:
        gx, gz = -HALF_X + i * STEP, -HALF_Z + j * STEP
        nxv = (1 if i == nx else -1 if i == 0 else 0)
        nzv = (1 if j == nz else -1 if j == 0 else 0)
        n = Vector((nxv, nzv)).normalized()
        for r, (off, z) in enumerate(rows):
            jitter = 0.05 * noise.noise(Vector((gx * 1.7, gz * 1.7, r * 0.9))) if r >= 2 else 0.0
            sverts.append(b(gx + n.x * (off + jitter), gz + n.y * (off + jitter), z))
    nb, nr = len(border), len(rows)
    for k in range(nb):
        k2 = (k + 1) % nb
        for r in range(nr - 1):
            sfaces.append((k * nr + r, k * nr + r + 1, k2 * nr + r + 1, k2 * nr + r))
            smat.append(r)
    skirt = tg.from_pydata("Skirt", sverts, sfaces, None, smooth=False)
    for m in mats:
        skirt.data.materials.append(tg.swatch(m))
    for f, m in zip(skirt.data.polygons, smat):
        f.material_index = m
    bm = bmesh.new()
    bm.from_mesh(skirt.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(skirt.data)
    bm.free()
    tg.shade(skirt, 50)
    return ground, skirt


def build_path():
    pts = centerline()
    section = [(-0.6, -0.02, "path_dark"), (-0.5, 0.012, "path"), (-0.25, 0.016, "path"), (0.0, 0.018, "path"),
               (0.25, 0.016, "path"), (0.5, 0.012, "path_dark"), (0.6, -0.02, None)]
    verts, faces, fmat = [], [], []
    for k, p in enumerate(pts):
        a = pts[max(k - 1, 0)]
        c = pts[min(k + 1, len(pts) - 1)]
        t = (c - a).normalized()
        n = Vector((-t.y, t.x))
        for off, h, _ in section:
            q = p + n * off
            verts.append(b(q.x, q.y, h))
    ns = len(section)
    for k in range(len(pts) - 1):
        for s in range(ns - 1):
            faces.append((k * ns + s, (k + 1) * ns + s, (k + 1) * ns + s + 1, k * ns + s + 1))
            fmat.append(section[s][2])
    path = tg.from_pydata("Path", verts, faces, None)
    names = sorted(set(fmat))
    for m in names:
        path.data.materials.append(tg.swatch(m))
    for f, m in zip(path.data.polygons, fmat):
        f.material_index = names.index(m)
    bm = bmesh.new()
    bm.from_mesh(path.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for f in bm.faces:
        if f.normal.z < 0:
            f.normal_flip()
    bm.to_mesh(path.data)
    bm.free()
    tg.shade(path, 60)
    return path, pts


def pebble(name, rng, x, z, size, mat):
    s = tg.sphere(name, (size * rng.uniform(0.9, 1.3), size, size * 0.55), b(x, z, 0.01), mat, seg=6, rings=4,
                  rot=(0, 0, rng.uniform(0, 180)))
    tg.displace_noise(s, size * 0.12, 0.05, seed=rng.randint(0, 999))
    return s


def build_details(rng, pts):
    parts = []
    # Stones along both path edges.
    for k in range(0, len(pts), 2):
        p = pts[k]
        a, c = pts[max(k - 1, 0)], pts[min(k + 1, len(pts) - 1)]
        t = (c - a).normalized()
        n = Vector((-t.y, t.x))
        for side in (-1, 1):
            q = p + n * side * rng.uniform(0.6, 0.68) + t * rng.uniform(-0.08, 0.08)
            if q.x < -5.4 or q.x > 3.8 or rng.random() < 0.25:
                continue
            if any(math.hypot(q.x - sx, q.y - sz) < 0.62 for sx, sz in SLOTS):
                continue
            parts.append(pebble(f"edge{k}{side}", rng, q.x, q.y, rng.uniform(0.07, 0.11),
                                rng.choice(["rock", "stone_light", "rock"])))
    # Grass tufts and scattered pebbles on free ground.
    placed = 0
    while placed < 70:
        x, z = rng.uniform(-5.7, 5.7), rng.uniform(-3.7, 3.7)
        if not free_spot(x, z, 0.7):
            continue
        blades = []
        for i in range(rng.randint(3, 5)):
            a = rng.uniform(0, 2 * math.pi)
            r = rng.uniform(0.0, 0.05)
            bl = tg.cylinder(f"blade{placed}_{i}", 0.018, 0.0, rng.uniform(0.08, 0.15),
                             b(x + r * math.cos(a), z + r * math.sin(a)), rng.choice(["grass_dark", "leaf"]),
                             verts=3, rot=(rng.uniform(-18, 18), rng.uniform(-18, 18), 0), smooth=False)
            blades.append(bl)
        parts += blades
        placed += 1
    for i in range(18):
        x, z = rng.uniform(-5.7, 5.7), rng.uniform(-3.7, 3.7)
        if free_spot(x, z, 0.65):
            parts.append(pebble(f"peb{i}", rng, x, z, rng.uniform(0.04, 0.07), "rock"))
    return tg.join(parts, "Details")


def place(layout, name):
    makers = {"pine": env.tree_pine, "round": env.tree_round, "bush": env.bush, "flowers": env.flowers,
              "rock_a": lambda r: env.rock("Rock", r, 30), "rock_b": env.rock_cluster}
    rng = random.Random(9)
    objs = []
    for kind, x, z, yaw, s in layout:
        obj = makers[kind](rng)
        obj.rotation_euler = (0, 0, math.radians(yaw))
        obj.scale = (s, s, s)
        obj.location = b(x, z, 0)
        tg.apply_all_transforms(obj)
        objs.append(obj)
    return tg.join(objs, name)


def build() -> list:
    rng = random.Random(5)
    ground, skirt = build_ground()
    path, pts = build_path()
    details = build_details(rng, pts)
    small = place(SMALL, "Small")
    terrain = tg.join([ground, skirt, path, details, small], "Terrain")
    decor = place(TALL, "Decor")

    def tint(co):
        # Soft colour variation on the grass (AO channel).
        return 0.9 + 0.12 * noise.noise(Vector((co.x * 0.45, co.y * 0.45, 3.0)))
    out = [tg.finish_asset("level_01_terrain", terrain, ao_distance=0.3, ao_strength=0.6, ground=False, tint=tint,
                           occluders=[decor])]
    out.append(tg.finish_asset("level_01_decor", decor, ao_distance=0.3, ao_strength=0.7, ground=False,
                               occluders=[terrain]))
    return out

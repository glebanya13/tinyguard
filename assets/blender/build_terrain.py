"""Level terrain: ground with hills, the enemy path, path details and decoration.

Layouts come from resources/levels.json (shared with Godot). For every level this
builds level_<id>_terrain.glb, level_<id>_decor.glb and level_<id>_forest.glb in
world coordinates (placed at the origin in Godot). Godot (x, y, z) == Blender
(x, -z, y). Path corners are rounded (0.75 m) but stay within half a metre of the
sharp curve enemies walk on (a 0.75 m quadratic corner is 0.27 m off the sharp one).
Set TG_LEVELS=1,3 to build only some levels.
"""
import json
import math
import os
import random

import bmesh
from mathutils import Vector, noise

import build_environment as env
import tg_common as tg

LEVELS_FILE = tg.ROOT / "resources" / "levels.json"
GROUND_HALF = 40.0
STEP = 0.5
PATH_HALF = 0.5
CORNER_R = 0.75  # > path half width + shoulder (0.6), else the inner edge folds
CHUNK = 10.0

# Current level (set by use_level).
PLAY_X = PLAY_Z = DENSE_X = DENSE_Z = 0.0
PATH: list = []
SLOTS: list = []
HERO: tuple = (0.0, 0.0)
CASTLE: tuple = (0.0, 0.0)
PORTAL: tuple = (0.0, 0.0)
CHOP_TREES: list = []


def use_level(lv: dict) -> None:
    global PLAY_X, PLAY_Z, DENSE_X, DENSE_Z, PATH, SLOTS, HERO, CASTLE, PORTAL, CHOP_TREES
    x0, z0, w, h = lv["bounds"]
    PLAY_X, PLAY_Z = w / 2, h / 2
    DENSE_X, DENSE_Z = PLAY_X + 1.5, PLAY_Z + 1.5
    pts = [tuple(p) for p in lv["path"]]
    # Extend the last segment to the castle steps.
    (ax, az), (bx, bz) = pts[-2], pts[-1]
    d = Vector((bx - ax, bz - az)).normalized()
    PATH = pts[:-1] + [(bx + d.x * 0.45, bz + d.y * 0.45)]
    SLOTS = [tuple(s) for s in lv["slots"]]
    HERO = tuple(lv["hero"])
    CASTLE = tuple(lv["castle"])
    PORTAL = pts[0]
    CHOP_TREES = [tuple(s) for s in lv["trees"]]


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
    """True where decoration may go: off the path, slots, castle, hero, portal and choppable trees."""
    if abs(x) > PLAY_X - 0.3 or abs(z) > PLAY_Z - 0.3:
        return False
    if dist_to_path(x, z) < margin:
        return False
    if any(math.hypot(x - sx, z - sz) < 1.0 for sx, sz in SLOTS):
        return False
    if abs(x - CASTLE[0]) < 1.9 and abs(z - CASTLE[1]) < 1.9:
        return False
    if math.hypot(x - HERO[0], z - HERO[1]) < 0.8:
        return False
    if math.hypot(x - PORTAL[0], z - PORTAL[1]) < 1.8:
        return False
    if any(math.hypot(x - tx, z - tz) < 1.1 for tx, tz in CHOP_TREES):
        return False
    return True


def axis(dense: float) -> list:
    """Grid coordinates: 0.5 m inside the play area, 2 m in the distant hills."""
    coarse = [-GROUND_HALF + 2.0 * i for i in range(int((GROUND_HALF - dense) / 2.0) + 1)]
    fine = [-dense + STEP * i for i in range(int(2 * dense / STEP) + 1)]
    pts = sorted({round(v, 3) for v in coarse + fine + [-v for v in coarse]})
    return [v for v in pts if -dense - 0.01 <= v <= dense + 0.01 or abs(v) >= dense + 1.0]


def outside(gx, gz) -> float:
    """Distance beyond the play rectangle (0 inside)."""
    return max(abs(gx) - PLAY_X, abs(gz) - PLAY_Z, 0.0)


def height(gx, gz) -> float:
    d = outside(gx, gz)
    if d > 0:  # rolling hills rising towards the horizon
        rise = min(d, 9.0) / 9.0
        return rise * (0.5 + 0.9 * (0.5 + 0.5 * noise.noise(Vector((gx * 0.12, gz * 0.12, 2.0)))))
    if dist_to_path(gx, gz) > 1.0:
        return 0.03 * noise.noise(Vector((gx * 0.6, gz * 0.6, 0.5)))
    return 0.0


def build_ground():
    xs, zs = axis(DENSE_X), axis(DENSE_Z)
    verts, faces = [], []
    for gz in zs:
        for gx in xs:
            verts.append(b(gx, gz, height(gx, gz)))
    nx = len(xs)
    for j in range(len(zs) - 1):
        for i in range(nx - 1):
            a = j * nx + i
            faces.append((a, a + nx, a + nx + 1, a + 1))
    ground = tg.from_pydata("Ground", verts, faces, "grass")
    bm = bmesh.new()
    bm.from_mesh(ground.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for f in bm.faces:
        if f.normal.z < 0:
            f.normal_flip()
    bm.to_mesh(ground.data)
    bm.free()
    tg.shade(ground, 60)
    return ground


def build_walls():
    """Invisible walls around the play area (Godot StaticBody3D via -colonly)."""
    t = 0.5
    walls = [
        tg.collider_box("WallN", (2 * PLAY_X + 2 * t, t, 3), b(0, -PLAY_Z - t / 2, 1.5)),
        tg.collider_box("WallS", (2 * PLAY_X + 2 * t, t, 3), b(0, PLAY_Z + t / 2, 1.5)),
        tg.collider_box("WallW", (t, 2 * PLAY_Z + 2 * t, 3), b(-PLAY_X - t / 2, 0, 1.5)),
        tg.collider_box("WallE", (t, 2 * PLAY_Z + 2 * t, 3), b(PLAY_X + t / 2, 0, 1.5)),
    ]
    return walls


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
            if rng.random() < 0.25 or math.hypot(q.x - PORTAL[0], q.y - PORTAL[1]) < 1.3:
                continue
            if math.hypot(q.x - CASTLE[0], q.y - CASTLE[1]) < 1.9:
                continue
            if any(math.hypot(q.x - sx, q.y - sz) < 0.62 for sx, sz in SLOTS):
                continue
            parts.append(pebble(f"edge{k}{side}", rng, q.x, q.y, rng.uniform(0.07, 0.11),
                                rng.choice(["rock", "stone_light", "rock"])))
    # Grass tufts and scattered pebbles on free ground.
    placed = 0
    while placed < 330:
        x, z = rng.uniform(-PLAY_X, PLAY_X), rng.uniform(-PLAY_Z, PLAY_Z)
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
    for i in range(90):
        x, z = rng.uniform(-PLAY_X, PLAY_X), rng.uniform(-PLAY_Z, PLAY_Z)
        if free_spot(x, z, 0.65):
            parts.append(pebble(f"peb{i}", rng, x, z, rng.uniform(0.04, 0.07), "rock"))
    return tg.join(parts, "Details")


MAKERS = {"pine": env.tree_pine, "round": env.tree_round, "round_lite": env.tree_round_lite, "bush": env.bush,
          "flowers": env.flowers, "rock_a": lambda r: env.rock("Rock", r, 30), "rock_b": env.rock_cluster}
TREES = ("pine", "round", "round_lite")
CHUNK = 10.0


def generated_layout(rng):
    """More groves inside the bigger play area and a forest ring outside it."""
    tall, small = [], []
    taken = list(CHOP_TREES)

    def spaced(x, z, d):
        return all(math.hypot(x - a, z - c) > d for a, c in taken)
    tries = 0
    while len(tall) < 46 and tries < 8000:
        tries += 1
        x, z = rng.uniform(-PLAY_X + 0.8, PLAY_X - 0.8), rng.uniform(-PLAY_Z + 0.8, PLAY_Z - 0.8)
        if not free_spot(x, z, 1.0) or not spaced(x, z, 1.3):
            continue
        kind = rng.choice(["pine", "pine", "round", "bush"])
        tall.append((kind, x, z, rng.uniform(0, 360), rng.uniform(0.85, 1.2)))
        taken.append((x, z))
    tries = 0
    while len(small) < 60 and tries < 8000:
        tries += 1
        x, z = rng.uniform(-PLAY_X + 0.5, PLAY_X - 0.5), rng.uniform(-PLAY_Z + 0.5, PLAY_Z - 0.5)
        if free_spot(x, z, 0.8):
            small.append((rng.choice(["flowers", "flowers", "rock_a", "rock_b"]), x, z, rng.uniform(0, 360),
                          rng.uniform(0.8, 1.2)))
    # Forest ring: dense next to the walls, sparser further out.
    ring = []
    gx = -PLAY_X - 13.0
    while gx <= PLAY_X + 13.0:
        gz = -PLAY_Z - 13.0
        while gz <= PLAY_Z + 13.0:
            jx, jz = gx + rng.uniform(-0.6, 0.6), gz + rng.uniform(-0.6, 0.6)
            d = outside(jx, jz)
            if 1.2 < d and (d < 6.0 or rng.random() < 0.2):
                kind = "pine" if rng.random() < 0.7 else "round_lite"
                ring.append((kind, jx, jz, rng.uniform(0, 360), rng.uniform(0.95, 1.45)))
            gz += 2.0
        gx += 2.0
    return tall, small, ring


def place(layout, name, ground_height=False):
    rng = random.Random(9)
    objs = []
    for kind, x, z, yaw, s in layout:
        obj = MAKERS[kind](rng)
        obj.rotation_euler = (0, 0, math.radians(yaw))
        obj.scale = (s, s, s)
        obj.location = b(x, z, height(x, z) - 0.02 if ground_height else 0)
        tg.apply_all_transforms(obj)
        objs.append(obj)
    return tg.join(objs, name) if objs else None


def chunked(layout, prefix):
    """Join props per CHUNK x CHUNK cell so Godot can frustum-cull the forest."""
    cells = {}
    for item in layout:
        key = (math.floor(item[1] / CHUNK), math.floor(item[2] / CHUNK))
        cells.setdefault(key, []).append(item)
    return [place(items, f"{prefix}_{kx}_{kz}".replace("-", "m"), ground_height=True)
            for (kx, kz), items in sorted(cells.items())]


def build_level(lv: dict) -> list:
    use_level(lv)
    rng = random.Random(5 + lv["id"])
    ground = build_ground()
    path, pts = build_path()
    details = build_details(rng, pts)
    gen_tall, gen_small, ring = generated_layout(random.Random(13 + lv["id"]))
    # Every tree inside the play area can be chopped: Godot puts a WoodTree on each
    # Chop_<kind>_<i> marker, so those trees are not baked into the decor mesh.
    rng_spot = random.Random(21 + lv["id"])
    chop = [("round", x, z, rng_spot.uniform(0, 360), rng_spot.uniform(0.95, 1.15)) for x, z in CHOP_TREES]
    chop += [item for item in gen_tall if item[0] in TREES]
    gen_tall = [item for item in gen_tall if item[0] not in TREES]
    terrain = tg.join([ground, path, details], "Terrain")
    for wall in build_walls():
        tg.parent(wall, terrain)

    decor = tg.empty("Decor")
    for chunk in chunked(gen_tall + gen_small, "Chunk"):
        tg.parent(chunk, decor)
    forest = tg.empty("Forest")
    for chunk in chunked(ring, "Ring"):
        tg.parent(chunk, forest)
    for i, (kind, x, z, yaw, s) in enumerate(chop):
        marker = tg.empty(f"Chop_{kind}_{i}", b(x, z, max(height(x, z) - 0.02, 0.0)))
        marker.rotation_euler = (0, 0, math.radians(yaw))
        marker.scale = (s, s, s)
        tg.parent(marker, decor)
    # Bushes inside the play area block the hero (chop trees have their own bodies).
    cols = [tg.collider_cylinder(f"trunk{i}", 0.28 if kind in TREES else 0.32, 1.2, b(x, z, 0))
            for i, (kind, x, z, _, s) in enumerate(gen_tall)]
    if cols:
        tg.parent(tg.join(cols, "Trunks" + tg.COLLIDER_SUFFIX), decor)
    chunks = [c for c in decor.children if c.type == "MESH" and not tg.is_collider(c)] + list(forest.children)

    def tint(co):
        # Soft colour variation on the grass (AO channel).
        return 0.9 + 0.12 * noise.noise(Vector((co.x * 0.45, co.y * 0.45, 3.0)))
    name = f"level_{lv['id']}"
    out = [tg.finish_asset(f"{name}_terrain", terrain, ao_distance=0.3, ao_strength=0.6, ground=False, tint=tint,
                           occluders=chunks)]
    out.append(tg.finish_asset(f"{name}_decor", decor, ao_distance=0.3, ao_strength=0.7, ground=False,
                               occluders=[terrain] + list(forest.children)))
    out.append(tg.finish_asset(f"{name}_forest", forest, ao_distance=0.3, ao_strength=0.7, ground=False,
                               occluders=[terrain]))
    return out


def build() -> list:
    import bpy
    levels = json.loads(LEVELS_FILE.read_text(encoding="utf-8"))["levels"]
    only = os.environ.get("TG_LEVELS")
    if only:
        levels = [lv for lv in levels if str(lv["id"]) in only.split(",")]
    out = []
    for lv in levels:
        for o in list(bpy.data.objects):
            bpy.data.objects.remove(o, do_unlink=True)
        out += build_level(lv)
    return out

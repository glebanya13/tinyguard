"""Small 3D models that tools/render_icons.gd renders into the HUD icons.

Each icon_<name>.glb is centred at the origin, about 1 m tall, facing -Y.
They are not used in the game world.
"""
import math

import bpy
from mathutils import Vector

import build_hero
import tg_common as tg


def _clear() -> None:
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)


def extrude_outline(name, outline_xz, depth, mat, bevel=0.03, subsurf=1):
    """Flat shape in the XZ plane extruded along Y, rounded."""
    n = len(outline_xz)
    verts = [(x, -depth / 2, z) for x, z in outline_xz] + [(x, depth / 2, z) for x, z in outline_xz]
    faces = [tuple(range(n)), tuple(reversed(range(n, 2 * n)))]
    faces += [(i, (i + 1) % n, n + (i + 1) % n, n + i) for i in range(n)]
    obj = tg.from_pydata(name, verts, faces, mat, smooth=False)
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(obj.data)
    bm.free()
    if bevel:
        tg.add_bevel(obj, bevel, 2, angle_deg=30)
    if subsurf:
        tg.add_subsurf(obj, subsurf)
    tg.shade(obj, 50)
    return obj


def star_outline(r_out, r_in, points=5):
    pts = []
    for i in range(points * 2):
        a = math.pi / 2 + math.pi * i / points
        r = r_out if i % 2 == 0 else r_in
        pts.append((r * math.cos(a), r * math.sin(a)))
    return pts


def icon_coin():
    disc = tg.cylinder("disc", 0.48, 0.48, 0.12, (0, 0.06, 0), "gold", verts=32, rot=(90, 0, 0))
    rim = tg.torus("rim", 0.46, 0.05, (0, 0, 0), "gold", seg=32, minor_seg=8, rot=(90, 0, 0))
    star = extrude_outline("star", star_outline(0.26, 0.11), 0.06, "gold", bevel=0.015, subsurf=0)
    star.location = (0, -0.07, 0)
    tg.apply_all_transforms(star)
    return tg.join([disc, rim, star], "Coin")


def icon_heart():
    pts = []
    for i in range(40):
        t = 2 * math.pi * i / 40
        x = 16 * math.sin(t) ** 3
        z = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)
        pts.append((x / 32, z / 32))
    heart = extrude_outline("heart", pts, 0.26, "ruby", bevel=0.08, subsurf=1)
    shine = tg.sphere("shine", (0.14, 0.04, 0.09), (-0.2, -0.16, 0.16), "white", seg=10, rings=5, rot=(0, 30, 0))
    return tg.join([heart, shine], "Heart")


def icon_sword():
    sword = build_hero.build_sword()
    sword.scale = (2.1, 2.1, 2.1)
    sword.rotation_euler = (0, math.radians(-40), 0)
    sword.location = (0, 0, -0.1)
    tg.apply_all_transforms(sword)
    return sword


def icon_crown():
    band = tg.cylinder("band", 0.42, 0.46, 0.22, (0, 0, -0.25), "gold", verts=20)
    parts = [band]
    for i in range(5):
        a = math.pi * 2 * i / 5 - math.pi / 2
        x, y = 0.42 * math.cos(a), 0.42 * math.sin(a)
        parts.append(tg.cylinder(f"sp{i}", 0.11, 0.0, 0.32, (x, y, -0.05), "gold", verts=8))
        parts.append(tg.sphere(f"ball{i}", (0.09, 0.09, 0.09), (x, y, 0.29), "gold", seg=10, rings=5))
    for i, a in enumerate([-math.pi / 2, -math.pi / 2 - 1.2, -math.pi / 2 + 1.2]):
        parts.append(tg.sphere(f"gem{i}", (0.12, 0.06, 0.12), (0.45 * math.cos(a), 0.45 * math.sin(a), -0.15),
                               "ruby" if i == 0 else "ice", seg=10, rings=5))
    return tg.join(parts, "Crown")


def icon_hourglass():
    top = tg.cylinder("top", 0.36, 0.36, 0.08, (0, 0, 0.42), "wood", verts=16)
    bottom = tg.cylinder("bottom", 0.36, 0.36, 0.08, (0, 0, -0.5), "wood", verts=16)
    glass_t = tg.cylinder("glass_t", 0.05, 0.28, 0.42, (0, 0, 0.0), "ice_light", verts=16)
    glass_b = tg.cylinder("glass_b", 0.28, 0.05, 0.42, (0, 0, -0.42), "ice_light", verts=16)
    sand_b = tg.cylinder("sand_b", 0.22, 0.12, 0.16, (0, 0, -0.42), "path", verts=16)
    sand_t = tg.cylinder("sand_t", 0.03, 0.17, 0.14, (0, 0, 0.18), "path", verts=16)
    posts = [tg.cylinder(f"post{i}", 0.035, 0.035, 0.84, (0.3 * math.cos(a), 0.3 * math.sin(a), -0.42), "wood_dark",
                         verts=8) for i, a in enumerate([0.8, 2.9, 5.0])]
    return tg.join([top, bottom, glass_t, glass_b, sand_b, sand_t, *posts], "Hourglass")


def icon_flag():
    pole = tg.cylinder("pole", 0.035, 0.03, 1.0, (-0.3, 0, -0.5), "wood_dark", verts=10)
    ball = tg.sphere("ball", (0.1, 0.1, 0.1), (-0.3, 0, 0.52), "gold", seg=10, rings=5)
    pts = []
    cols = 8
    for i in range(cols + 1):
        u = i / cols
        wave = 0.06 * math.sin(u * math.pi * 1.8)
        pts.append((-0.27 + 0.72 * u, wave, 0.45 - 0.05 * u))
        pts.append((-0.27 + 0.72 * u + (0.12 if i == cols else 0), wave, 0.0 + 0.1 * u))
    faces = [(2 * i, 2 * i + 2, 2 * i + 3, 2 * i + 1) for i in range(cols)]
    cloth = tg.from_pydata("cloth", pts, faces, "cape")
    tg.add_solidify(cloth, 0.04)
    trim = tg.box("trim", (0.05, 0.06, 0.47), (-0.25, 0, 0.22), "gold")
    return tg.join([pole, ball, cloth, trim], "Flag")


def icon_upgrade():
    arrow = [(0, 0.5), (0.42, 0.06), (0.17, 0.06), (0.17, -0.45), (-0.17, -0.45), (-0.17, 0.06), (-0.42, 0.06)]
    obj = extrude_outline("arrow", arrow, 0.22, "gold", bevel=0.04, subsurf=0)
    star = extrude_outline("star", star_outline(0.16, 0.07), 0.08, "ruby", bevel=0.01, subsurf=0)
    star.location = (0, -0.13, -0.1)
    tg.apply_all_transforms(star)
    return tg.join([obj, star], "Upgrade")


def icon_lock():
    body = tg.box("body", (0.7, 0.3, 0.55), (0, 0, -0.18), "iron", bevel=0.08, bevel_seg=3)
    shackle = tg.torus("shackle", 0.22, 0.06, (0, 0, 0.1), "steel", seg=24, minor_seg=8, rot=(90, 0, 0))
    tg.deform(shackle, lambda c: Vector((c.x, c.y, max(c.z, -0.05))))
    hole = tg.cylinder("hole", 0.07, 0.07, 0.04, (0, -0.15, -0.12), "eye", verts=12, rot=(90, 0, 0))
    slot = tg.box("slot", (0.05, 0.04, 0.16), (0, -0.16, -0.25), "eye")
    trim = tg.box("trim", (0.74, 0.32, 0.06), (0, 0, 0.07), "gold", bevel=0.02, bevel_seg=1)
    return tg.join([body, shackle, hole, slot, trim], "Lock")


def icon_star():
    return extrude_outline("Star", star_outline(0.52, 0.23), 0.2, "gold", bevel=0.05, subsurf=0)


def icon_cancel():
    a = tg.box("a", (0.22, 0.2, 0.95), (0, 0, 0), "ruby", bevel=0.08, bevel_seg=3, rot=(0, 45, 0))
    b = tg.box("b", (0.22, 0.2, 0.95), (0, 0, 0), "ruby", bevel=0.08, bevel_seg=3, rot=(0, -45, 0))
    return tg.join([a, b], "Cancel")


ICONS = {"coin": icon_coin, "heart": icon_heart, "sword": icon_sword, "crown": icon_crown,
         "hourglass": icon_hourglass, "flag": icon_flag, "upgrade": icon_upgrade, "lock": icon_lock,
         "star": icon_star, "cancel": icon_cancel}


def build() -> list:
    out = []
    for name, fn in ICONS.items():
        _clear()
        out.append(tg.finish_asset(f"icon_{name}", fn(), ao_distance=0.15, ao_strength=0.5, ground=False))
    return out

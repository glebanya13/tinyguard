"""Small 3D models that tools/render_icons.gd renders into the HUD icons.

Each icon_<name>.glb is centred at the origin, about 1 m tall, facing -Y.
They are not used in the game world.
"""
import math

import bmesh
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
    """Thick gold coin with a raised rim and an embossed crown."""
    disc = tg.cylinder("disc", 0.5, 0.5, 0.16, (0, 0.08, 0), "gold", verts=40, rot=(90, 0, 0))
    rim_f = tg.torus("rim_f", 0.47, 0.045, (0, -0.08, 0), "gold", seg=40, minor_seg=8, rot=(90, 0, 0))
    rim_b = tg.torus("rim_b", 0.47, 0.045, (0, 0.08, 0), "gold", seg=40, minor_seg=8, rot=(90, 0, 0))
    crown = [(-0.24, -0.16), (0.24, -0.16), (0.28, 0.14), (0.14, 0.02), (0.0, 0.2), (-0.14, 0.02), (-0.28, 0.14)]
    emboss = extrude_outline("crown", crown, 0.07, "gold", bevel=0.02, subsurf=0)
    emboss.location = (0, -0.1, 0.0)
    tg.apply_all_transforms(emboss)
    return tg.join([disc, rim_f, rim_b, emboss], "Coin")


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
    """Chunky green up arrow with a gold star: level up."""
    arrow = [(0, 0.55), (0.48, 0.08), (0.2, 0.08), (0.2, -0.5), (-0.2, -0.5), (-0.2, 0.08), (-0.48, 0.08)]
    obj = extrude_outline("arrow", arrow, 0.24, "go", bevel=0.06, subsurf=0)
    back = extrude_outline("back", arrow, 0.1, "go_dark", bevel=0.0, subsurf=0)
    back.scale = (1.08, 1, 1.06)
    back.location = (0, 0.1, -0.01)
    tg.apply_all_transforms(back)
    star = extrude_outline("star", star_outline(0.17, 0.08), 0.08, "star", bevel=0.02, subsurf=0)
    star.location = (0, -0.15, -0.18)
    tg.apply_all_transforms(star)
    return tg.join([obj, back, star], "Upgrade")


def icon_lock():
    body = tg.box("body", (0.7, 0.3, 0.55), (0, 0, -0.18), "iron", bevel=0.08, bevel_seg=3)
    shackle = tg.torus("shackle", 0.22, 0.06, (0, 0, 0.1), "steel", seg=24, minor_seg=8, rot=(90, 0, 0))
    tg.deform(shackle, lambda c: Vector((c.x, c.y, max(c.z, -0.05))))
    hole = tg.cylinder("hole", 0.07, 0.07, 0.04, (0, -0.15, -0.12), "eye", verts=12, rot=(90, 0, 0))
    slot = tg.box("slot", (0.05, 0.04, 0.16), (0, -0.16, -0.25), "eye")
    trim = tg.box("trim", (0.74, 0.32, 0.06), (0, 0, 0.07), "gold", bevel=0.02, bevel_seg=1)
    return tg.join([body, shackle, hole, slot, trim], "Lock")


def icon_star():
    """Puffy yellow star with a shine."""
    star = extrude_outline("Star", star_outline(0.55, 0.26), 0.24, "star", bevel=0.09, subsurf=1)
    shine = tg.sphere("shine", (0.12, 0.04, 0.07), (-0.16, -0.17, 0.2), "white", seg=10, rings=5, rot=(0, 35, 0))
    return tg.join([star, shine], "Star")


def icon_cancel():
    a = tg.box("a", (0.22, 0.2, 0.95), (0, 0, 0), "ruby", bevel=0.08, bevel_seg=3, rot=(0, 45, 0))
    b = tg.box("b", (0.22, 0.2, 0.95), (0, 0, 0), "ruby", bevel=0.08, bevel_seg=3, rot=(0, -45, 0))
    return tg.join([a, b], "Cancel")


def icon_whirl():
    """Sword inside a swirl ring: the hero's spin attack."""
    sword = icon_sword()
    sword.scale = (0.8, 0.8, 0.8)
    tg.apply_all_transforms(sword)
    ring = tg.torus("ring", 0.5, 0.05, (0, 0, 0), "gold", seg=40, minor_seg=8, rot=(90, 0, 0))
    # Open the ring into a swirl with an arrow head.
    tg.deform(ring, lambda c: Vector((c.x * (1 + 0.15 * max(c.x, 0)), c.y, c.z)))
    head = tg.cylinder("head", 0.13, 0.0, 0.22, (0.55, 0, 0.1), "gold", verts=10, rot=(0, 20, 0))
    return tg.join([sword, ring, head], "Whirl")


def icon_hammer():
    """Smith's hammer over an anvil: the forge."""
    handle = tg.cylinder("handle", 0.045, 0.04, 0.75, (0, 0, -0.2), "wood", verts=10)
    head = tg.box("head", (0.42, 0.2, 0.2), (0, 0, 0.6), "steel", bevel=0.03, bevel_seg=2)
    band = tg.box("band", (0.1, 0.22, 0.22), (0, 0, 0.6), "gold", bevel=0.01, bevel_seg=1)
    hammer = tg.join([handle, head, band], "Hammer")
    hammer.rotation_euler = (0, math.radians(-35), 0)
    hammer.location = (0.25, -0.12, -0.38)
    tg.apply_all_transforms(hammer)
    anvil_top = tg.box("anvil_top", (0.7, 0.3, 0.14), (-0.05, 0.1, -0.33), "iron", bevel=0.03, bevel_seg=2)
    horn = tg.cylinder("horn", 0.07, 0.0, 0.25, (-0.52, 0.1, -0.33), "iron", verts=10, rot=(0, -90, 0))
    anvil_body = tg.box("anvil_body", (0.34, 0.24, 0.2), (-0.05, 0.1, -0.5), "iron", bevel=0.02, bevel_seg=1)
    return tg.join([hammer, anvil_top, horn, anvil_body], "Forge")


def arc(name, radius, minor, start_deg, end_deg, mat, loc=(0, 0, 0)):
    """Tube along part of a circle in the XZ plane (facing -Y); angles from +X towards +Z."""
    obj = tg.torus(name, radius, minor, (0, 0, 0), mat, seg=48, minor_seg=8, rot=(90, 0, 0))
    tg.apply_all_transforms(obj)
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    doomed = [v for v in bm.verts
              if not start_deg <= math.degrees(math.atan2(v.co.z, v.co.x)) % 360 <= end_deg]
    bmesh.ops.delete(bm, geom=doomed, context="VERTS")
    bm.to_mesh(obj.data)
    bm.free()
    obj.location = loc
    tg.apply_all_transforms(obj)
    return obj


def icon_wood():
    """Three logs with light cut ends and rings."""
    parts = []
    for i, (x, z) in enumerate([(-0.27, -0.2), (0.27, -0.2), (0.0, 0.25)]):
        log = tg.cylinder(f"log{i}", 0.24, 0.24, 0.8, (x, 0.4, z), "wood", verts=14, rot=(90, 0, 0))
        cut = tg.cylinder(f"cut{i}", 0.21, 0.21, 0.03, (x, -0.41, z), "wood_light", verts=14, rot=(90, 0, 0))
        ring = tg.torus(f"ring{i}", 0.11, 0.018, (x, -0.43, z), "wood", seg=16, minor_seg=4, rot=(90, 0, 0))
        parts += [log, cut, ring]
    leaf = tg.sphere("leaf", (0.13, 0.05, 0.08), (0.2, -0.1, 0.5), "leaf", seg=10, rings=5, rot=(0, -30, 0))
    return tg.join(parts + [leaf], "Wood")


def icon_axe():
    """Woodcutter's axe: wooden handle, steel blade."""
    handle = tg.cylinder("handle", 0.05, 0.045, 1.1, (0, 0, -0.55), "wood", verts=10)
    blade = [(0.0, 0.16), (0.42, 0.34), (0.48, 0.0), (0.42, -0.34), (0.0, -0.12)]
    head = extrude_outline("blade", blade, 0.08, "steel", bevel=0.02, subsurf=0)
    head.location = (0.04, 0, 0.38)
    tg.apply_all_transforms(head)
    poll = tg.box("poll", (0.16, 0.14, 0.26), (-0.03, 0, 0.4), "iron", bevel=0.03, bevel_seg=2)
    grip = tg.cylinder("grip", 0.06, 0.06, 0.22, (0, 0, -0.52), "leather", verts=10)
    axe = tg.join([handle, head, poll, grip], "Axe")
    axe.rotation_euler = (0, math.radians(-30), 0)
    tg.apply_all_transforms(axe)
    return axe


def icon_sell():
    """Coin stack with a flying coin: sell for gold."""
    parts = [tg.cylinder(f"c{i}", 0.34, 0.34, 0.09, (-0.12 + 0.02 * (i % 2), 0, -0.45 + i * 0.1), "gold", verts=28)
             for i in range(4)]
    flying = icon_coin()
    flying.scale = (0.55, 0.55, 0.55)
    flying.rotation_euler = (0, math.radians(-20), 0)
    flying.location = (0.28, -0.05, 0.25)
    tg.apply_all_transforms(flying)
    return tg.join(parts + [flying], "Sell")


def icon_pause():
    a = tg.box("a", (0.22, 0.2, 0.85), (-0.2, 0, 0), "cream", bevel=0.07, bevel_seg=3)
    b = tg.box("b", (0.22, 0.2, 0.85), (0.2, 0, 0), "cream", bevel=0.07, bevel_seg=3)
    return tg.join([a, b], "Pause")


def _triangle(name, size, mat, x=0.0):
    pts = [(-size * 0.45, size * 0.55), (size * 0.6, 0.0), (-size * 0.45, -size * 0.55)]
    obj = extrude_outline(name, pts, 0.22, mat, bevel=0.06, subsurf=0)
    obj.location = (x, 0, 0)
    tg.apply_all_transforms(obj)
    return obj


def icon_play():
    return _triangle("Play", 1.0, "go")


def icon_speed():
    return tg.join([_triangle("a", 0.75, "cream", -0.24), _triangle("b", 0.75, "cream", 0.26)], "Speed")


def icon_restart():
    """Circular arrow."""
    ring = arc("ring", 0.4, 0.09, 40, 330, "go")
    head = _triangle("head", 0.42, "go")
    head.rotation_euler = (0, math.radians(-125), 0)
    head.location = (0.33, 0, 0.27)
    tg.apply_all_transforms(head)
    return tg.join([ring, head], "Restart")


def _speaker():
    body = tg.box("body", (0.22, 0.24, 0.32), (-0.32, 0, 0), "iron", bevel=0.04, bevel_seg=2)
    cone = tg.cylinder("cone", 0.12, 0.36, 0.3, (-0.21, 0, 0), "iron_dark", verts=16, rot=(0, 90, 0))
    return [body, cone]


def icon_sound_on():
    parts = _speaker()
    parts.append(arc("w1", 0.22, 0.045, 0, 50, "cream", (0.1, 0, 0)))
    parts.append(arc("w1b", 0.22, 0.045, 310, 360, "cream", (0.1, 0, 0)))
    parts.append(arc("w2", 0.4, 0.045, 0, 50, "cream", (0.1, 0, 0)))
    parts.append(arc("w2b", 0.4, 0.045, 310, 360, "cream", (0.1, 0, 0)))
    return tg.join(parts, "SoundOn")


def icon_sound_off():
    parts = _speaker()
    parts.append(tg.box("x1", (0.09, 0.1, 0.5), (0.3, 0, 0), "ruby", bevel=0.03, bevel_seg=2, rot=(0, 45, 0)))
    parts.append(tg.box("x2", (0.09, 0.1, 0.5), (0.3, 0, 0), "ruby", bevel=0.03, bevel_seg=2, rot=(0, -45, 0)))
    return tg.join(parts, "SoundOff")


def icon_chest():
    """Treasure chest with gold bands, slightly open, coins inside."""
    base = tg.box("base", (0.9, 0.55, 0.42), (0, 0, -0.2), "wood", bevel=0.03, bevel_seg=2)
    lid = tg.cylinder("lid", 0.275, 0.275, 0.9, (-0.45, 0, 0.01), "wood_light", verts=16, rot=(0, 90, 0))
    tg.deform(lid, lambda c: Vector((c.x, c.y, max(c.z, 0.01))))
    lid.rotation_euler = (math.radians(-25), 0, 0)
    lid.location = (0, 0.2, 0.06)
    tg.apply_all_transforms(lid)
    parts = [base, lid]
    for x in (-0.3, 0.3):
        parts.append(tg.box(f"band{x}", (0.08, 0.57, 0.44), (x, 0, -0.2), "gold"))
    parts.append(tg.box("lock", (0.14, 0.06, 0.16), (0, -0.29, -0.06), "gold", bevel=0.02, bevel_seg=1))
    for i, (x, z) in enumerate([(-0.18, 0.04), (0.05, 0.07), (0.22, 0.03), (-0.04, 0.12)]):
        parts.append(tg.cylinder(f"coin{i}", 0.1, 0.1, 0.03, (x, -0.05, z), "gold", verts=14, rot=(70, 0, 20 * i)))
    parts.append(tg.sphere("gem", (0.08, 0.08, 0.08), (0.12, -0.12, 0.13), "ruby", seg=10, rings=5))
    return tg.join(parts, "Chest")


def icon_map():
    """Parchment map with a dotted route and a red cross."""
    sheet = tg.box("sheet", (0.95, 0.65, 0.03), (0, 0, 0), "cream")
    tg.deform(sheet, lambda c: Vector((c.x, c.y, c.z + 0.05 * math.sin(c.x * 6.0))))
    roll_a = tg.cylinder("roll_a", 0.06, 0.06, 0.7, (-0.5, 0.35, 0.0), "path", verts=10, rot=(90, 0, 0))
    roll_b = tg.cylinder("roll_b", 0.06, 0.06, 0.7, (0.5, 0.35, 0.0), "path", verts=10, rot=(90, 0, 0))
    parts = [sheet, roll_a, roll_b]
    for i in range(6):
        x = -0.35 + i * 0.12
        y = 0.18 * math.sin(i * 1.1)
        parts.append(tg.cylinder(f"dot{i}", 0.03, 0.03, 0.02, (x, y, 0.03 + 0.05 * math.sin(x * 6.0)), "wood_dark", verts=8))
    parts.append(tg.box("x1", (0.05, 0.22, 0.03), (0.33, 0.05, 0.06), "ruby", rot=(0, 0, 45)))
    parts.append(tg.box("x2", (0.05, 0.22, 0.03), (0.33, 0.05, 0.06), "ruby", rot=(0, 0, -45)))
    m = tg.join(parts, "Map")
    m.rotation_euler = (math.radians(70), 0, 0)
    tg.apply_all_transforms(m)
    return m


ICONS = {"wood": icon_wood, "axe": icon_axe, "sell": icon_sell, "pause": icon_pause, "play": icon_play,
         "speed": icon_speed, "restart": icon_restart, "sound_on": icon_sound_on, "sound_off": icon_sound_off,
         "chest": icon_chest, "map": icon_map,
         "hammer": icon_hammer, "whirl": icon_whirl, "coin": icon_coin, "heart": icon_heart, "sword": icon_sword, "crown": icon_crown,
         "hourglass": icon_hourglass, "flag": icon_flag, "upgrade": icon_upgrade, "lock": icon_lock,
         "star": icon_star, "cancel": icon_cancel}


def build() -> list:
    out = []
    for name, fn in ICONS.items():
        _clear()
        out.append(tg.finish_asset(f"icon_{name}", fn(), ao_distance=0.15, ao_strength=0.5, ground=False))
    return out

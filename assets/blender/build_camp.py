"""Lumberjack camp: open timber lodge with a shingled gable roof, firewood stack,
chopping stump with an axe and a woodcutters' banner. One mesh (one draw call).

camp_lumber.glb: front faces -Y (Godot +Z), pivot at the centre of the deck floor.
Footprint matches the old procedural camp (scripts/camp_structures.gd): deck 2.5 x 1.9 m,
posts at x = -1.05 / 0 / 1.05, y = +-0.75, roof ridge at 2.05 m, stump at (0.9, -1.05).
"""
import math
import random

import bmesh
import bpy
from mathutils import Vector

import tg_common as tg

POST_X = (-1.05, 0.0, 1.05)
POST_Y = 0.75
BEAM_Z = 1.65
RIDGE_Z = 2.05


def log(name, length, r, loc, rot, mat="wood_dark", verts=8, caps=True):
    """Round log along its local Z (rotated by rot), with light end-grain caps."""
    parts = [tg.cylinder(name, r, r * 0.94, length, (0, 0, -length / 2), mat, verts=verts)]
    if caps:
        for k, z in enumerate((-length / 2 - 0.004, length / 2 - 0.004)):
            parts.append(tg.cylinder(f"{name}_cap{k}", r * 0.82, r * 0.82, 0.008, (0, 0, z), "wood_light",
                                     verts=verts))
    obj = tg.join(parts, name)
    tg.pivot(obj, (0, 0, 0))
    obj.rotation_euler = [math.radians(a) for a in rot]
    obj.location = loc
    tg.apply_all_transforms(obj)
    return obj


def build_frame(parts):
    # Plank deck on two sleepers.
    n = 7
    w = 2.5 / n
    for i in range(n):
        x = -1.25 + w * (i + 0.5)
        parts.append(tg.box(f"plank{i}", (w - 0.02, 1.9, 0.06), (x, 0, 0.07), "wood" if i % 2 else "wood_light",
                            bevel=0.012, bevel_seg=1))
    for y in (-0.7, 0.7):
        parts.append(tg.box(f"sleeper{y}", (2.6, 0.14, 0.06), (0, y, 0.025), "wood_dark", bevel=0.015, bevel_seg=1))
    # Posts on stone footings, rough log beams, knee braces.
    for x in POST_X:
        for sy in (-1, 1):
            y = POST_Y * sy
            parts.append(tg.cylinder(f"post{x}{sy}", 0.085, 0.072, BEAM_Z - 0.1, (x, y, 0.1), "wood_dark", verts=8))
            parts.append(tg.cylinder(f"footing{x}{sy}", 0.13, 0.11, 0.1, (x, y, 0.0), "stone_dark", verts=6))
    for sy in (-1, 1):
        parts.append(log(f"beam_x{sy}", 2.45, 0.07, (0, POST_Y * sy, BEAM_Z), (0, 90, 0), caps=True))
        for x, d in ((-1.05, 1), (1.05, -1), (0.0, 1), (0.0, -1)):
            brace = tg.box(f"brace{x}{sy}{d}", (0.05, 0.05, 0.42), (x + 0.15 * d, POST_Y * sy, BEAM_Z - 0.17),
                           "wood", bevel=0.01, bevel_seg=1, rot=(0, 45 * d, 0))
            parts.append(brace)
    for x in (-1.05, 1.05):
        parts.append(tg.box(f"tie{x}", (0.1, 1.62, 0.1), (x, 0, BEAM_Z), "wood_dark", bevel=0.02, bevel_seg=1))
        parts.append(tg.box(f"king{x}", (0.08, 0.08, RIDGE_Z - BEAM_Z), (x, 0, (BEAM_Z + RIDGE_Z) / 2), "wood_dark",
                            bevel=0.012, bevel_seg=1))
    parts.append(log("ridge", 2.75, 0.065, (0, 0, RIDGE_Z + 0.02), (0, 90, 0)))


def build_roof(parts, rng):
    """Two pitched planes of overlapping wooden shingle rows with bargeboards at the gables."""
    pitch = math.atan2(RIDGE_Z - BEAM_Z + 0.08, POST_Y + 0.2)
    rows = 4
    slope_len = math.hypot(POST_Y + 0.25, RIDGE_Z - BEAM_Z + 0.1)
    for sy in (-1, 1):
        for r in range(rows):
            u = (r + 0.5) / rows  # 0 at the ridge, 1 at the eave
            y = sy * u * (POST_Y + 0.25)
            z = RIDGE_Z + 0.1 - u * (RIDGE_Z - BEAM_Z + 0.1)
            mat = ("wood_light", "wood")[r % 2]
            row = tg.box(f"shingle{sy}{r}", (2.8, slope_len / rows + 0.06, 0.045), (0, 0, 0), mat,
                         bevel=0.012, bevel_seg=1)
            # Ragged lower edge: a little sag towards the ends of each row.
            tg.deform(row, lambda c: Vector((c.x, c.y, c.z - 0.012 * (c.x / 1.4) ** 2)))
            row.rotation_euler = (-sy * pitch + math.radians(rng.uniform(-1.0, 1.0)), 0, 0)
            row.location = (rng.uniform(-0.02, 0.02), y, z + 0.04)
            tg.apply_all_transforms(row)
            parts.append(row)
        for x in (-1.42, 1.42):
            bb = tg.box(f"barge{sy}{x}", (0.05, slope_len + 0.1, 0.09), (0, 0, 0), "wood_dark", bevel=0.012,
                        bevel_seg=1)
            bb.rotation_euler = (-sy * pitch, 0, 0)
            bb.location = (x, sy * (POST_Y + 0.25) / 2, (RIDGE_Z + BEAM_Z) / 2 + 0.08)
            tg.apply_all_transforms(bb)
            parts.append(bb)


def build_banner(parts):
    """Green woodcutters' banner with a cream axe emblem, hanging from the front beam."""
    x, y = -0.6, -POST_Y - 0.09
    cols = 4
    pts, faces = [], []
    for i in range(cols + 1):
        u = i / cols
        xx = x - 0.21 + 0.42 * u
        wave = 0.012 * math.sin(u * math.pi * 2)
        bottom = BEAM_Z - 0.68 + 0.1 * abs(u - 0.5) * 2  # swallow-tail notch
        pts += [(xx, y + wave, BEAM_Z - 0.04), (xx, y + wave, bottom)]
    for i in range(cols):
        a = i * 2
        faces.append((a, a + 1, a + 3, a + 2))
    cloth = tg.from_pydata("banner", pts, faces, "pine")
    tg.add_solidify(cloth, 0.015)
    rod = tg.cylinder("banner_rod", 0.014, 0.014, 0.52, (x - 0.26, y, BEAM_Z - 0.04), "wood_dark", verts=6,
                      rot=(0, 90, 0))
    handle = tg.box("emblem_handle", (0.035, 0.012, 0.3), (x + 0.02, y - 0.012, BEAM_Z - 0.34), "cream",
                    rot=(0, 25, 0))
    blade = tg.box("emblem_blade", (0.12, 0.012, 0.09), (x - 0.04, y - 0.014, BEAM_Z - 0.22), "cream",
                   bevel=0.02, bevel_seg=1, rot=(0, 25, 0))
    parts += [cloth, rod, handle, blade]


def build_firewood(parts):
    """Stack of split logs under the roof (back left), end grain towards the camera."""
    cx, cy = -0.35, 0.22
    k = 0
    for row, count in enumerate((4, 3, 2)):
        for i in range(count):
            x = cx + (i - (count - 1) / 2) * 0.17
            z = 0.18 + row * 0.145
            parts.append(log(f"fw{k}", 0.8, 0.078, (x, cy, z), (90, 0, 0), mat="wood", verts=7))
            k += 1
    for sx in (-1, 1):
        parts.append(tg.box(f"stake{sx}", (0.04, 0.04, 0.5), (cx + sx * 0.4, cy - 0.38, 0.33), "wood_dark",
                            bevel=0.008, bevel_seg=1))
        parts.append(tg.box(f"stake_b{sx}", (0.04, 0.04, 0.5), (cx + sx * 0.4, cy + 0.38, 0.33), "wood_dark",
                            bevel=0.008, bevel_seg=1))


def build_stump(parts, rng):
    """Chopping block with roots, an axe bitten into it and a few chips around."""
    sx, sy = 0.9, -1.05
    parts.append(tg.lathe("block", [(0.26, 0.0), (0.21, 0.05), (0.19, 0.12), (0.185, 0.3), (0.175, 0.32)],
                          "wood", steps=12, loc=(sx, sy, 0)))
    parts.append(tg.cylinder("block_top", 0.165, 0.165, 0.012, (sx, sy, 0.315), "wood_light", verts=12))
    parts.append(tg.torus("block_ring", 0.1, 0.007, (sx, sy, 0.327), "wood", seg=12, minor_seg=3))
    for i, a in enumerate((0.5, 2.6, 4.4)):
        parts.append(tg.cylinder(f"root{i}", 0.05, 0.0, 0.2, (sx + 0.17 * math.cos(a), sy + 0.17 * math.sin(a), 0.0),
                                 "wood", verts=5, rot=(0, 72, math.degrees(a))))
    # Axe: handle leaning back-right, steel head bitten into the top of the block.
    hx, hy, hz = sx - 0.02, sy, 0.36
    handle = tg.cylinder("axe_handle", 0.022, 0.018, 0.55, (0, 0, 0), "wood_light", verts=6)
    handle.rotation_euler = (math.radians(-12), math.radians(38), 0)
    handle.location = (hx, hy, hz - 0.03)
    tg.apply_all_transforms(handle)
    head_pts = [(-0.02, -0.012, 0.0), (0.02, -0.012, 0.0), (0.02, -0.012, 0.06), (-0.02, -0.012, 0.06),
                (-0.03, -0.004, -0.1), (0.04, -0.004, -0.1)]
    verts = [(x, y, z) for x, y, z in head_pts] + [(x, -y, z) for x, y, z in head_pts]
    faces = [(0, 1, 2, 3), (6, 9, 8, 7), (0, 4, 5, 1), (6, 7, 11, 10), (4, 10, 11, 5), (0, 3, 9, 6),
             (1, 7, 8, 2), (2, 8, 9, 3), (0, 6, 10, 4), (1, 5, 11, 7)]
    head = tg.from_pydata("axe_head", verts, faces, "steel", smooth=False)
    bm = bmesh.new()
    bm.from_mesh(head.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(head.data)
    bm.free()
    head.scale = (1.6, 1.6, 1.6)
    head.rotation_euler = (0, math.radians(38), math.radians(90))
    head.location = (hx - 0.01, hy, hz + 0.03)
    tg.apply_all_transforms(head)
    parts += [handle, head]
    for i in range(5):
        a = rng.uniform(0, 2 * math.pi)
        d = rng.uniform(0.3, 0.5)
        parts.append(tg.box(f"chip{i}", (0.06, 0.03, 0.012), (sx + d * math.cos(a), sy + d * math.sin(a), 0.006),
                            "wood_light", rot=(0, 0, rng.uniform(0, 180))))
    # A spare log waiting by the block.
    parts.append(log("spare", 0.55, 0.085, (sx - 0.5, sy - 0.05, 0.085), (90, 0, 70), mat="wood", verts=8))


def build() -> dict:
    rng = random.Random(5)
    tg.MAX_BEVEL_SEG = 1
    parts = []
    build_frame(parts)
    build_roof(parts, rng)
    build_banner(parts)
    build_firewood(parts)
    build_stump(parts, rng)
    camp = tg.join(parts, "LogCanopy")
    out = tg.finish_asset("camp_lumber", camp, ao_distance=0.3, ao_strength=0.7)
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    return out

"""Cute but mischievous slime enemy (~0.5 m). Faces -Y.

slime.glb: Slime (empty) -> Body (one mesh incl. face). Animation: idle (hop).
"""
from mathutils import Vector

import tg_common as tg

C = Vector((0, 0, 0.21))
R = Vector((0.25, 0.23, 0.21))


def build() -> dict:
    body = tg.sphere("blob", (R.x * 2, R.y * 2, R.z * 2), C, "slime", seg=28, rings=14)

    def shape(v: Vector) -> Vector:
        # v is relative to the centre. Heavier, gooey base below the face; flat sole.
        t = max(0.0, (-0.08 - v.z) / 0.13)
        bulge = 1.0 + 0.16 * t * t
        z = v.z if v.z > -0.18 else -0.18 + (v.z + 0.18) * 0.2
        return Vector((v.x * bulge, v.y * bulge, z))
    tg.deform(body, shape)

    def on_body(x, z, lift):
        return tg.surface_y(body, x, z, lift)

    drip = tg.sphere("drip", (0.09, 0.09, 0.13), (0.02, 0.01, 0.43), "slime", seg=14, rings=8, rot=(0, 18, 0))
    shine = tg.sphere("shine", (0.11, 0.035, 0.06), (-0.11, on_body(-0.11, 0.34, -0.012), 0.34), "slime_light",
                      seg=12, rings=6, rot=(20, 0, 35))
    shine2 = tg.sphere("shine2", (0.035, 0.02, 0.03), (-0.04, on_body(-0.04, 0.38, -0.006), 0.38), "slime_light",
                       seg=8, rings=4)
    parts = [drip, shine, shine2]
    for sx in (-1, 1):
        ex, ez = 0.088 * sx, 0.235
        ey = on_body(ex, ez, -0.012)
        eye = tg.sphere(f"eye{sx}", (0.1, 0.045, 0.13), (ex, ey, ez), "eye", seg=14, rings=8)
        hl = tg.sphere(f"hl{sx}", (0.036, 0.012, 0.036), (ex + 0.022, ey - 0.024, ez + 0.035), "white", seg=8, rings=4)
        # Brows tilted down towards the middle: cute, but up to no good.
        bx, bz = 0.09 * sx, 0.33
        brow = tg.sphere(f"brow{sx}", (0.08, 0.022, 0.024), (bx, on_body(bx, bz, 0.004), bz), "eye",
                         seg=10, rings=4, rot=(0, 24 * sx, 0))
        parts += [eye, hl, brow]
    mouth = tg.sphere("mouth", (0.07, 0.02, 0.034), (0, on_body(0, 0.145, 0.006), 0.145), "mouth", seg=12, rings=6)
    tg.deform(mouth, lambda v: Vector((v.x, v.y, v.z + 5.0 * v.x * v.x)))  # grin
    fang = tg.cylinder("fang", 0.013, 0.0, 0.028, (0.022, on_body(0.022, 0.14, 0.012), 0.145), "white", verts=6,
                       rot=(180, 0, 0))
    parts += [mouth, fang]
    slime_body = tg.join([body] + parts, "Body")
    tg.pivot(slime_body, (0, 0, 0))
    root = tg.empty("Slime")
    tg.parent(slime_body, root)
    tg.make_track("idle", {
        slime_body: [(0, {}), (8, {"scale": (1.1, 1.1, 0.86)}), (16, {"scale": (0.93, 0.93, 1.13), "loc": (0, 0, 0.05)}),
                     (24, {"scale": (1.04, 1.04, 0.96)}), (32, {})],
    }, 32)
    return tg.finish_asset("slime", root, ao_distance=0.1, ao_strength=0.65)

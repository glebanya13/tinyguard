"""Slime enemies: regular, fast, tank and the King Slime boss. All face -Y.

slime*.glb: Slime (empty) -> Body (one mesh incl. face and gear). Animation: idle.
"""
import math

from mathutils import Vector

import tg_common as tg

VARIANTS = {
    # name: body colour, dark, radii (x, y, z), brow angle, extras, hop height
    "slime": dict(col="slime", dark="slime_dark", r=(0.25, 0.23, 0.21), brow=24, extra=None, hop=0.05),
    "slime_fast": dict(col="slime_fast", dark="slime_fast_dark", r=(0.19, 0.18, 0.24), brow=30, extra="fast", hop=0.07),
    "slime_tank": dict(col="slime_tank", dark="slime_tank_dark", r=(0.33, 0.3, 0.25), brow=18, extra="helmet", hop=0.03),
    "slime_king": dict(col="king", dark="king_dark", r=(0.48, 0.44, 0.4), brow=32, extra="crown", hop=0.04),
}


def build_variant(name: str, v: dict):
    R = Vector(v["r"])
    C = Vector((0, 0, R.z))
    body = tg.sphere("blob", (R.x * 2, R.y * 2, R.z * 2), C, v["col"], seg=28, rings=14)
    lower = -0.85 * R.z

    def shape(p: Vector) -> Vector:
        # p is relative to the centre. Heavier, gooey base below the face; flat sole.
        t = max(0.0, (-0.38 * R.z - p.z) / (0.62 * R.z))
        bulge = 1.0 + 0.16 * t * t
        z = p.z if p.z > lower else lower + (p.z - lower) * 0.2
        if v["extra"] == "fast":  # teardrop leaning back, like it is dashing
            z += 0.0
            return Vector((p.x * bulge, p.y * bulge + 0.12 * max(0.0, p.z / R.z) ** 2 * R.y, z))
        return Vector((p.x * bulge, p.y * bulge, z))
    tg.deform(body, shape)

    def on_body(x, z, lift):
        return tg.surface_y(body, x, z, lift)

    s = R.z / 0.21  # feature scale relative to the regular slime
    parts = []
    if v["extra"] in (None, "fast"):
        parts.append(tg.sphere("drip", (0.09 * s, 0.09 * s, 0.13 * s), (0.02, 0.01 + (0.06 if v["extra"] else 0),
                                                                          2 * R.z + 0.01), v["col"], seg=14, rings=8,
                               rot=(-25 if v["extra"] else 0, 18, 0)))
    sz = C.z + 0.62 * R.z
    parts.append(tg.sphere("shine", (0.11 * s, 0.035 * s, 0.06 * s), (-0.44 * R.x, on_body(-0.44 * R.x, sz, -0.012 * s), sz),
                           "slime_light", seg=12, rings=6, rot=(20, 0, 35)))
    ez = C.z + 0.12 * R.z
    for sx in (-1, 1):
        ex = 0.35 * R.x * sx
        ey = on_body(ex, ez, -0.012 * s)
        parts.append(tg.sphere(f"eye{sx}", (0.1 * s, 0.045 * s, 0.13 * s), (ex, ey, ez), "eye", seg=14, rings=8))
        parts.append(tg.sphere(f"hl{sx}", (0.036 * s, 0.012 * s, 0.036 * s), (ex + 0.022 * s, ey - 0.024 * s, ez + 0.035 * s),
                               "white", seg=8, rings=4))
        bz = ez + 0.095 * s
        bx = 0.36 * R.x * sx
        parts.append(tg.sphere(f"brow{sx}", (0.08 * s, 0.022 * s, 0.024 * s), (bx, on_body(bx, bz, 0.004 * s), bz), "eye",
                               seg=10, rings=4, rot=(0, v["brow"] * sx, 0)))
    mz = C.z - 0.31 * R.z
    mouth = tg.sphere("mouth", (0.07 * s, 0.02 * s, 0.034 * s), (0, on_body(0, mz, 0.006 * s), mz), "mouth", seg=12, rings=6)
    tg.deform(mouth, lambda p: Vector((p.x, p.y, p.z + 5.0 / s * p.x * p.x)))  # grin
    parts.append(mouth)
    for fx in ((0.022,) if v["extra"] != "crown" else (-0.03, 0.03)):
        parts.append(tg.cylinder("fang", 0.013 * s, 0.0, 0.028 * s, (fx * s, on_body(fx * s, mz - 0.005, 0.012 * s),
                                                                        mz), "white", verts=6, rot=(180, 0, 0)))
    if v["extra"] == "helmet":
        top = 2 * R.z
        hz = top - 0.17  # helmet rim height, just above the brows
        helm = tg.sphere("helmet", (R.x * 1.72, R.y * 1.72, 0.44), (0, 0.0, hz), "iron", seg=20, rings=10)
        tg.deform(helm, lambda p: Vector((p.x, p.y, max(p.z, -0.005))))
        rim = tg.torus("helm_rim", R.x * 0.86, 0.026, (0, 0.0, hz), "iron_dark", seg=24, minor_seg=6,
                       scale=(1, R.y / R.x, 1))
        visor = tg.box("visor", (0.06, 0.05, 0.12), (0, on_body(0, hz + 0.02, 0.03), hz + 0.03), "iron_dark",
                       bevel=0.015, bevel_seg=1)
        horns = [tg.cylinder(f"horn{sx}", 0.045, 0.0, 0.18, (0.25 * sx, 0.0, hz + 0.12), "cream", verts=8,
                             rot=(0, -40 * sx, 0)) for sx in (-1, 1)]
        parts.append(visor)
        parts += [helm, rim, *horns]
    if v["extra"] == "crown":
        top = 2 * R.z
        band = tg.cylinder("crown_band", 0.2, 0.22, 0.1, (0, 0.04, top - 0.07), "gold", verts=16)
        spikes = []
        for i in range(6):
            a = 2 * math.pi * i / 6
            x, y = 0.2 * math.cos(a), 0.04 + 0.2 * math.sin(a)
            spikes.append(tg.cylinder(f"spike{i}", 0.05, 0.0, 0.13, (x, y, top + 0.02), "gold", verts=6))
            spikes.append(tg.sphere(f"tip{i}", (0.035, 0.035, 0.035), (x, y, top + 0.15), "gold", seg=8, rings=4))
        gems = [tg.sphere(f"gem{i}", (0.05, 0.03, 0.05), (0.2 * math.cos(a), 0.04 + 0.2 * math.sin(a) - 0.01, top - 0.02),
                          "ruby", seg=8, rings=4) for i, a in enumerate([-math.pi / 2, -math.pi / 2 - 0.9,
                                                                         -math.pi / 2 + 0.9])]
        cape = tg.sphere("mantle", (R.x * 2.1, R.y * 1.6, 0.16), (0, 0.18, 0.14), v["dark"], seg=20, rings=8)
        tg.deform(cape, lambda p: Vector((p.x, max(p.y, -0.02), p.z)))
        parts += [band, *spikes, *gems, cape]
    slime_body = tg.join([body] + parts, "Body")
    tg.pivot(slime_body, (0, 0, 0))
    root = tg.empty("Slime")
    tg.parent(slime_body, root)
    hop = v["hop"]
    tg.make_track("idle", {
        slime_body: [(0, {}), (8, {"scale": (1.1, 1.1, 0.86)}), (16, {"scale": (0.93, 0.93, 1.13), "loc": (0, 0, hop)}),
                     (24, {"scale": (1.04, 1.04, 0.96)}), (32, {})],
    }, 32)
    return tg.finish_asset(name, root, ao_distance=0.1 * s, ao_strength=0.65)


def build() -> list:
    import bpy
    out = []
    for name, v in VARIANTS.items():
        for o in list(bpy.data.objects):
            bpy.data.objects.remove(o, do_unlink=True)
        out.append(build_variant(name, v))
    return out

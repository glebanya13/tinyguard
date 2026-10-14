"""Villager: friendly peasant with a straw hat and a sack on the back (~1.0 m,
a head shorter than the knight). Faces -Y. The player sells wood to villagers.

villager.glb: Villager (empty) -> LegL, LegR, Body (with the sack) -> Head, ArmL, ArmR.
Six meshes only: every part is a draw call.
Animations: idle, walk, wave (greets the knight while trading).
"""
import math

from mathutils import Vector

import tg_common as tg

HEAD_C = Vector((0, 0, 0.74))
HEAD_R = Vector((0.17, 0.155, 0.16))


def head_front_y(x: float, z: float, lift: float = 0.0) -> float:
    """y of the head surface (front, -Y side) at (x, z), pushed out by lift."""
    k = 1 - (x / HEAD_R.x) ** 2 - ((z - HEAD_C.z) / HEAD_R.z) ** 2
    return -HEAD_R.y * math.sqrt(max(k, 0.0)) - lift


def build_legs():
    legs = []
    for sx in (-1, 1):
        x = 0.07 * sx
        boot = tg.sphere(f"boot{sx}", (0.11, 0.16, 0.09), (x, -0.02, 0.045), "leather", seg=8, rings=4)
        tg.deform(boot, lambda c: Vector((c.x, c.y, max(c.z, -0.04))))  # flat sole
        leg = tg.cylinder(f"leg{sx}", 0.048, 0.052, 0.17, (x, 0, 0.06), "wood", verts=8)
        part = tg.join([boot, leg], "LegR" if sx < 0 else "LegL")
        tg.pivot(part, (x, 0, 0.23))
        legs.append(part)
    return legs


def build_body():
    tunic = tg.lathe("tunic", [(0.17, 0.17), (0.165, 0.24), (0.15, 0.36), (0.13, 0.45), (0.07, 0.54)],
                     "leaf_dark", steps=12)
    tg.deform(tunic, lambda c: Vector((c.x, c.y * 0.85, c.z)))
    belt = tg.torus("belt", 0.152, 0.018, (0, 0, 0.29), "leather", seg=12, minor_seg=3, scale=(1, 0.86, 1))
    buckle = tg.box("buckle", (0.045, 0.02, 0.035), (0, -0.132, 0.29), "wood_light", bevel=0.006)
    collar = tg.torus("collar", 0.075, 0.016, (0, 0, 0.53), "cream", seg=10, minor_seg=3)
    neck = tg.cylinder("neck", 0.045, 0.042, 0.06, (0, 0, 0.53), "skin", verts=8)
    body = tg.join([tunic, belt, buckle, collar, neck, *build_sack()], "Body")
    tg.pivot(body, (0, 0, 0.24))
    return body


def build_head():
    c = HEAD_C
    head = tg.sphere("skull", (HEAD_R.x * 2, HEAD_R.y * 2, HEAD_R.z * 2), c, "skin", seg=14, rings=7)
    parts = [head]
    for sx in (-1, 1):
        ex, ez = 0.062 * sx, 0.735
        eye = tg.sphere(f"eye{sx}", (0.05, 0.03, 0.07), (ex, head_front_y(ex, ez) + 0.012, ez), "eye",
                        seg=8, rings=4)
        hl = tg.sphere(f"hl{sx}", (0.018, 0.01, 0.018), (ex + 0.012, head_front_y(ex, ez) - 0.003, ez + 0.018),
                       "white", seg=6, rings=3)
        cx, cz = 0.105 * sx, 0.69
        cheek = tg.sphere(f"blush{sx}", (0.045, 0.014, 0.024), (cx, head_front_y(cx, cz) + 0.005, cz), "blush",
                          seg=8, rings=3)
        ear = tg.sphere(f"ear{sx}", (0.04, 0.035, 0.06), (0.165 * sx, 0.01, 0.73), "skin", seg=8, rings=4)
        parts += [eye, hl, cheek, ear]
    nose = tg.sphere("nose", (0.036, 0.03, 0.03), (0, head_front_y(0, 0.705) + 0.006, 0.705), "blush", seg=8, rings=4)
    mouth = tg.sphere("mouth", (0.04, 0.012, 0.016), (0, head_front_y(0, 0.665) + 0.004, 0.665), "mouth",
                      seg=8, rings=3)
    tg.deform(mouth, lambda v: Vector((v.x, v.y, v.z + 7.0 * v.x * v.x)))  # smile
    hair = tg.sphere("hair", (0.36, 0.33, 0.2), (0, 0.035, 0.77), "hair", seg=10, rings=5)
    beard = tg.sphere("beard", (0.2, 0.1, 0.09), (0, head_front_y(0, 0.63) + 0.04, 0.63), "hair", seg=8, rings=4)
    parts += [nose, mouth, hair, beard]

    # Wide straw hat: flat brim and a rounded cone, with a cloth band.
    hat = tg.lathe("hat", [(0.30, 0.83), (0.31, 0.845), (0.15, 0.86), (0.12, 0.93), (0.05, 0.975), (0.0, 0.98)],
                   "flower_yellow", steps=12)
    band = tg.torus("hat_band", 0.135, 0.016, (0, 0, 0.87), "berry", seg=12, minor_seg=3)
    parts += [hat, band]
    head_obj = tg.join(parts, "Head")
    tg.pivot(head_obj, (0, 0, 0.56))
    return head_obj


def build_arm(side: int):
    """side -1 = villager's right (-X), +1 = left (+X)."""
    sx = side
    sleeve = tg.sphere("sleeve", (0.085, 0.085, 0.2), (0.175 * sx, 0, 0.42), "leaf_dark", seg=8, rings=5,
                       rot=(0, -10 * sx, 0))
    cuff = tg.torus("cuff", 0.036, 0.01, (0.19 * sx, 0, 0.33), "cream", seg=8, minor_seg=3)
    hand = tg.sphere("hand", (0.07, 0.07, 0.07), (0.192 * sx, -0.005, 0.3), "skin", seg=8, rings=4)
    arm = tg.join([sleeve, cuff, hand], "ArmR" if side < 0 else "ArmL")
    tg.pivot(arm, (0.15 * sx, 0, 0.5))
    return arm


def build_sack():
    """Sack for the wood the villager buys, slung over the back (part of the Body mesh)."""
    sack = tg.sphere("sack", (0.2, 0.14, 0.22), (0.02, 0.15, 0.38), "path", seg=8, rings=5)
    tg.deform(sack, lambda v: Vector((v.x, v.y, v.z + 0.25 * (v.x * v.x + v.y * v.y))))
    tie = tg.torus("tie", 0.04, 0.012, (0.02, 0.15, 0.49), "leather", seg=8, minor_seg=3)
    strap = tg.torus("strap", 0.17, 0.012, (0, 0.02, 0.38), "leather", seg=12, minor_seg=3, rot=(0, 35, 0),
                     scale=(1, 0.75, 1))
    return [sack, tie, strap]


def idle(body, head, arm_l, arm_r) -> None:
    tg.make_track("idle", {
        body: [(0, {}), (24, {"scale": (1.0, 1.0, 1.03)}), (48, {})],
        head: [(0, {}), (16, {"rot": (0, 0, 5)}), (32, {"rot": (-3, 0, -4)}), (48, {})],
        arm_r: [(0, {}), (24, {"rot": (-4, 0, -3)}), (48, {})],
        arm_l: [(0, {}), (24, {"rot": (4, 0, 3)}), (48, {})],
    }, 48)


def walk(body, head, arm_l, arm_r, leg_l, leg_r) -> None:
    """A slow stroll: one stride every 24 frames (1 s) at ~0.6 m/s."""
    swing = 22
    tg.make_track("walk", {
        leg_l: [(0, {"rot": (swing, 0, 0)}), (12, {"rot": (-swing, 0, 0)}), (24, {"rot": (swing, 0, 0)})],
        leg_r: [(0, {"rot": (-swing, 0, 0)}), (12, {"rot": (swing, 0, 0)}), (24, {"rot": (-swing, 0, 0)})],
        arm_l: [(0, {"rot": (-18, 0, 0)}), (12, {"rot": (18, 0, 0)}), (24, {"rot": (-18, 0, 0)})],
        arm_r: [(0, {"rot": (18, 0, 0)}), (12, {"rot": (-18, 0, 0)}), (24, {"rot": (18, 0, 0)})],
        body: [(0, {"rot": (4, 0, 0)}), (6, {"rot": (4, 0, 3), "loc": (0, 0, 0.02)}), (12, {"rot": (4, 0, 0)}),
               (18, {"rot": (4, 0, -3), "loc": (0, 0, 0.02)}), (24, {"rot": (4, 0, 0)})],
        head: [(0, {}), (6, {"rot": (-3, 0, 2)}), (12, {}), (18, {"rot": (-3, 0, -2)}), (24, {})],
    }, 24)


def wave(body, head, arm_l, arm_r) -> None:
    """Greeting: the right hand goes up and waves twice (24 frames = 1 s)."""
    up = {"rot": (0, 150, 0)}
    tg.make_track("wave", {
        arm_r: [(0, {}), (5, up), (9, {"rot": (0, 125, 0)}), (13, up), (17, {"rot": (0, 125, 0)}), (24, {})],
        head: [(0, {}), (6, {"rot": (0, 0, -6)}), (18, {"rot": (0, 0, -6)}), (24, {})],
        body: [(0, {}), (6, {"rot": (0, 0, 4)}), (18, {"rot": (0, 0, 4)}), (24, {})],
        arm_l: [(0, {}), (12, {"rot": (6, 0, 4)}), (24, {})],
    }, 24)


def build() -> dict:
    root = tg.empty("Villager")
    leg_r, leg_l = build_legs()
    body = build_body()
    head = build_head()
    arm_l = build_arm(1)
    arm_r = build_arm(-1)
    for part in (leg_l, leg_r, body):
        tg.parent(part, root)
    for part in (head, arm_l, arm_r):
        tg.parent(part, body)
    idle(body, head, arm_l, arm_r)
    walk(body, head, arm_l, arm_r, leg_l, leg_r)
    wave(body, head, arm_l, arm_r)
    return tg.finish_asset("villager", root, ao_distance=0.1, ao_strength=0.7)

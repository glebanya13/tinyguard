"""Stone golem: a slow, armoured enemy. Faces -Y.

stone_golem.glb: Golem (empty) -> Body (torso + head + legs), ArmL, ArmR.
Animation: idle (a heavy lumbering walk: body sways, arms swing).
"""
import math
import random

import tg_common as tg


def boulder(name, size, loc, mat, rng, seed):
    rock = tg.sphere(name, size, loc, mat, seg=10, rings=6)
    tg.displace_noise(rock, 0.06 * max(size), 0.9, seed=seed)
    return rock


def build() -> dict:
    rng = random.Random(7)
    root = tg.empty("Golem")
    torso = boulder("torso", (0.62, 0.48, 0.58), (0, 0, 0.62), "rock", rng, 3)
    belly = boulder("belly", (0.42, 0.3, 0.32), (0, -0.08, 0.48), "rock_dark", rng, 5)
    head = boulder("head", (0.38, 0.34, 0.3), (0, -0.06, 0.96), "rock", rng, 8)
    moss = [tg.sphere(f"moss{i}", (0.16, 0.12, 0.06), (x, y, z), "leaf_dark", seg=8, rings=4)
            for i, (x, y, z) in enumerate([(-0.14, 0.05, 1.1), (0.18, 0.1, 0.9), (0.05, 0.18, 0.95)])]
    eyes = [tg.sphere(f"eye{s}", (0.09, 0.05, 0.07), (0.08 * s, -0.2, 1.0), "portal_glow", seg=8, rings=4)
            for s in (-1, 1)]
    brow = tg.box("brow", (0.26, 0.06, 0.05), (0, -0.19, 1.05), "rock_dark", bevel=0.02, bevel_seg=1)
    legs = [boulder(f"leg{s}", (0.2, 0.22, 0.32), (0.16 * s, 0.0, 0.16), "rock_dark", rng, 11 + s) for s in (-1, 1)]
    crystals = [tg.cylinder(f"crys{i}", 0.05, 0.0, 0.16, (x, 0.18, z), "portal_glow", verts=5, rot=(-30, 0, a))
                for i, (x, z, a) in enumerate([(-0.18, 0.9, -20), (0.0, 0.98, 0), (0.2, 0.86, 25)])]
    body = tg.join([torso, belly, head, *moss, *eyes, brow, *legs, *crystals], "Body")
    tg.pivot(body, (0, 0, 0))
    tg.parent(body, root)
    arms = {}
    for s, name in ((-1, "ArmL"), (1, "ArmR")):
        upper = boulder(f"{name}_u", (0.22, 0.22, 0.36), (0.34 * s, 0, 0.64), "rock", rng, 20 + s)
        fist = boulder(f"{name}_f", (0.28, 0.26, 0.26), (0.38 * s, -0.04, 0.36), "rock_dark", rng, 30 + s)
        arm = tg.join([upper, fist], name)
        tg.pivot(arm, (0.32 * s, 0, 0.8))
        tg.parent(arm, root)
        arms[s] = arm
    tg.make_track("idle", {
        body: [(0, {"rot": (0, -4, 0)}), (12, {"rot": (0, 4, 0), "loc": (0, 0, 0.03)}), (24, {"rot": (0, -4, 0)})],
        arms[-1]: [(0, {"rot": (25, 0, 0)}), (12, {"rot": (-25, 0, 0)}), (24, {"rot": (25, 0, 0)})],
        arms[1]: [(0, {"rot": (-25, 0, 0)}), (12, {"rot": (25, 0, 0)}), (24, {"rot": (-25, 0, 0)})],
    }, 24)
    return tg.finish_asset("stone_golem", root, ao_distance=0.15, ao_strength=0.7)

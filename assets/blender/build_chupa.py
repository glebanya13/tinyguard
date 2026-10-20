"""Chupacabra enemies: regular, swift, brute (tank), chupa-bat (flying), shield bearer, twin
(splits into pups), pup, shaman (healer) and the Chupacabra King boss. All face -Y.

The files keep their old names (slime*.glb): enemy ids, resources and replays refer to them.

slime*.glb: Chupa (empty) -> Body (one mesh incl. face and gear); the bat also has WingL, WingR.
Animation: idle. EnemyCrowd squashes "Body" and flaps "Wing*" by name; do not rename the parts.
"""
import math

from mathutils import Vector

import tg_common as tg

VARIANTS = {
    # col/dark/belly/spike: swatches. k: overall scale. torso/head: full sizes (x, y, z) at k=1.
    # leg: leg height, hunch: degrees the back is raised, ear: ellipsoid size, spikes: count on the back.
    "slime": dict(col="chupa", dark="chupa_dark", belly="chupa_belly", spike="chupa_spike", k=0.9,
                  torso=(0.42, 0.32, 0.32), head=(0.34, 0.28, 0.28), leg=0.1, hunch=12, ear=(0.07, 0.12, 0.2),
                  spikes=4, spike_h=0.13, brow=10, hop=0.05, extra=None),
    "slime_fast": dict(col="berry", dark="slime_dark", belly="cream", spike="flower_yellow", k=0.9,
                       torso=(0.3, 0.38, 0.25), head=(0.27, 0.34, 0.25), leg=0.17, hunch=6,
                       ear=(0.06, 0.2, 0.12), spikes=5, spike_h=0.09, brow=15, hop=0.07, extra="fast"),
    "slime_tank": dict(col="chupa_olive", dark="chupa_olive_dark", belly="cream", spike="cream", k=0.9,
                       torso=(0.54, 0.36, 0.4), head=(0.3, 0.26, 0.25), leg=0.09, hunch=10,
                       ear=(0.06, 0.1, 0.14), spikes=4, spike_h=0.14, brow=30, hop=0.03, extra="brute"),
    "slime_king": dict(col="chupa", dark="chupa_dark", belly="chupa_belly", spike="chupa_spike", k=1.7,
                       torso=(0.46, 0.34, 0.36), head=(0.36, 0.3, 0.3), leg=0.1, hunch=10, ear=(0.07, 0.14, 0.22),
                       spikes=5, spike_h=0.12, brow=24, hop=0.04, extra="king"),
    "slime_bat": dict(col="portal_glow", dark="portal", belly="cream", spike="flower_yellow", k=0.9,
                      torso=(0.3, 0.3, 0.28), head=(0.32, 0.27, 0.27), leg=0.12, hunch=0, ear=(0.08, 0.05, 0.22),
                      spikes=3, spike_h=0.07, brow=12, hop=0.08, extra="bat"),
    "slime_shield": dict(col="chupa", dark="chupa_dark", belly="chupa_belly", spike="chupa_spike", k=0.9,
                         torso=(0.42, 0.32, 0.32), head=(0.34, 0.28, 0.28), leg=0.1, hunch=12,
                         ear=(0.07, 0.12, 0.2), spikes=3, spike_h=0.09, brow=20, hop=0.03, extra="shield"),
    "slime_splitter": dict(col="ice", dark="ice_dark", belly="ice_light", spike="chupa_spike", k=0.9,
                           torso=(0.5, 0.32, 0.32), head=(0.28, 0.24, 0.24), leg=0.1, hunch=12,
                           ear=(0.06, 0.1, 0.17), spikes=4, spike_h=0.09, brow=12, hop=0.05, extra="twin"),
    "slime_mini": dict(col="ice", dark="ice_dark", belly="ice_light", spike="chupa_spike", k=0.58,
                       torso=(0.38, 0.28, 0.3), head=(0.4, 0.34, 0.34), leg=0.08, hunch=8,
                       ear=(0.08, 0.14, 0.22), spikes=3, spike_h=0.1, brow=12, hop=0.07, extra=None, lod=0.75),
    "slime_healer": dict(col="flower_pink", dark="berry", belly="cream", spike="flower_yellow", k=0.9,
                         torso=(0.4, 0.32, 0.32), head=(0.34, 0.28, 0.28), leg=0.1, hunch=6,
                         ear=(0.07, 0.12, 0.2), spikes=3, spike_h=0.08, brow=14, hop=0.04, extra="shaman"),
}


def wing(name, side):
    """Bat wing in the XZ plane, attached at the body side (origin), pointing out along X."""
    pts = [(0.0, 0.06), (0.16, 0.2), (0.34, 0.16), (0.42, 0.02), (0.3, -0.02), (0.22, -0.08), (0.12, -0.03),
           (0.0, -0.06)]
    pts = [(x * side, z) for x, z in pts]
    n = len(pts)
    verts = [(x, -0.012, z) for x, z in pts] + [(x, 0.012, z) for x, z in pts]
    faces = [tuple(range(n)), tuple(reversed(range(n, 2 * n)))]
    faces += [(i, (i + 1) % n, n + (i + 1) % n, n + i) for i in range(n)]
    obj = tg.from_pydata(name, verts, faces, "portal", smooth=False)
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(obj.data)
    bm.free()
    bones = [tg.cylinder(f"{name}_bone{i}", 0.012, 0.008, 0.36, (0, 0, 0.05), "portal_glow", verts=6,
                         rot=(0, 90 * side - a * side, 0)) for i, a in enumerate((25, 0, -25))]
    return tg.join([obj, *bones], name)


def build_variant(name: str, v: dict):
    k = v["k"]
    lod = v.get("lod", 1.0)
    extra = v["extra"]
    tw, tl, th = v["torso"]
    hw, hl, hh = v["head"]
    leg = v["leg"]
    hunch = math.radians(v["hunch"])
    col, dark, belly, spike = v["col"], v["dark"], v["belly"], v["spike"]

    def sc(t):
        return tuple(a * k for a in t)

    def seg(n):
        return max(6, int(n * lod))

    def sph(n, size, loc, mat, s=10, r=5, rot=(0, 0, 0)):
        return tg.sphere(n, sc(size), sc(loc), mat, seg=seg(s), rings=max(3, int(r * lod)), rot=rot)

    def cone(n, rb, rt, h, loc, mat, verts=6, rot=(0, 0, 0)):
        return tg.cylinder(n, rb * k, rt * k, h * k, sc(loc), mat, verts=verts, rot=rot)

    parts = []
    tz = leg * 0.55 + th / 2
    ty = 0.04
    torso = sph("torso", (tw, tl, th), (0, ty, tz), col, 12, 7, rot=(math.degrees(hunch), 0, 0))
    parts.append(torso)
    parts.append(sph("chest", (tw * 0.72, tl * 0.55, th * 0.62), (0, ty - tl * 0.2, tz - th * 0.22), belly, 8, 5))

    def ridge(t):
        """Point on the top line of the torso at t in [-1, 1] (front -> rear), world coordinates."""
        yl = 0.5 * tl * t
        zl = 0.5 * th * math.sqrt(max(0.0, 1 - t * t))
        yy = yl * math.cos(hunch) - zl * math.sin(hunch)
        zz = yl * math.sin(hunch) + zl * math.cos(hunch)
        return ty + yy, tz + zz

    # --- legs, haunches, tail
    if extra != "bat":
        for sx in (-1, 1):
            fx, fy = sx * tw * 0.33, -tl * 0.27
            parts.append(cone(f"fleg{sx}", 0.052, 0.062, leg + 0.06, (fx, fy, 0), dark, 7))
            parts.append(sph(f"fpaw{sx}", (0.11, 0.14, 0.06), (fx, fy - 0.025, 0.03), dark, 6, 4))
            for ci, (cx_off, rot_z) in enumerate([(-0.032, 16), (0.0, 0), (0.032, -16)]):
                parts.append(cone(f"fclaw{sx}_{ci}", 0.016, 0.0, 0.065,
                                  (fx + cx_off, fy - 0.075, 0.025), "white", 4,
                                  rot=(105, 0, rot_z * sx)))
            bx, by = sx * tw * 0.42, ty + tl * 0.3
            parts.append(sph(f"haunch{sx}", (0.13 * tw / 0.36, 0.2, 0.2 + leg * 0.8), (bx, by, tz - 0.03), col, 8, 5))
            parts.append(sph(f"bpaw{sx}", (0.11, 0.15, 0.06), (bx, by - 0.03, 0.03), dark, 6, 4))
            for ci, (cx_off, rot_z) in enumerate([(-0.032, 16), (0.0, 0), (0.032, -16)]):
                parts.append(cone(f"bclaw{sx}_{ci}", 0.016, 0.0, 0.065,
                                  (bx + cx_off, by - 0.085, 0.025), "white", 4,
                                  rot=(105, 0, rot_z * sx)))
        ry, rz = ridge(0.95)
        parts.append(cone("tail", 0.04, 0.012, 0.13, (0, ry, rz - 0.04), dark, 5, rot=(-55, 0, 0)))
    else:
        for sx in (-1, 1):
            parts.append(cone(f"foot{sx}", 0.032, 0.012, 0.1, (sx * 0.07, -0.02, 0.1), dark, 5, rot=(180, 0, 0)))
            parts.append(cone(f"foot_claw{sx}_0", 0.016, 0.0, 0.06, (sx * 0.07 - 0.016 * sx, -0.05, 0.02), "white", 4,
                              rot=(150, 15 * sx, 0)))
            parts.append(cone(f"foot_claw{sx}_1", 0.016, 0.0, 0.06, (sx * 0.07 + 0.016 * sx, -0.05, 0.02), "white", 4,
                              rot=(150, -15 * sx, 0)))

    # --- back spikes
    n = v["spikes"]
    sh = v["spike_h"]
    big = max(1.0, tw / 0.38)
    for i in range(n):
        t = -0.6 + 1.5 * i / max(1, n - 1) if n > 1 else 0.0
        yy, zz = ridge(t)
        h = sh * (1.2 - 0.5 * abs(t - 0.1))
        tilt = -(8 + 28 * (t + 0.6) / 1.5)
        parts.append(cone(f"spike{i}", 0.042 * big, 0.0, h, (0, yy, zz - 0.02), spike, 5, rot=(tilt, 0, 0)))

    # --- head(s)
    def head(tag, cx, hs, ears, eye_scale=1.0, hy=None, hz=None):
        cy = (-tl * 0.5 + 0.045) if hy is None else hy
        cz = (tz + 0.05) if hz is None else hz
        hsz = (hw * hs, hl * hs, hh * hs)
        out = [sph(f"head{tag}", hsz, (cx, cy, cz), col, 12, 6)]
        f = hs * hw / 0.32
        ef = f * eye_scale

        # --- Glowing demonic eyes & aggressive menacing brow ridges
        eye_mat = "ruby"
        brow_ang = 30 + max(0, v.get("brow", 0)) * 0.25
        for sx in (-1, 1):
            ex = sx * 0.25 * hsz[0]
            dz = 0.042 * f
            yfront = cy - 0.5 * hsz[1] * math.sqrt(max(0.0, 1 - (ex / (hsz[0] / 2)) ** 2 - (dz / (hsz[2] / 2)) ** 2))
            ey = yfront + 0.01 * ef
            ez = cz + dz

            # Deep sunken demonic socket
            out.append(sph(f"socket{tag}{sx}", (0.115 * ef, 0.05 * ef, 0.085 * ef),
                           (cx + ex, ey + 0.012 * ef, ez), "eye", 6, 4))
            # Glowing demonic iris (no cute white highlights)
            out.append(sph(f"eye{tag}{sx}", (0.088 * ef, 0.042 * ef, 0.07 * ef),
                           (cx + ex, ey - 0.006 * ef, ez), eye_mat, 6, 4,
                           rot=(10, -22 * sx, 8 * sx)))
            # Sharp predatory vertical slit pupil
            out.append(sph(f"pupil{tag}{sx}", (0.018 * ef, 0.02 * ef, 0.065 * ef),
                           (cx + ex * 0.92, ey - 0.02 * ef, ez), "eye", 4, 3,
                           rot=(10, -22 * sx, 8 * sx)))
            # Heavy menacing overhanging brow ridge meeting in an angry V
            out.append(sph(f"brow{tag}{sx}", (0.14 * ef, 0.055 * ef, 0.045 * ef),
                           (cx + ex * 0.78, ey - 0.022 * ef, ez + 0.055 * ef), dark, 7, 4,
                           rot=(16, -brow_ang * sx, -10 * sx)))

        # --- Predatory fanged maw (no cute puppy snout or button nose)
        my = cy - 0.44 * hsz[1]
        mz = cz - 0.04 * f

        # Snarling upper predator jaw
        out.append(sph(f"upper_jaw{tag}", (0.20 * f, 0.11 * f, 0.06 * f),
                       (cx, my - 0.015 * f, mz + 0.025 * f), dark, 7, 4, rot=(12, 0, 0)))
        # Upper snout ridge
        out.append(cone(f"snout_crest{tag}", 0.026 * f, 0.0, 0.075 * f,
                        (cx, my + 0.02 * f, mz + 0.048 * f), dark, 4, rot=(65, 0, 0)))
        # Dark crimson maw cavity
        out.append(sph(f"maw{tag}", (0.16 * f, 0.10 * f, 0.08 * f),
                       (cx, my + 0.025 * f, mz - 0.015 * f), "mouth", 6, 4))
        # Menacing lower jaw / mandible with underbite
        out.append(sph(f"lower_jaw{tag}", (0.17 * f, 0.12 * f, 0.06 * f),
                       (cx, my + 0.012 * f, mz - 0.052 * f), dark, 6, 4, rot=(-6, 0, 0)))

        # Sharp fangs & jagged interlocking teeth
        for sx in (-1, 1):
            # Long curved upper sabre fangs
            out.append(cone(f"fang_up{tag}{sx}", 0.023 * f, 0.0, 0.095 * f,
                            (cx + sx * 0.062 * f, my - 0.032 * f, mz + 0.022 * f), "white", 4,
                            rot=(195, 12 * sx, 0)))
            # Vicious lower underbite tusks
            out.append(cone(f"fang_low{tag}{sx}", 0.021 * f, 0.0, 0.08 * f,
                            (cx + sx * 0.040 * f, my - 0.042 * f, mz - 0.052 * f), "white", 4,
                            rot=(-15, -12 * sx, 0)))
            # Sharp upper front incisors
            out.append(cone(f"incisor_up{tag}{sx}", 0.014 * f, 0.0, 0.045 * f,
                            (cx + sx * 0.018 * f, my - 0.042 * f, mz + 0.020 * f), "white", 4,
                            rot=(190, 6 * sx, 0)))
            # Sharp lower front incisors
            out.append(cone(f"incisor_low{tag}{sx}", 0.013 * f, 0.0, 0.040 * f,
                            (cx + sx * 0.014 * f, my - 0.046 * f, mz - 0.048 * f), "white", 4,
                            rot=(-12, -6 * sx, 0)))
            # Serrated side teeth
            out.append(cone(f"side_tooth{tag}{sx}", 0.016 * f, 0.0, 0.050 * f,
                            (cx + sx * 0.082 * f, my - 0.012 * f, mz + 0.014 * f), "white", 4,
                            rot=(185, 20 * sx, 0)))

        # --- Sharp curved demonic horns on the skull
        for sx in (-1, 1):
            hx = cx + sx * 0.28 * hsz[0]
            hy_h = cy + 0.02 * f
            hz_h = cz + 0.38 * hsz[2]
            h1 = 0.095 * f
            out.append(cone(f"horn_base{tag}{sx}", 0.040 * f, 0.022 * f, h1,
                            (hx, hy_h, hz_h), dark, 5, rot=(-28, 28 * sx, 0)))
            tx = hx + 0.038 * sx * f
            ty = hy_h + 0.042 * f
            tz_tip = hz_h + 0.076 * f
            h2 = 0.12 * f
            out.append(cone(f"horn{tag}{sx}", 0.024 * f, 0.0, h2,
                            (tx, ty, tz_tip), spike, 5, rot=(-52, 18 * sx, 0)))

        # --- Demonic pointed ears
        for sx in ears:
            if extra == "bat":
                out.append(cone(f"ear{tag}{sx}", 0.045 * f, 0.008 * f, 0.19 * f,
                                (cx + sx * hsz[0] * 0.34, cy + 0.03 * f, cz + hsz[2] * 0.36),
                                dark, 4, rot=(-15, 22 * sx, 0)))
            else:
                out.append(cone(f"ear{tag}{sx}", 0.038 * f, 0.006 * f, 0.16 * f,
                                (cx + sx * hsz[0] * 0.44, cy + 0.03 * f, cz + 0.05 * f),
                                dark, 4, rot=(-25, 55 * sx, -15 * sx)))
        return out, cy, cz, hsz

    if extra == "bat":
        hparts, hcy, hcz, hsz = head("", 0.0, 1.0, (-1, 1), 1.15, hy=-0.1, hz=tz + 0.04)
    elif extra == "twin":
        hparts, hcy, hcz, hsz = head("L", -0.12, 0.84, (-1,), hz=tz + 0.07)
        hp2, _, _, _ = head("R", 0.12, 0.84, (1,), hy=-tl * 0.5 + 0.03, hz=tz + 0.03)
        hparts += hp2
    elif extra == "brute":
        hparts, hcy, hcz, hsz = head("", 0.0, 1.0, (-1, 1), 0.95, hy=-tl * 0.5 + 0.04, hz=tz + 0.02)
    elif name == "slime_mini":
        hparts, hcy, hcz, hsz = head("", 0.0, 1.0, (-1, 1), 1.0, hy=-tl * 0.36, hz=tz + 0.07)
    else:
        hparts, hcy, hcz, hsz = head("", 0.0, 1.0, (-1, 1))
    parts += hparts
    head_top = hcz + hsz[2] / 2

    # --- per-variant gear
    if extra == "fast":
        # Speed stripes on the haunch.
        for sx in (-1, 1):
            parts.append(sph(f"stripe{sx}", (0.03, 0.2, 0.04), (sx * tw * 0.56, ty + tl * 0.3, tz + 0.03), spike, 6, 3,
                             rot=(20, 0, 0)))
    if extra == "brute":
        cap = sph("bone_cap", (hw * 1.1, hl * 1.08, hh * 0.75), (0, hcy + 0.01, hcz + 0.02), "cream", 10, 5)
        tg.deform(cap, lambda p, z0=-0.01 * k: Vector((p.x, p.y, max(p.z, z0))))
        parts.append(cap)
        for sx in (-1, 1):
            parts.append(cone(f"brute_horn{sx}", 0.04, 0.0, 0.17, (sx * hw * 0.42, hcy + 0.02, head_top - 0.03), "cream", 6,
                              rot=(0, 42 * sx, 0)))
            parts.append(sph(f"pad{sx}", (0.17, 0.2, 0.15), (sx * tw * 0.54, -tl * 0.1, tz + th * 0.28), "cream", 8, 5))
            parts.append(cone(f"pad_spike{sx}", 0.04, 0.0, 0.1, (sx * tw * 0.58, -tl * 0.1, tz + th * 0.4), "cream", 5,
                              rot=(0, 55 * sx, 0)))
            parts.append(cone(f"tusk{sx}", 0.026, 0.0, 0.085, (sx * 0.085, hcy - hsz[1] * 0.5 + 0.0, hcz - 0.11),
                              "cream", 4, rot=(-25, 0, 0)))
    if extra == "king":
        band = cone("crown_band", 0.13, 0.14, 0.06, (0, hcy + 0.02, head_top - 0.05), "flower_yellow", 16)
        parts.append(band)
        for i in range(6):
            a = 2 * math.pi * i / 6 + math.pi / 6
            x, y = 0.135 * math.cos(a), hcy + 0.02 + 0.135 * math.sin(a)
            parts.append(cone(f"crown_bone{i}", 0.032, 0.0, 0.12, (x, y, head_top - 0.02), "cream", 5))
            parts.append(sph(f"crown_tip{i}", (0.03, 0.03, 0.03), (x, y, head_top + 0.11), "flower_yellow", 6, 3))
        parts.append(sph("crown_gem", (0.05, 0.03, 0.05), (0, hcy + 0.02 - 0.138, head_top - 0.02), "ruby", 8, 4))
        mantle = sph("mantle", (tw * 1.2, tl * 0.5, th * 0.62), (0, ty + 0.04, tz + th * 0.12), "portal", 14, 6)
        parts.append(mantle)
        for sx in (-1, 1):
            parts.append(cone(f"tusk{sx}", 0.032, 0.0, 0.1, (sx * 0.095, hcy - hsz[1] * 0.5 + 0.01, hcz - 0.12), "cream", 5,
                              rot=(-20, 0, 0)))
    if extra == "shield":
        sh_parts = []
        for i, xo in enumerate((-0.095, 0.0, 0.095)):
            sh_parts.append(tg.box(f"plank{i}", (0.098, 0.035, 0.4), (xo, 0, 0), "wood_light" if i % 2 else "wood",
                                   bevel=0.01, bevel_seg=1))
        sh_parts.append(tg.box("strap1", (0.31, 0.045, 0.045), (0, -0.01, 0.1), "iron", bevel=0.01, bevel_seg=1))
        sh_parts.append(tg.box("strap2", (0.31, 0.045, 0.045), (0, -0.01, -0.1), "iron", bevel=0.01, bevel_seg=1))
        sh_parts.append(tg.sphere("shield_boss", (0.09, 0.05, 0.09), (0, -0.03, 0), "flower_yellow", seg=8, rings=4))
        shield = tg.join(sh_parts, "ShieldPart")
        shield.rotation_euler = (0, 0, math.radians(-52))
        shield.location = (tw * 0.62 * k, -tl * 0.42 * k, (tz + 0.0) * k)
        shield.scale = (k, k, k)
        tg.apply_all_transforms(shield)
        parts.append(shield)
        # a rough wooden bowl helmet
        cap = sph("cap", (hw * 1.06, hl * 1.04, hh * 0.6), (0, hcy + 0.01, hcz + hh * 0.2), "wood_dark", 10, 4)
        tg.deform(cap, lambda p, z0=-hh * 0.08 * k: Vector((p.x, p.y, max(p.z, z0))))
        parts.append(cap)
    if extra == "shaman":
        top = head_top
        parts.append(cone("headband", 0.1, 0.1, 0.03, (0, hcy + 0.02, top - 0.07), "flower_yellow", 12))
        for i, (fx, mat, rot) in enumerate(((-0.07, "go", 28), (0.0, "flower_yellow", 0), (0.07, "ruby", -28))):
            parts.append(sph(f"feather{i}", (0.055, 0.02, 0.19), (fx, hcy + 0.03, top + 0.02), mat, 8, 4, rot=(0, rot, 0)))
        parts.append(sph("amulet", (0.08, 0.04, 0.08), (0, -tl * 0.5 + 0.02, tz - 0.09), "flower_yellow", 8, 4))
        sx_, sy_ = tw * 0.82, -tl * 0.2
        parts.append(cone("staff", 0.02, 0.016, 0.6, (sx_, sy_, 0), "wood_dark", 6))
        parts.append(sph("orb", (0.12, 0.12, 0.12), (sx_, sy_, 0.66), "go", 10, 6))
        parts.append(tg.torus("orb_ring", 0.07 * k, 0.012 * k, (sx_ * k, sy_ * k, 0.58 * k), "flower_yellow", seg=10, minor_seg=4))
    body = tg.join([p for p in parts], "Body")
    tg.pivot(body, (0, 0, 0))
    root = tg.empty("Chupa")
    tg.parent(body, root)
    hop = v["hop"]
    keys = {
        body: [(0, {}), (8, {"scale": (1.1, 1.1, 0.86)}), (16, {"scale": (0.93, 0.93, 1.13), "loc": (0, 0, hop)}),
               (24, {"scale": (1.04, 1.04, 0.96)}), (32, {})],
    }
    if extra == "bat":
        for side in (-1, 1):
            w = wing(f"Wing{'L' if side < 0 else 'R'}", side)
            w.location = (0.15 * side, 0.05, tz * k + 0.04)
            tg.parent(w, root)
            keys[w] = [(0, {"rot": (0, 25 * side, 0)}), (8, {"rot": (0, -35 * side, 0)}), (16, {"rot": (0, 25 * side, 0)}),
                       (24, {"rot": (0, -35 * side, 0)}), (32, {"rot": (0, 25 * side, 0)})]
    tg.make_track("idle", keys, 32)
    return tg.finish_asset(name, root, ao_distance=0.1 * k, ao_strength=0.65)


def build() -> list:
    import bpy
    out = []
    for name, v in VARIANTS.items():
        for o in list(bpy.data.objects):
            bpy.data.objects.remove(o, do_unlink=True)
        out.append(build_variant(name, v))
    return out

"""Shared helpers for Tinyguard asset scripts (Blender 4.0+, run in background).

Modelling is done with named "swatch" materials (see PALETTE). finish_asset()
then converts every mesh to the shared palette atlas material: each face gets
UVs at the centre of its swatch cell, so one material (one draw call per mesh)
covers the whole game. Ambient occlusion is ray-cast into vertex colours.

Coordinates: Blender Z-up, metres. Models face -Y (glTF/Godot +Z).
"""
from __future__ import annotations

import math
import random
from pathlib import Path

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector
from mathutils.bvhtree import BVHTree

ROOT = Path(__file__).resolve().parents[2]
MODELS_DIR = ROOT / "assets" / "models"
MATERIALS_DIR = ROOT / "assets" / "materials"

# name: (sRGB hex, roughness, metallic). Order defines the atlas cell.
PALETTE: dict[str, tuple[str, float, float]] = {
    # nature
    "grass": ("6BA85C", 0.95, 0.0),
    "grass_dark": ("4E8A45", 0.95, 0.0),
    "dirt": ("8B6A4A", 0.95, 0.0),
    "dirt_dark": ("6B4F38", 0.95, 0.0),
    "path": ("D9BE86", 0.95, 0.0),
    "path_dark": ("BFA06A", 0.95, 0.0),
    "rock": ("8F96A0", 0.85, 0.0),
    "rock_dark": ("6E747E", 0.9, 0.0),
    "leaf": ("5DAE4B", 0.8, 0.0),
    "leaf_dark": ("3F8A3B", 0.85, 0.0),
    "leaf_light": ("79BF57", 0.8, 0.0),
    "pine": ("2F7D4F", 0.85, 0.0),
    "pine_light": ("3F9A5E", 0.85, 0.0),
    "wood": ("8A5A3A", 0.8, 0.0),
    "wood_dark": ("5E3C26", 0.85, 0.0),
    "wood_light": ("B07A4E", 0.8, 0.0),
    "berry": ("D9425A", 0.45, 0.0),
    "flower_yellow": ("F4C842", 0.7, 0.0),
    "flower_pink": ("EE8FB0", 0.7, 0.0),
    "flower_white": ("F6F1E7", 0.7, 0.0),
    # buildings
    "stone": ("B9B0A0", 0.85, 0.0),
    "stone_dark": ("8E8678", 0.9, 0.0),
    "stone_light": ("D2C9B6", 0.85, 0.0),
    "roof": ("3F73D9", 0.5, 0.1),
    "roof_dark": ("2E56AE", 0.55, 0.1),
    "window": ("2A2F45", 0.4, 0.0),
    "portal": ("4B2F7A", 0.4, 0.0),
    "portal_glow": ("B48CF2", 0.3, 0.0),
    # hero
    "armor": ("3E6FD6", 0.35, 0.25),
    "armor_dark": ("2A4FA8", 0.4, 0.2),
    "cream": ("F1E4C6", 0.7, 0.0),
    "gold": ("E9B44C", 0.3, 0.85),
    "steel": ("DCE3EC", 0.3, 0.55),
    "leather": ("6A4327", 0.7, 0.0),
    "skin": ("F6C7A4", 0.6, 0.0),
    "blush": ("F0A39A", 0.6, 0.0),
    "hair": ("6E3F24", 0.55, 0.0),
    "eye": ("1E1C26", 0.15, 0.0),
    "white": ("FFFFFF", 0.2, 0.0),
    "mouth": ("A8434B", 0.5, 0.0),
    "cape": ("2B4AA3", 0.75, 0.0),
    "string": ("EDE6D6", 0.8, 0.0),
    # enemy
    "slime": ("EA5A4E", 0.25, 0.0),
    "slime_dark": ("B53A3A", 0.3, 0.0),
    "slime_light": ("FFA08C", 0.2, 0.0),
    # enemy variants
    "slime_fast": ("F2A33A", 0.25, 0.0),
    "slime_fast_dark": ("C9762A", 0.3, 0.0),
    "slime_tank": ("B8323F", 0.3, 0.0),
    "slime_tank_dark": ("7E2030", 0.35, 0.0),
    "king": ("B23A72", 0.25, 0.0),
    "king_dark": ("6E2350", 0.3, 0.0),
    "ruby": ("E23B4F", 0.15, 0.2),
    # towers
    "iron": ("4C525F", 0.45, 0.6),
    "iron_dark": ("2F333C", 0.5, 0.5),
    "ice": ("7FD3F2", 0.15, 0.0),
    "ice_light": ("D6F6FF", 0.1, 0.0),
    "ice_dark": ("3E8FC4", 0.2, 0.0),
    # world map
    "sea": ("5FA8D3", 0.3, 0.0),
    "sea_light": ("8CC8E8", 0.3, 0.0),
    "sand": ("E8D3A0", 0.95, 0.0),
    "snow": ("F4F7FA", 0.8, 0.0),
    # HUD icons
    "star": ("FFC93C", 0.35, 0.0),
    "go": ("5CCB5F", 0.4, 0.0),
    "go_dark": ("379B48", 0.45, 0.0),
}
GRID = 8
CELL_PX = 32


# --------------------------------------------------------------------------- scene


def reset_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.fps = 24
    scene.frame_start = 0


def select_only(objs) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    objs = objs if isinstance(objs, (list, tuple)) else [objs]
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]


def swatch(name: str) -> bpy.types.Material:
    """Temporary per-colour material used while modelling."""
    if name not in PALETTE:
        raise KeyError(f"unknown swatch {name}")
    mat = bpy.data.materials.get("sw_" + name)
    if mat is None:
        mat = bpy.data.materials.new("sw_" + name)
        mat.diffuse_color = (*hex_to_linear(PALETTE[name][0]), 1.0)
    return mat


# Biome palettes: swatch name -> replacement, applied by recolor().
BIOMES = {
    "meadow": {},
    "winter": {"grass": "snow", "grass_dark": "ice_light", "leaf": "snow", "leaf_light": "snow",
               "leaf_dark": "pine", "pine_light": "snow", "dirt": "rock", "dirt_dark": "rock_dark",
               "path": "stone_light", "path_dark": "stone", "flower_yellow": "ice", "flower_pink": "ice_light",
               "flower_white": "snow", "berry": "ruby"},
    "autumn": {"leaf": "slime_fast", "leaf_light": "flower_yellow", "leaf_dark": "berry",
               "flower_pink": "slime_fast", "flower_white": "flower_yellow", "grass_dark": "dirt"},
    "desert": {"grass": "sand", "grass_dark": "path", "leaf": "leaf_dark", "leaf_light": "leaf",
               "pine": "leaf_dark", "pine_light": "leaf", "dirt": "path_dark", "path": "dirt",
               "path_dark": "dirt_dark", "flower_pink": "berry", "flower_white": "flower_yellow"},
}


def recolor(roots, biome: str) -> None:
    """Swap swatch materials on every mesh under roots according to BIOMES[biome]."""
    mapping = BIOMES[biome]
    if not mapping:
        return
    roots = roots if isinstance(roots, (list, tuple)) else [roots]
    for root in roots:
        for obj in [root, *root.children_recursive]:
            if obj.type != "MESH":
                continue
            for slot in obj.material_slots:
                name = slot.material.name[3:] if slot.material and slot.material.name.startswith("sw_") else None
                if name in mapping:
                    slot.material = swatch(mapping[name])


def hex_to_srgb(h: str) -> tuple[float, float, float]:
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


def hex_to_linear(h: str) -> tuple[float, float, float]:
    def lin(c: float) -> float:
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    return tuple(lin(c) for c in hex_to_srgb(h))


def _finish_new(name: str, mat: str | None, smooth: bool = True):
    obj = bpy.context.active_object
    obj.name = name
    obj.data.name = name
    if mat:
        obj.data.materials.append(swatch(mat))
    if smooth:
        shade(obj, 50)
    return obj


# --------------------------------------------------------------------------- primitives


def sphere(name, size, loc=(0, 0, 0), mat=None, seg=24, rings=12, rot=(0, 0, 0)):
    """Ellipsoid with full size (x, y, z)."""
    bpy.ops.mesh.primitive_uv_sphere_add(segments=seg, ring_count=rings, radius=0.5, location=loc,
                                         rotation=[math.radians(a) for a in rot])
    obj = _finish_new(name, mat)
    obj.scale = size
    apply_transform(obj)
    return obj


def cylinder(name, r_bottom, r_top, height, loc=(0, 0, 0), mat=None, verts=16, rot=(0, 0, 0), smooth=True):
    """Frustum standing on loc (base at loc.z) unless rotated."""
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r_bottom, radius2=r_top, depth=height,
                                    location=(0, 0, 0), end_fill_type="NGON")
    obj = _finish_new(name, mat, smooth)
    obj.data.transform(Matrix.Translation((0, 0, height / 2)))  # origin at the base
    obj.rotation_euler = Euler([math.radians(a) for a in rot])
    obj.location = loc
    apply_transform(obj)
    return obj


def box(name, size, loc=(0, 0, 0), mat=None, bevel=0.0, bevel_seg=2, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=[math.radians(a) for a in rot])
    obj = _finish_new(name, mat, smooth=False)
    obj.scale = size
    apply_transform(obj)
    if bevel > 0:
        add_bevel(obj, bevel, bevel_seg)
    shade(obj, 35)
    return obj


def torus(name, major, minor, loc=(0, 0, 0), mat=None, rot=(0, 0, 0), seg=24, minor_seg=8, scale=(1, 1, 1)):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor, major_segments=seg,
                                     minor_segments=minor_seg, location=loc,
                                     rotation=[math.radians(a) for a in rot])
    obj = _finish_new(name, mat)
    obj.scale = scale
    apply_transform(obj)
    return obj


def from_pydata(name, verts, faces, mat=None, smooth=True):
    me = bpy.data.meshes.new(name)
    me.from_pydata([Vector(v) for v in verts], [], faces)
    me.update()
    obj = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(obj)
    if mat:
        me.materials.append(swatch(mat))
    if smooth:
        shade(obj, 50)
    return obj


def lathe(name, profile, mat=None, steps=16, loc=(0, 0, 0), smooth=True):
    """Revolve a (radius, z) profile around Z. Profile goes bottom -> top."""
    verts, faces = [], []
    n = len(profile)
    for s in range(steps):
        a = 2 * math.pi * s / steps
        for r, z in profile:
            verts.append((r * math.cos(a) + loc[0], r * math.sin(a) + loc[1], z + loc[2]))
    for s in range(steps):
        s2 = (s + 1) % steps
        for i in range(n - 1):
            faces.append((s * n + i, s2 * n + i, s2 * n + i + 1, s * n + i + 1))
    obj = from_pydata(name, verts, faces, mat, smooth)
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    # Cap holes (bottom/top) when the profile does not reach the axis.
    bmesh.ops.holes_fill(bm, edges=bm.edges, sides=steps)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(obj.data)
    bm.free()
    return obj


# --------------------------------------------------------------------------- modifiers & ops


def apply_transform(obj) -> None:
    select_only(obj)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)


def apply_all_transforms(obj) -> None:
    select_only(obj)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


def shade(obj, angle_deg: float) -> None:
    """Smooth shading with hard edges above angle_deg (Blender 4.0 and 4.1+)."""
    select_only(obj)
    if hasattr(obj.data, "use_auto_smooth"):  # Blender <= 4.0
        bpy.ops.object.shade_smooth()
        obj.data.use_auto_smooth = True
        obj.data.auto_smooth_angle = math.radians(angle_deg)
    else:  # Blender 4.1+ removed mesh auto smooth
        bpy.ops.object.shade_smooth_by_angle(angle=math.radians(angle_deg))


def flat(obj) -> None:
    select_only(obj)
    bpy.ops.object.shade_flat()


def _apply_mod(obj, mod) -> None:
    select_only(obj)
    bpy.ops.object.modifier_apply(modifier=mod.name)


def add_subsurf(obj, levels: int = 1) -> None:
    mod = obj.modifiers.new("subsurf", "SUBSURF")
    mod.levels = levels
    mod.render_levels = levels
    _apply_mod(obj, mod)


def add_bevel(obj, width: float, segments: int = 2, angle_deg: float = 40) -> None:
    mod = obj.modifiers.new("bevel", "BEVEL")
    mod.width = width
    mod.segments = segments
    mod.limit_method = "ANGLE"
    mod.angle_limit = math.radians(angle_deg)
    mod.harden_normals = False
    _apply_mod(obj, mod)


def add_solidify(obj, thickness: float, inner_mat: str | None = None) -> None:
    mod = obj.modifiers.new("solidify", "SOLIDIFY")
    mod.thickness = thickness
    mod.offset = 0
    if inner_mat:
        obj.data.materials.append(swatch(inner_mat))
        mod.material_offset = len(obj.data.materials) - 1
    _apply_mod(obj, mod)


def displace_noise(obj, strength: float, scale: float = 0.3, seed: int = 0) -> None:
    """Organic wobble along normals (deterministic)."""
    rng = random.Random(seed)
    ox, oy, oz = (rng.uniform(0, 100) for _ in range(3))
    from mathutils import noise
    me = obj.data
    for v in me.vertices:
        p = Vector(((v.co.x + ox) / scale, (v.co.y + oy) / scale, (v.co.z + oz) / scale))
        v.co += v.normal * noise.noise(p) * strength
    me.update()


def deform(obj, fn) -> None:
    """Apply fn(Vector co) -> Vector to every vertex (object space)."""
    for v in obj.data.vertices:
        v.co = fn(v.co.copy())
    obj.data.update()


def join(objs, name: str):
    objs = [o for o in objs if o is not None]
    select_only(objs)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    obj = bpy.context.active_object
    obj.name = name
    obj.data.name = name
    return obj


def pivot(obj, point) -> None:
    """Move the origin of an unparented, unrotated, unscaled object to `point`
    (world space) without moving its geometry."""
    point = Vector(point)
    obj.data.transform(Matrix.Translation(obj.location - point))
    obj.location = point


def parent(child, par) -> None:
    # matrix_world is stale after a location change until the view layer updates.
    bpy.context.view_layer.update()
    mw = child.matrix_world.copy()
    child.parent = par
    child.matrix_world = mw


def empty(name: str, loc=(0, 0, 0)):
    obj = bpy.data.objects.new(name, None)
    obj.location = loc
    bpy.context.collection.objects.link(obj)
    return obj


def mirror_x(obj, name: str):
    """Duplicate obj mirrored across X (object data copied)."""
    dup = obj.copy()
    dup.data = obj.data.copy()
    dup.name = name
    dup.data.name = name
    bpy.context.collection.objects.link(dup)
    dup.data.transform(Matrix.Scale(-1, 4, (1, 0, 0)))
    dup.data.flip_normals()
    dup.location.x = -obj.location.x
    dup.rotation_euler = (obj.rotation_euler.x, -obj.rotation_euler.y, -obj.rotation_euler.z)
    return dup


def surface_y(obj, x: float, z: float, lift: float = 0.0) -> float:
    """World y of obj's front (-Y facing) surface at world (x, z), pushed out by lift.
    Used to seat facial features on deformed shapes."""
    bpy.context.view_layer.update()
    inv = obj.matrix_world.inverted()
    origin = inv @ Vector((x, -10.0, z))
    direction = (inv.to_3x3() @ Vector((0, 1, 0))).normalized()
    hit, loc, _n, _i = obj.ray_cast(origin, direction)
    if not hit:
        raise ValueError(f"no surface on {obj.name} at x={x} z={z}")
    return (obj.matrix_world @ loc).y - lift


COLLIDER_SUFFIX = "-colonly"


def is_collider(obj) -> bool:
    return obj.name.endswith(COLLIDER_SUFFIX)


def collider_box(name, size, loc=(0, 0, 0), rot=(0, 0, 0)):
    """Godot import hint: a mesh named *-colonly becomes a StaticBody3D shape."""
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=[math.radians(a) for a in rot])
    obj = bpy.context.active_object
    obj.scale = size
    apply_transform(obj)
    obj.name = name + COLLIDER_SUFFIX
    return obj


def collider_cylinder(name, radius, height, loc=(0, 0, 0), verts=8):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=radius, depth=height,
                                        location=(loc[0], loc[1], loc[2] + height / 2))
    obj = bpy.context.active_object
    obj.name = name + COLLIDER_SUFFIX
    return obj


def tri_count(objs) -> int:
    total = 0
    for o in objs:
        if o.type == "MESH":
            total += sum(len(p.vertices) - 2 for p in o.data.polygons)
    return total


# --------------------------------------------------------------------------- animation


def make_track(track: str, keys: dict, length: int) -> None:
    """keys: {obj: [(frame, {"loc": dv, "rot": deg, "scale": mul}), ...]}.
    Values are relative to the rest pose. Each object's action is pushed into an
    NLA track named `track`; the exporter merges tracks by name."""
    for obj, frames in keys.items():
        rest_loc, rest_rot, rest_scale = obj.location.copy(), obj.rotation_euler.copy(), obj.scale.copy()
        for frame, props in frames:
            obj.location = rest_loc + Vector(props.get("loc", (0, 0, 0)))
            r = props.get("rot", (0, 0, 0))
            obj.rotation_euler = Euler([rest_rot[i] + math.radians(r[i]) for i in range(3)])
            s = props.get("scale", (1, 1, 1))
            obj.scale = Vector([rest_scale[i] * s[i] for i in range(3)])
            for path in ("location", "rotation_euler", "scale"):
                obj.keyframe_insert(path, frame=frame)
        action = obj.animation_data.action
        action.name = f"{obj.name}_{track}"
        nla = obj.animation_data.nla_tracks.new()
        nla.name = track
        strip = nla.strips.new(track, 0, action)
        strip.action_frame_start, strip.action_frame_end = 0, length
        obj.animation_data.action = None
        obj.location, obj.rotation_euler, obj.scale = rest_loc, rest_rot, rest_scale


# --------------------------------------------------------------------------- palette material


def _cell(index: int) -> tuple[int, int]:
    return index % GRID, index // GRID


def palette_material() -> bpy.types.Material:
    mat = bpy.data.materials.get("TG_Palette")
    if mat:
        return mat
    names = list(PALETTE)
    size = GRID * CELL_PX
    albedo = bpy.data.images.new("tg_palette_albedo", size, size, alpha=False)
    orm = bpy.data.images.new("tg_palette_orm", size, size, alpha=False)
    orm.colorspace_settings.name = "Non-Color"
    a_px = [0.0] * (size * size * 4)
    o_px = [0.0] * (size * size * 4)
    for i in range(GRID * GRID):
        if i < len(names):
            h, rough, metal = PALETTE[names[i]]
            col = hex_to_srgb(h)
        else:
            col, rough, metal = (1.0, 0.0, 1.0), 1.0, 0.0
        cx, cy = _cell(i)
        for y in range(CELL_PX):
            # Blender images are stored bottom row first; cell row 0 is the top.
            py = size - 1 - (cy * CELL_PX + y)
            for x in range(CELL_PX):
                k = (py * size + cx * CELL_PX + x) * 4
                a_px[k:k + 4] = (*col, 1.0)
                o_px[k:k + 4] = (1.0, rough, metal, 1.0)
    albedo.pixels = a_px
    orm.pixels = o_px
    MATERIALS_DIR.mkdir(parents=True, exist_ok=True)
    for img in (albedo, orm):
        img.filepath_raw = str(MATERIALS_DIR / f"{img.name}.png")
        img.file_format = "PNG"
        img.save()

    mat = bpy.data.materials.new("TG_Palette")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Specular IOR Level"].default_value = 0.4
    t_alb = nt.nodes.new("ShaderNodeTexImage")
    t_alb.image = albedo
    t_alb.interpolation = "Closest"
    t_orm = nt.nodes.new("ShaderNodeTexImage")
    t_orm.image = orm
    t_orm.interpolation = "Closest"
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    nt.links.new(t_alb.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(t_orm.outputs["Color"], sep.inputs["Color"])
    nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
    nt.links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])
    return mat


def to_palette(obj) -> None:
    """Replace swatch materials by the atlas: UV every face to its cell centre."""
    me = obj.data
    names = list(PALETTE)
    if not me.uv_layers:
        me.uv_layers.new(name="UVMap")
    uv = me.uv_layers[0].data
    slot_cell = []
    for slot in obj.material_slots:
        mname = slot.material.name[3:] if slot.material and slot.material.name.startswith("sw_") else None
        if mname is None:
            raise ValueError(f"{obj.name}: face material {slot.material} is not a swatch")
        slot_cell.append(names.index(mname))
    for poly in me.polygons:
        cx, cy = _cell(slot_cell[poly.material_index])
        u = (cx + 0.5) / GRID
        v = 1.0 - (cy + 0.5) / GRID
        for li in poly.loop_indices:
            uv[li].uv = (u, v)
    me.materials.clear()
    me.materials.append(palette_material())


# --------------------------------------------------------------------------- ambient occlusion


def bake_ao(objs, distance: float, strength: float = 0.8, rays: int = 32, extra=(), tint=None) -> None:
    """Ray-cast AO into a POINT byte colour attribute "Col" (exported as COLOR_0).
    `extra` objects (e.g. a helper ground plane) occlude but get no colours.
    `tint(world_co) -> float` multiplies the result (used for grass variation)."""
    meshes = [o for o in objs if o.type == "MESH"]
    verts, polys, off = [], [], 0
    for o in list(meshes) + list(extra):
        dg = o.evaluated_get(bpy.context.evaluated_depsgraph_get())
        me = dg.to_mesh()
        verts += [o.matrix_world @ v.co for v in me.vertices]
        polys += [[i + off for i in p.vertices] for p in me.polygons]
        off += len(me.vertices)
        dg.to_mesh_clear()
    bvh = BVHTree.FromPolygons(verts, polys)
    rng = random.Random(7)
    dirs = []
    for i in range(rays):
        u, v = (i + 0.5) / rays, rng.random()
        r, th = math.sqrt(u), 2 * math.pi * v
        dirs.append(Vector((r * math.cos(th), r * math.sin(th), math.sqrt(max(0.0, 1 - u)))))
    for o in meshes:
        me = o.data
        if "Col" in me.color_attributes:
            me.color_attributes.remove(me.color_attributes["Col"])
        attr = me.color_attributes.new("Col", "BYTE_COLOR", "POINT")
        me.color_attributes.active_color = attr
        nmat = o.matrix_world.to_3x3().inverted().transposed()
        for v in me.vertices:
            co = o.matrix_world @ v.co
            nrm = (nmat @ v.normal).normalized()
            q = nrm.to_track_quat("Z", "Y")
            hits = 0
            for d in dirs:
                if bvh.ray_cast(co + nrm * 0.003, q @ d, distance)[0] is not None:
                    hits += 1
            ao = 1.0 - strength * hits / rays
            if tint:
                ao *= tint(co)
            attr.data[v.index].color = (ao, ao, ao, 1.0)


# --------------------------------------------------------------------------- export


def finish_asset(name: str, roots, ao_distance: float, ao_strength: float = 0.8,
                 ground: bool = True, tint=None, occluders=()) -> dict:
    """AO bake, palette conversion and GLB export of everything under roots.
    `occluders` are other scene objects that shadow this asset's AO only."""
    roots = roots if isinstance(roots, (list, tuple)) else [roots]
    objs = []
    for r in roots:
        objs.append(r)
        objs.extend(r.children_recursive)
    # "-colonly" meshes become invisible StaticBody3D colliders in Godot: no AO, no material.
    meshes = [o for o in objs if o.type == "MESH" and not is_collider(o)]
    extra = list(occluders)
    if ground:
        bpy.ops.mesh.primitive_plane_add(size=30, location=(0, 0, 0))
        extra.append(bpy.context.active_object)
    bake_ao(meshes, ao_distance, ao_strength, extra=extra, tint=tint)
    for o in extra[len(occluders):]:
        bpy.data.objects.remove(o, do_unlink=True)
    for o in meshes:
        to_palette(o)
    MODELS_DIR.mkdir(parents=True, exist_ok=True)
    path = MODELS_DIR / f"{name}.glb"
    select_only(objs)
    options = dict(
        filepath=str(path), export_format="GLB", use_selection=True,
        export_animation_mode="NLA_TRACKS", export_yup=True,
        export_apply=True, export_texcoords=True, export_normals=True,
        export_materials="EXPORT", export_image_format="AUTO",
    )
    # The AO colour attribute is not wired into the material, so it must be
    # exported explicitly. The option was renamed in Blender 4.2.
    exporter_props = bpy.ops.export_scene.gltf.get_rna_type().properties.keys()
    if "export_vertex_color" in exporter_props:
        options["export_vertex_color"] = "ACTIVE"
    else:
        options["export_colors"] = True
    bpy.ops.export_scene.gltf(**options)
    ensure_import_settings(path)
    info = {"name": name, "tris": tri_count(meshes), "meshes": len(meshes), "path": str(path.relative_to(ROOT))}
    print(f"[tinyguard] exported {info['path']}: {info['tris']} tris, {info['meshes']} meshes")
    return info


SHARED_MATERIAL = "res://assets/materials/tg_palette.tres"
_IMPORT_PARAMS = {
    # Every model uses the one shared palette material instead of its embedded copy.
    "_subresources": '{\n"materials": {\n"TG_Palette": {\n"use_external/enabled": true,\n'
                     f'"use_external/path": "{SHARED_MATERIAL}"\n}}\n}}\n}}',
    # Do not extract the embedded palette PNGs next to every model.
    "gltf/embedded_image_handling": "0",
}


def ensure_import_settings(glb: Path) -> None:
    """Write/patch <model>.glb.import so Godot uses the shared material.
    Godot keeps these params and fills in the rest on (re)import."""
    imp = glb.with_name(glb.name + ".import")
    if not imp.exists():
        lines = ["[remap]", "", 'importer="scene"', "", "[params]", ""]
        lines += [f"{k}={v}" for k, v in _IMPORT_PARAMS.items()]
        imp.write_text("\n".join(lines) + "\n")
        return
    out, depth = [], 0
    for line in imp.read_text().splitlines():
        key = line.split("=", 1)[0]
        if depth > 0:  # inside a multi-line _subresources value
            depth += line.count("{") - line.count("}")
            continue
        if key == "_subresources":
            depth = line.count("{") - line.count("}")
            continue
        if key in _IMPORT_PARAMS:
            continue
        out.append(line)
    out += [f"{k}={v}" for k, v in _IMPORT_PARAMS.items()]
    imp.write_text("\n".join(out) + "\n")

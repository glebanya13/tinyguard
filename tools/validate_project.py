#!/usr/bin/env python3
"""Static sanity checks for the Bimbleguard Godot project.

Runs without Godot. Verifies required files/dirs, res:// references in
project.godot and .tscn/.tres files, basic .tscn structure, NodePath values
and $Node paths used by scene root scripts, class_name uniqueness and
script_class of .tres files, and that .gd files are indented with tabs.
It does NOT prove the project runs in Godot.

Usage: python3 tools/validate_project.py
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

REQUIRED_FILES = [
    "project.godot",
    "README.md",
    "CLAUDE.md",
    ".gitignore",
    "docs/GAME_DESIGN.md",
    "docs/TECHNICAL_DESIGN.md",
    "docs/ART_GUIDE.md",
    "docs/ROADMAP.md",
]
REQUIRED_DIRS = [
    "scenes",
    "scripts",
    "resources",
    "ui",
    "assets/models",
    "assets/materials",
    "assets/blender",
]
EXPECTED_SETTINGS = {
    "renderer/rendering_method": '"gl_compatibility"',
    "renderer/rendering_method.mobile": '"gl_compatibility"',
    "window/handheld/orientation": "4",  # sensor landscape
}

RES_RE = re.compile(r'res://[^"\s)]+')
HEADER_RE = re.compile(r"^\[(\w+)(.*)\]$")
ATTR_RE = re.compile(r'(\w+)=("[^"]*"|\S+)')

errors: list[str] = []
# Non-fatal findings (release blockers that must not break day-to-day checks).
warnings: list[str] = []
# res:// path of every script -> its class_name (filled before scenes are checked).
class_names: dict[str, str] = {}


def resolve_node_path(base: str, target: str) -> str:
    """Resolves a relative NodePath against a scene node path ("." is root)."""
    parts = [] if base == "." else base.split("/")
    for seg in target.split("/"):
        if seg == "..":
            if not parts:
                return "<outside scene>"
            parts.pop()
        elif seg not in (".", ""):
            parts.append(seg)
    return "/".join(parts) or "."


def inside_instance(node_path: str, instanced: set[str]) -> bool:
    """True if node_path lies below an instanced sub-scene (not listed here)."""
    return any(node_path.startswith(inst + "/") for inst in instanced)


def check_layout() -> None:
    for rel in REQUIRED_FILES:
        if not (ROOT / rel).is_file():
            errors.append(f"missing file: {rel}")
    for rel in REQUIRED_DIRS:
        if not (ROOT / rel).is_dir():
            errors.append(f"missing dir: {rel}")


def check_res_paths(path: Path) -> None:
    for ref in RES_RE.findall(path.read_text(encoding="utf-8")):
        target = ROOT / ref[len("res://"):]
        if not target.exists():
            errors.append(f"{path.relative_to(ROOT)}: broken reference {ref}")


def check_project_settings() -> None:
    path = ROOT / "project.godot"
    if not path.is_file():
        return
    text = path.read_text(encoding="utf-8")
    if "config_version=5" not in text:
        errors.append("project.godot: expected config_version=5 (Godot 4)")
    if 'run/main_scene="' not in text:
        errors.append("project.godot: run/main_scene is not set")
    for key, value in EXPECTED_SETTINGS.items():
        if f"{key}={value}" not in text:
            errors.append(f"project.godot: expected {key}={value}")
    check_res_paths(path)


def check_scene(path: Path) -> None:
    rel = path.relative_to(ROOT)
    lines = path.read_text(encoding="utf-8").splitlines()
    if not lines or not lines[0].startswith(("[gd_scene", "[gd_resource")):
        errors.append(f"{rel}: missing gd_scene/gd_resource header")
        return
    header = dict(ATTR_RE.findall(lines[0].strip("[]")))
    if header.get("format") != "3":
        errors.append(f"{rel}: expected format=3 (Godot 4)")

    ext_ids, sub_ids, used_ext, used_sub = set(), set(), set(), set()
    ext_paths: dict[str, str] = {}
    node_paths = {"."}
    instanced: set[str] = set()
    node_path_refs: list[tuple[str, str]] = []  # (owner node, NodePath value)
    # Node-typed @export properties written as NodePath(...) must be listed in the
    # node header's node_paths, otherwise Godot 4 leaves them null at runtime.
    node_props: dict[str, tuple[str, set[str], str]] = {}  # node -> (script id, node_paths, header)
    nodepath_props: list[tuple[str, str]] = []  # (node, property)
    root_script_id = ""
    resource_script_id = ""
    current = ""  # node path of the block being read, "" outside nodes
    in_resource = False
    has_root = False
    for line in lines[1:]:
        m = HEADER_RE.match(line)
        if m:
            kind, attrs = m.group(1), dict(ATTR_RE.findall(m.group(2)))
            ident = attrs.get("id", "").strip('"')
            current, in_resource = "", kind == "resource"
            if kind == "ext_resource":
                ext_ids.add(ident)
                ext_paths[ident] = attrs.get("path", "").strip('"')
            elif kind == "sub_resource":
                sub_ids.add(ident)
            elif kind == "node":
                name = attrs.get("name", "").strip('"')
                parent = attrs.get("parent")
                if parent is None:
                    if has_root:
                        errors.append(f"{rel}: more than one root node")
                    has_root = True
                    current = "."
                    continue
                parent = parent.strip('"')
                if parent not in node_paths and not inside_instance(parent, instanced):
                    errors.append(f"{rel}: node {name} has unknown parent {parent}")
                current = name if parent == "." else f"{parent}/{name}"
                node_paths.add(current)
            if kind == "node":
                listed_m = re.search(r"node_paths=PackedStringArray\(([^)]*)\)", m.group(2))
                listed = set(re.findall(r'"([^"]+)"', listed_m.group(1))) if listed_m else set()
                node_props[current] = ("", listed, line)
                if "instance" in attrs:
                    instanced.add(current)
        script = re.match(r'script = ExtResource\("([^"]+)"\)', line)
        if script and current == ".":
            root_script_id = script.group(1)
        if script and current in node_props:
            node_props[current] = (script.group(1),) + node_props[current][1:]
        prop = re.match(r'(\w+) = NodePath\(', line)
        if prop and current:
            nodepath_props.append((current, prop.group(1)))
        if script and in_resource:
            resource_script_id = script.group(1)
        for value in re.findall(r'NodePath\("([^"]*)"\)', line):
            if current:
                node_path_refs.append((current, value))
        used_ext.update(re.findall(r'ExtResource\("([^"]+)"\)', line))
        used_sub.update(re.findall(r'SubResource\("([^"]+)"\)', line))

    for owner, value in node_path_refs:
        target = resolve_node_path(owner, value)
        if target not in node_paths and not inside_instance(target, instanced):
            errors.append(f"{rel}: NodePath(\"{value}\") on {owner} does not resolve")
    for owner, name in nodepath_props:
        script_id, listed, _ = node_props.get(owner, ("", set(), ""))
        if name in listed or declares_nodepath(ext_paths.get(script_id, ""), name):
            continue
        errors.append(f"{rel}: {owner}.{name} = NodePath(...) is not in the node's node_paths")
    if root_script_id in ext_paths:
        check_script_node_refs(rel, ext_paths[root_script_id], node_paths, instanced)
    script_class = header.get("script_class", "").strip('"')
    if script_class:
        actual = class_names.get(ext_paths.get(resource_script_id, ""), "")
        if actual != script_class:
            errors.append(f"{rel}: script_class={script_class}, script declares {actual or 'none'}")

    for ident in used_ext - ext_ids:
        errors.append(f"{rel}: ExtResource {ident} is not declared")
    for ident in used_sub - sub_ids:
        errors.append(f"{rel}: SubResource {ident} is not declared")
    if path.suffix == ".tscn" and not has_root:
        errors.append(f"{rel}: no root node")
    steps = header.get("load_steps")
    if steps is not None and int(steps) != len(ext_ids) + len(sub_ids) + 1:
        errors.append(f"{rel}: load_steps={steps}, expected {len(ext_ids) + len(sub_ids) + 1}")
    check_res_paths(path)


def check_script_node_refs(rel: Path, res_path: str, node_paths: set[str],
                           instanced: set[str]) -> None:
    """Checks $Node/Path lookups of a script attached to a scene's root."""
    script = ROOT / res_path[len("res://"):]
    if not script.is_file():
        return
    for ref in sorted(set(re.findall(r"\$([\w/]+)", script.read_text(encoding="utf-8")))):
        if ref not in node_paths and not inside_instance(ref, instanced):
            errors.append(f"{rel}: {res_path} uses ${ref}, no such node in the scene")


def declares_nodepath(res_path: str, prop: str) -> bool:
    """True if the script declares `prop` with the NodePath type itself."""
    script = ROOT / res_path[len("res://"):] if res_path else None
    if script is None or not script.is_file():
        return False
    return re.search(rf"var\s+{prop}\s*:\s*NodePath\b", script.read_text(encoding="utf-8")) is not None


def collect_class_names() -> None:
    seen: dict[str, str] = {}
    for path in sorted(p for p in ROOT.rglob("*.gd") if not _hidden(p)):
        if ".godot" in path.parts:
            continue
        m = re.search(r"^class_name\s+(\w+)", path.read_text(encoding="utf-8"), re.M)
        if not m:
            continue
        res = "res://" + path.relative_to(ROOT).as_posix()
        if m.group(1) in seen:
            errors.append(f"class_name {m.group(1)} declared in {seen[m.group(1)]} and {res}")
        seen[m.group(1)] = res
        class_names[res] = m.group(1)


def check_gdscript(path: Path) -> None:
    rel = path.relative_to(ROOT)
    for n, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if line.startswith(" "):
            errors.append(f"{rel}:{n}: indented with spaces, use tabs")


def _seg_dist(p, a, b) -> float:
    ax, az = a; bx, bz = b; px, pz = p
    dx, dz = bx - ax, bz - az
    L2 = dx * dx + dz * dz
    k = max(0.0, min(1.0, ((px - ax) * dx + (pz - az) * dz) / L2)) if L2 else 0.0
    return ((ax + dx * k - px) ** 2 + (az + dz * k - pz) ** 2) ** 0.5


def _segments_cross(a, b, c, d) -> bool:
    """True if segments a-b and c-d intersect (crossing or touching)."""
    def orient(p, q, r):
        v = (q[0] - p[0]) * (r[1] - p[1]) - (q[1] - p[1]) * (r[0] - p[0])
        return (v > 1e-9) - (v < -1e-9)
    o1, o2, o3, o4 = orient(a, b, c), orient(a, b, d), orient(c, d, a), orient(c, d, b)
    return o1 != o2 and o3 != o4


def _seg_gap(a, b, c, d) -> float:
    """Distance between segments a-b and c-d (0 if they cross)."""
    if _segments_cross(a, b, c, d):
        return 0.0
    return min(_seg_dist(a, c, d), _seg_dist(b, c, d), _seg_dist(c, a, b), _seg_dist(d, a, b))


def _on_segment(p, a, b) -> bool:
    """True if p lies on the segment a-b."""
    return _seg_dist(p, a, b) < 0.01


# Gate: a path whose last point is this close (taxicab, metres) to the castle centre
# ends at the castle; every other path ends on an earlier one (a T-junction).
GATE_REACH = 1.5
# The last segment of a castle path ("private approach", towers stand beside it) is at
# least this long, and other paths join the approach no closer than this to the castle.
APPROACH_LENGTH = 9.0
# Castle paths: one from each side of the castle (4 screen quadrants).
CASTLE_PATHS = 4
MIN_SLOTS = 14
MAX_SLOTS = 20
SLOTS_PER_SIDE = 2
DIRECTION_COUNT = 8
SCREEN_UP = (-0.7071068, -0.7071068)
SCREEN_RIGHT = (0.7071068, -0.7071068)


def screen_direction(x: float, z: float) -> int:
    """0..7 clockwise from the top of the screen (as LevelCatalog.screen_direction)."""
    import math
    angle = math.atan2(x * SCREEN_RIGHT[0] + z * SCREEN_RIGHT[1], x * SCREEN_UP[0] + z * SCREEN_UP[1])
    return round(angle / (math.pi / 4.0)) % DIRECTION_COUNT


def _is_gate(end, castle) -> bool:
    return abs(end[0] - castle[0]) + abs(end[1] - castle[1]) <= GATE_REACH


def _check_paths(tag: str, lv: dict) -> list:
    """Checks lv["paths"]; returns every segment as (path, index, a, b).

    The first CASTLE_PATHS paths end at the castle gates, one from each side. Every
    other path ends on a segment of an earlier path (a T-junction) and its enemies
    follow that path on to the castle. Segments of all paths keep 3 m apart, except a
    path's last segment and the segment it joins, and the last segments of two castle
    paths next to the castle (they converge on it, 1.6 m apart at the gates).
    """
    x0, z0, w, h = lv["bounds"]
    castle = lv["castle"]
    segs: list = []
    joins: dict = {}  # path -> (path, segment) it ends on
    gates: set = set()
    for k, pts in enumerate(lv["paths"]):
        ptag = f"{tag} path {k}"
        if len(pts) < 2:
            errors.append(f"{ptag}: needs at least 2 points")
            continue
        sx, sz = pts[0]
        if min(abs(sx - x0), abs(sx - x0 - w), abs(sz - z0), abs(sz - z0 - h)) > 0.5:
            errors.append(f"{ptag}: portal {pts[0]} is not on the play area border")
        for i, (a, b) in enumerate(zip(pts, pts[1:])):
            if a[0] != b[0] and a[1] != b[1]:
                errors.append(f"{ptag}: segment {i} is not axis-aligned")
            if ((a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2) ** 0.5 < 1.6:
                errors.append(f"{ptag}: segment {i} shorter than the 0.75 m corner radius x2")
        end, before = pts[-1], pts[-2]
        if _is_gate(end, castle):
            gates.add(k)
            if k >= CASTLE_PATHS:
                errors.append(f"{ptag}: castle paths must come first (paths 0..{CASTLE_PATHS - 1})")
            length = abs(end[0] - before[0]) + abs(end[1] - before[1])
            if length < APPROACH_LENGTH:
                errors.append(f"{ptag}: approach (last segment) is {length:.1f} m, needs {APPROACH_LENGTH}")
        else:
            if k < CASTLE_PATHS:
                errors.append(f"{ptag}: must end at the castle gate (paths 0..{CASTLE_PATHS - 1})")
            host = [(j, i, a, b) for j, i, a, b in segs if _on_segment(end, a, b)]
            if not host:
                errors.append(f"{ptag}: must end on a segment of an earlier path")
            else:
                j, i, a, b = host[0]
                joins[k] = (j, i)
                if (before[1] == end[1]) == (a[1] == b[1]):
                    errors.append(f"{ptag}: last segment must meet path {j} at a right angle")
                corner = min(abs(end[0] - a[0]) + abs(end[1] - a[1]), abs(end[0] - b[0]) + abs(end[1] - b[1]))
                if corner < 1.6:
                    errors.append(f"{ptag}: joins path {j} too close to a corner")
                if ((end[0] - castle[0]) ** 2 + (end[1] - castle[1]) ** 2) ** 0.5 < APPROACH_LENGTH:
                    errors.append(f"{ptag}: joins path {j} within {APPROACH_LENGTH} m of the castle")
        segs += [(k, i, a, b) for i, (a, b) in enumerate(zip(pts, pts[1:]))]
    last = {k: len(pts) - 2 for k, pts in enumerate(lv["paths"])}
    for n, (k1, i, a, b) in enumerate(segs):
        for k2, j, c, d in segs[n + 1:]:
            if k1 == k2 and j <= i + 1:
                continue
            if k1 != k2 and joins.get(k2) == (k1, i) and j == last[k2]:
                continue
            gap = _seg_gap(a, b, c, d)
            if k1 != k2 and k1 in gates and k2 in gates and i == last[k1] and j == last[k2] and gap >= 1.6:
                continue
            if gap < 3.0:
                errors.append(f"{tag}: path {k1} segment {i} and path {k2} segment {j} only {gap:.1f} m apart")
    # One approach from each side of the castle: the four axis directions are the four
    # screen quadrants (the camera looks along (-1, -1, -1)): behind-left, behind-right,
    # in front-left and in front-right.
    sides = set()
    for k in gates:
        pts = lv["paths"][k]
        dx, dz = pts[-2][0] - pts[-1][0], pts[-2][1] - pts[-1][1]
        sides.add((1 if dx > 0 else -1, 0) if abs(dx) > abs(dz) else (0, 1 if dz > 0 else -1))
    if len(gates) != CASTLE_PATHS or len(sides) != 4:
        errors.append(f"{tag}: needs {CASTLE_PATHS} castle paths, one from each side of the castle "
                      f"(found {len(gates)} paths, {len(sides)} sides)")
    portal_sides = {screen_direction(*pts[0]) for pts in lv["paths"]}
    if len(portal_sides) < 4:
        errors.append(f"{tag}: portals must be spread over at least 4 screen directions, found {sorted(portal_sides)}")
    return segs


def _check_lanes(tag: str, lv: dict) -> None:
    """waves.lanes (which paths a wave uses) and waves.elite must fit the paths."""
    waves = lv["waves"]
    n = len(lv["paths"])
    lanes = waves.get("lanes")
    if lanes is None:
        errors.append(f'{tag}: waves.lanes is missing (patterns, scout_paths, boss_paths)')
    else:
        patterns = lanes.get("patterns", [])
        if not patterns:
            errors.append(f"{tag}: waves.lanes.patterns is empty")
        used = [0.0] * n
        for i, pat in enumerate(patterns):
            if len(pat) != n:
                errors.append(f"{tag}: lane pattern {i} has {len(pat)} weights for {n} paths")
                continue
            if min(pat) < 0 or sum(pat) <= 0:
                errors.append(f"{tag}: lane pattern {i} needs non-negative weights with a positive sum")
            used = [u + p for u, p in zip(used, pat)]
        for k, total in enumerate(used):
            if patterns and total <= 0:
                errors.append(f"{tag}: path {k} is never used by any lane pattern")
        for key in ("scout_paths", "boss_paths"):
            ids = lanes.get(key, [])
            if not ids or any(not isinstance(k, int) or not 0 <= k < n for k in ids):
                errors.append(f"{tag}: waves.lanes.{key} must list path indices 0..{n - 1}")
        if n < CASTLE_PATHS:
            errors.append(f"{tag}: needs at least {CASTLE_PATHS} paths")
    elite = waves.get("elite")
    if elite is not None:
        for key in ("from", "every", "step", "kind", "hp", "reward", "scale"):
            if key not in elite:
                errors.append(f"{tag}: waves.elite.{key} is missing")
        if "kind" in elite and not (ROOT / "resources" / "enemies" / f"{elite['kind']}.tres").is_file():
            errors.append(f"{tag}: waves.elite.kind {elite['kind']} has no enemy resource")


def check_rules_lists() -> None:
    """firestore.rules whitelist the keys of users/{uid}.progression (storage abuse);
    a perk or level missing there would make its owner's cloud sync fail."""
    rules = ROOT / "firestore.rules"
    if not rules.is_file():
        return
    text = rules.read_text(encoding="utf-8")
    for perk in sorted((ROOT / "resources" / "perks").glob("*.tres")):
        m = re.search(r'^id = &"([a-z_0-9]+)"', perk.read_text(encoding="utf-8"), re.M)
        if m and f"'{m.group(1)}'" not in text:
            errors.append(f"firestore.rules: perk id '{m.group(1)}' ({perk.name}) is missing in perkKeys()/perksOk()")
    levels = ROOT / "resources" / "levels.json"
    if levels.is_file():
        import json
        for lv in json.loads(levels.read_text(encoding="utf-8"))["levels"]:
            if f"'{lv['id']}'" not in text:
                errors.append(f"firestore.rules: level {lv['id']} is missing in levelKeys()/starsOk()")


def check_levels() -> None:
    """Layout sanity for resources/levels.json (shared by Godot and Blender)."""
    path = ROOT / "resources" / "levels.json"
    if not path.is_file():
        return
    import json
    data = json.loads(path.read_text(encoding="utf-8"))
    for lv in data["levels"]:
        tag = f"levels.json level {lv['id']}"
        # firestore.rules (leaderboards): a record of wave N needs >= (N-1)*15 s of real
        # time = N*30 game seconds at the x2 maximum speed. Faster waves break that bound.
        waves = lv.get("waves", {})
        if waves.get("first_delay", 0) < 30 or waves.get("wave_duration", 0) < 30:
            errors.append(f"{tag}: first_delay and wave_duration must be >= 30 "
                          "(the record time check in firestore.rules assumes it)")
        if "path" in lv or not lv.get("paths"):
            errors.append(f'{tag}: expected "paths": [[...], ...] instead of "path"')
            continue
        _check_lanes(tag, lv)
        x0, z0, w, h = lv["bounds"]
        if abs(x0 + w / 2) > 0.01 or abs(z0 + h / 2) > 0.01:
            errors.append(f"{tag}: bounds must be centred on the origin (build_terrain.py)")
        segs = [(a, b) for _, _, a, b in _check_paths(tag, lv)]
        cx, cz = lv["castle"]
        if not (x0 + 1.2 <= cx <= x0 + w - 1.2 and z0 + 1.2 <= cz <= z0 + h - 1.2):
            errors.append(f"{tag}: castle outside the play bounds")
        _check_slot_sides(tag, lv)
        spots = [("slot", s, 1.3) for s in lv["slots"]] + [("tree", s, 1.2) for s in lv["trees"]]
        spots.append(("hero", lv["hero"], 0.8))
        for kind, s, clearance in spots:
            d = min(_seg_dist(s, a, b) for a, b in segs)
            if d < clearance:
                errors.append(f"{tag}: {kind} {s} is {d:.2f} m from a path (< {clearance})")
            if not (x0 + 0.4 <= s[0] <= x0 + w - 0.4 and z0 + 0.4 <= s[1] <= z0 + h - 0.4):
                errors.append(f"{tag}: {kind} {s} outside the play bounds")
            if abs(s[0] - cx) < 1.6 and abs(s[1] - cz) < 1.6:
                errors.append(f"{tag}: {kind} {s} overlaps the castle")
            for pts in lv["paths"]:
                if ((s[0] - pts[0][0]) ** 2 + (s[1] - pts[0][1]) ** 2) ** 0.5 < 2.0:
                    errors.append(f"{tag}: {kind} {s} blocks the portal at {pts[0]}")
        # Every slot must reach the path with the shortest-ranged tower at level 1.
        reach = _min_tower_range() - REACH_MARGIN
        for sx, sz in lv["slots"]:
            covered = 0.0
            for a, b in segs:
                length = ((b[0] - a[0]) ** 2 + (b[1] - a[1]) ** 2) ** 0.5
                steps = max(1, int(length / 0.25))
                for k in range(steps):
                    t = (k + 0.5) / steps
                    px, pz = a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t
                    if ((px - sx) ** 2 + (pz - sz) ** 2) ** 0.5 <= reach:
                        covered += length / steps
            if covered < MIN_SLOT_COVERAGE:
                errors.append(f"{tag}: slot {[sx, sz]} covers only {covered:.1f} m of path within {reach:.1f} m"
                              f" (needs {MIN_SLOT_COVERAGE})")
        for i, (k1, a, _) in enumerate(spots):
            for k2, b, _ in spots[i + 1:]:
                if ((a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2) ** 0.5 < 1.5:
                    errors.append(f"{tag}: {k1} {a} and {k2} {b} closer than 1.5 m")


def _check_slot_sides(tag: str, lv: dict) -> None:
    """14-20 slots, and at least SLOTS_PER_SIDE beside every approach to the castle."""
    slots = lv["slots"]
    if not MIN_SLOTS <= len(slots) <= MAX_SLOTS:
        errors.append(f"{tag}: {len(slots)} slots, expected {MIN_SLOTS}..{MAX_SLOTS}")
    cx, cz = lv["castle"]
    for k, pts in enumerate(lv["paths"][:CASTLE_PATHS]):
        dx, dz = pts[-2][0] - pts[-1][0], pts[-2][1] - pts[-1][1]
        along_x = abs(dx) > abs(dz)
        sign = (1 if dx > 0 else -1) if along_x else (1 if dz > 0 else -1)
        near = 0
        for sx, sz in slots:
            along = ((sx - cx) if along_x else (sz - cz)) * sign
            side = abs((sz - cz) if along_x else (sx - cx))
            if 1.5 <= along <= 11.0 and side <= 3.5:
                near += 1
        if near < SLOTS_PER_SIDE:
            errors.append(f"{tag}: only {near} slots beside the approach of path {k} (needs {SLOTS_PER_SIDE})")


# Slots: path length (m) the weakest-ranged tower must see, and a safety margin
# for enemies walking slightly off the centre line.
MIN_SLOT_COVERAGE = 3.5
REACH_MARGIN = 0.3


def _hidden(path) -> bool:
    """Not the project: dot-directories (.godot cache, .claude worktrees), the website, and the
    git-ignored build outputs (android/ Gradle template, build/, out/)."""
    parts = path.relative_to(ROOT).parts[:-1]
    return any(part.startswith(".") or part in ("node_modules", "website", "android", "build", "out") for part in parts)


def _min_tower_range() -> float:
    import re
    best = 99.0
    for tres in (ROOT / "resources" / "towers").glob("*.tres"):
        m = re.search(r"range_levels = Array\[float\]\(\[([0-9.]+)", tres.read_text(encoding="utf-8"))
        if m:
            best = min(best, float(m.group(1)))
    return best


def check_export_presets() -> None:
    path = ROOT / "export_presets.cfg"
    if not path.is_file():
        errors.append("export_presets.cfg is missing")
        return
    text = path.read_text(encoding="utf-8")
    if 'package/unique_name="com.bimbleguard.app"' not in text:
        errors.append("export_presets.cfg: package/unique_name must be com.bimbleguard.app")
    if "permissions/internet=true" not in text:
        errors.append("export_presets.cfg: INTERNET permission is required (Online module)")
    for line in text.splitlines():
        if line.startswith("permissions/") and line.endswith("=true"):
            if line != "permissions/internet=true":
                errors.append(f"export_presets.cfg: unexpected permission: {line}")
    if "firebase.cfg" not in text:
        errors.append("export_presets.cfg: include_filter must contain firebase.cfg")


def check_crashlytics() -> None:
    """Crashlytics is the only Firebase SDK allowed (CLAUDE.md): reports only, no Analytics/ads."""
    claude = (ROOT / "CLAUDE.md").read_text(encoding="utf-8")
    if "Crashlytics" not in claude:
        errors.append("CLAUDE.md: the Crashlytics exception is not documented")
    gitignore = (ROOT / ".gitignore").read_text(encoding="utf-8")
    if "google-services.json" not in gitignore:
        errors.append(".gitignore: google-services.json must be ignored (owner's file, not committed)")
    if (ROOT / "google-services.json").is_file():
        warnings.append("google-services.json lies in the project root: keep it out of commits")
    prep = ROOT / "tools" / "prepare_android_build.py"
    if not prep.is_file():
        errors.append("tools/prepare_android_build.py is missing (Gradle template + Crashlytics)")
    else:
        text = prep.read_text(encoding="utf-8")
        for banned in (
            "com.google.firebase:firebase-analytics",
            "com.google.firebase:firebase-messaging",
            "com.google.android.gms:play-services-ads",
        ):
            if banned in text:
                errors.append(f"tools/prepare_android_build.py: {banned} is not allowed")
        if "firebase_analytics_collection_deactivated" not in text:
            errors.append("tools/prepare_android_build.py: Analytics must stay deactivated in the manifest")
    presets = (ROOT / "export_presets.cfg").read_text(encoding="utf-8")
    plain = re.search(r'name="Android"\n.*?gradle_build/use_gradle_build=(\w+)', presets, re.S)
    if plain and plain.group(1) != "false":
        errors.append('export_presets.cfg: preset "Android" must stay without Gradle')


def check_privacy_url() -> None:
    """Warns (does not fail) while the public privacy policy URL is not set."""
    path = ROOT / "scripts" / "game_info.gd"
    hint = "publish docs/PRIVACY.md (see docs/PRIVACY_PUBLISH.md) and set GameInfo.PRIVACY_URL"
    if not path.is_file():
        warnings.append(f"PRIVACY_URL: scripts/game_info.gd not found; {hint}")
        return
    m = re.search(r'^const\s+PRIVACY_URL\s*(?::[^=]+)?:?=\s*"([^"]*)"', path.read_text(encoding="utf-8"), re.M)
    url = m.group(1).strip() if m else ""
    if not url or "TODO" in url.upper():
        warnings.append(f"PRIVACY_URL is empty/TODO (required before store release): {hint}")
    elif not url.startswith("https://"):
        warnings.append(f"PRIVACY_URL must be an https:// URL, got: {url}")


def check_release_constants() -> None:
    """Warns while the other store-release constants of GameInfo are unset."""
    path = ROOT / "scripts" / "game_info.gd"
    if not path.is_file():
        return
    text = path.read_text(encoding="utf-8")
    for name, hint in (
        ("DELETION_URL", "web account-deletion page (Play policy), see docs/RELEASE_READINESS.md"),
        ("SUPPORT_EMAIL", "support e-mail for the policy and store listing"),
    ):
        m = re.search(rf'^const\s+{name}\s*(?::[^=]+)?:?=\s*"([^"]*)"', text, re.M)
        if m is None:
            errors.append(f"scripts/game_info.gd: const {name} is missing")
        elif not m.group(1).strip():
            warnings.append(f"{name} is empty (required before store release): {hint}")
        elif name == "DELETION_URL" and not m.group(1).startswith("https://"):
            warnings.append(f"{name} must be an https:// URL, got: {m.group(1)}")


CYRILLIC = re.compile(r"[А-Яа-яЁё]")
PLACEHOLDER = re.compile(r"%[-+ 0#]*\d*(?:\.\d+)?[sdfxXc%]")
# Cyrillic is allowed in English texts only for a language named in its own script.
EN_CYRILLIC_OK = {"SET_LANG_RU"}
# Russian rows without Cyrillic letters (format-only text, a language name).
RU_LATIN_OK = {
    "CARD_TOWER_TIP",
    "SET_LANG_EN",
    "SET_LANG_ZH",
    "SET_LANG_IT",
    "SET_LANG_ES",
    "SET_LANG_KO",
    "SET_LANG_DE",
    "SET_LANG_PL",
    "SET_LANG_PT",
    "SET_LANG_TR",
    "SET_LANG_FR",
    "SET_LANG_JA",
}


def _strip_comment(line: str) -> str:
    """The line without a trailing # comment (a # inside a string is kept)."""
    in_string = False
    for i, ch in enumerate(line):
        if ch == '"' and (i == 0 or line[i - 1] != "\\"):
            in_string = not in_string
        elif ch == "#" and not in_string:
            return line[:i]
    return line


def check_translations() -> None:
    """translations/strings.csv is complete (ru + en), registered, and the UI
    sources hold no untranslated Cyrillic text. Mark data that must stay
    Cyrillic (reserved names, server-side names) with `# i18n:keep`."""
    import csv

    csv_path = ROOT / "translations" / "strings.csv"
    if not csv_path.is_file():
        errors.append("translations/strings.csv is missing")
        return
    with csv_path.open(encoding="utf-8", newline="") as f:
        rows = list(csv.reader(f))
    expected_langs = ["ru", "en", "zh", "it", "es", "ko", "de", "pl", "pt", "tr", "fr", "ja"]
    if not rows or rows[0][0] != "keys" or rows[0][1:] != expected_langs:
        errors.append(f"translations/strings.csv: header must be keys,{','.join(expected_langs)}")
        return
    keys: set[str] = set()
    num_cols = len(rows[0])
    for row in rows[1:]:
        if len(row) != num_cols:
            errors.append(f"strings.csv: bad row {row[:1]}")
            continue
        key = row[0]
        ru = row[1]
        en = row[2]
        if key in keys:
            errors.append(f"strings.csv: duplicate key {key}")
        keys.add(key)
        for col_idx, lang in enumerate(expected_langs, start=1):
            val = row[col_idx]
            if not val.strip():
                errors.append(f"strings.csv: {key} has an empty translation in {lang}")
            if lang != "ru" and key not in EN_CYRILLIC_OK and CYRILLIC.search(val) and lang not in ("zh", "ja", "ko"):
                errors.append(f"strings.csv: {key}: Cyrillic in the {lang} text")
            if PLACEHOLDER.findall(ru) != PLACEHOLDER.findall(val):
                errors.append(f"strings.csv: {key}: format placeholders differ between ru and {lang}")
        if key not in RU_LATIN_OK and not CYRILLIC.search(ru):
            errors.append(f"strings.csv: {key}: the Russian text has no Cyrillic")
    project = (ROOT / "project.godot").read_text(encoding="utf-8")
    for lang in expected_langs:
        if f"res://translations/strings.{lang}.translation" not in project:
            errors.append(f"project.godot: strings.{lang}.translation is not registered")
    for sub in ("scripts", "scenes", "ui", "resources"):
        for path in sorted((ROOT / sub).rglob("*")):
            if path.suffix not in (".gd", ".tscn", ".tres", ".json") or _hidden(path):
                continue
            rel = path.relative_to(ROOT)
            for n, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
                if "i18n:keep" in line:
                    continue
                code = _strip_comment(line) if path.suffix == ".gd" else line
                if CYRILLIC.search(code):
                    errors.append(f"{rel}:{n}: untranslated Cyrillic text, move it to strings.csv: {code.strip()[:60]}")
                if path.suffix == ".gd":
                    for m in re.finditer(r'\b(?:tr|translate)\(\s*"([A-Z][A-Z0-9_]+)"', code):
                        if m.group(1) not in keys:
                            errors.append(f"{rel}:{n}: translation key {m.group(1)} is not in strings.csv")


def main() -> int:
    check_layout()
    check_export_presets()
    check_crashlytics()
    check_privacy_url()
    check_release_constants()
    check_translations()
    check_levels()
    check_rules_lists()
    check_project_settings()
    collect_class_names()
    for pattern in ("*.tscn", "*.tres"):
        for path in (p for p in ROOT.rglob(pattern) if not _hidden(p)):
            if ".godot" not in path.parts:
                check_scene(path)
    for path in (p for p in ROOT.rglob("*.gd") if not _hidden(p)):
        if ".godot" not in path.parts:
            check_gdscript(path)

    if errors:
        print("FAILED:")
        for e in errors:
            print(f"  - {e}")
        return 1
    for w in warnings:
        print(f"WARNING: {w}")
    print("OK: structure, project settings, scenes and scripts look consistent.")
    print("Note: this is a static check; run the project in Godot to verify it.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Static sanity checks for the Tinyguard Godot project.

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
    "window/handheld/orientation": "0",
}

RES_RE = re.compile(r'res://[^"\s)]+')
HEADER_RE = re.compile(r"^\[(\w+)(.*)\]$")
ATTR_RE = re.compile(r'(\w+)=("[^"]*"|\S+)')

errors: list[str] = []
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
    for path in sorted(ROOT.rglob("*.gd")):
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


def check_levels() -> None:
    """Layout sanity for resources/levels.json (shared by Godot and Blender)."""
    path = ROOT / "resources" / "levels.json"
    if not path.is_file():
        return
    import json
    data = json.loads(path.read_text(encoding="utf-8"))
    for lv in data["levels"]:
        tag = f"levels.json level {lv['id']}"
        x0, z0, w, h = lv["bounds"]
        pts = lv["path"]
        segs = list(zip(pts, pts[1:]))
        for i, (a, b) in enumerate(segs):
            if a[0] != b[0] and a[1] != b[1]:
                errors.append(f"{tag}: path segment {i} is not axis-aligned")
            if ((a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2) ** 0.5 < 1.6:
                errors.append(f"{tag}: path segment {i} shorter than the 0.75 m corner radius x2")
        for i, (a, b) in enumerate(segs):
            for j, (c, d) in enumerate(segs):
                if j <= i + 1:
                    continue
                gap = min(_seg_dist(a, c, d), _seg_dist(b, c, d), _seg_dist(c, a, b), _seg_dist(d, a, b))
                if gap < 3.0:
                    errors.append(f"{tag}: path segments {i} and {j} only {gap:.1f} m apart")
        cx, cz = lv["castle"]
        if not (x0 + 1.2 <= cx <= x0 + w - 1.2 and z0 + 1.2 <= cz <= z0 + h - 1.2):
            errors.append(f"{tag}: castle outside the play bounds")
        spots = [("slot", s, 1.3) for s in lv["slots"]] + [("tree", s, 1.2) for s in lv["trees"]]
        spots.append(("hero", lv["hero"], 0.8))
        for kind, s, clearance in spots:
            d = min(_seg_dist(s, a, b) for a, b in segs)
            if d < clearance:
                errors.append(f"{tag}: {kind} {s} is {d:.2f} m from the path (< {clearance})")
            if not (x0 + 0.4 <= s[0] <= x0 + w - 0.4 and z0 + 0.4 <= s[1] <= z0 + h - 0.4):
                errors.append(f"{tag}: {kind} {s} outside the play bounds")
            if abs(s[0] - cx) < 1.6 and abs(s[1] - cz) < 1.6:
                errors.append(f"{tag}: {kind} {s} overlaps the castle")
        for i, (k1, a, _) in enumerate(spots):
            for k2, b, _ in spots[i + 1:]:
                if ((a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2) ** 0.5 < 1.5:
                    errors.append(f"{tag}: {k1} {a} and {k2} {b} closer than 1.5 m")


def main() -> int:
    check_layout()
    check_levels()
    check_project_settings()
    collect_class_names()
    for pattern in ("*.tscn", "*.tres"):
        for path in ROOT.rglob(pattern):
            if ".godot" not in path.parts:
                check_scene(path)
    for path in ROOT.rglob("*.gd"):
        if ".godot" not in path.parts:
            check_gdscript(path)

    if errors:
        print("FAILED:")
        for e in errors:
            print(f"  - {e}")
        return 1
    print("OK: structure, project settings, scenes and scripts look consistent.")
    print("Note: this is a static check; run the project in Godot to verify it.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

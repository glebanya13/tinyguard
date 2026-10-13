#!/usr/bin/env python3
"""Static sanity checks for the Tinyguard Godot project.

Runs without Godot. Verifies required files/dirs, res:// references in
project.godot and .tscn/.tres files, basic .tscn structure, and that .gd
files are indented with tabs. It does NOT prove the project runs in Godot.

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
    node_paths = {"."}
    has_root = False
    for line in lines[1:]:
        m = HEADER_RE.match(line)
        if m:
            kind, attrs = m.group(1), dict(ATTR_RE.findall(m.group(2)))
            ident = attrs.get("id", "").strip('"')
            if kind == "ext_resource":
                ext_ids.add(ident)
            elif kind == "sub_resource":
                sub_ids.add(ident)
            elif kind == "node":
                name = attrs.get("name", "").strip('"')
                parent = attrs.get("parent")
                if parent is None:
                    if has_root:
                        errors.append(f"{rel}: more than one root node")
                    has_root = True
                    continue
                parent = parent.strip('"')
                if parent not in node_paths:
                    errors.append(f"{rel}: node {name} has unknown parent {parent}")
                node_paths.add(name if parent == "." else f"{parent}/{name}")
        used_ext.update(re.findall(r'ExtResource\("([^"]+)"\)', line))
        used_sub.update(re.findall(r'SubResource\("([^"]+)"\)', line))

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


def check_gdscript(path: Path) -> None:
    rel = path.relative_to(ROOT)
    for n, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if line.startswith(" "):
            errors.append(f"{rel}:{n}: indented with spaces, use tabs")


def main() -> int:
    check_layout()
    check_project_settings()
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

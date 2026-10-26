#!/usr/bin/env python3
"""Версия игры живёт в четырёх местах и должна совпадать: version/code и
version/name в трёх пресетах export_presets.cfg и config/version в project.godot
(AGENTS.md, «Релиз Android»). Скрипт меняет их одной командой и не даёт
разъехаться.

	python3 tools/bump_version.py --check            # только сверить
	python3 tools/bump_version.py patch             # 0.6.3 -> 0.6.4, code +1
	python3 tools/bump_version.py minor             # 0.6.3 -> 0.7.0, code +1
	python3 tools/bump_version.py --name 0.7.0      # code +1 автоматически
	python3 tools/bump_version.py --name 0.7.0 --code 11

version/code растёт с каждой выкладкой в Play и не откатывается
(docs/ANDROID_BUILD.md). Скрипт отказывается понижать code без явного --code.
"""

import argparse
import re
import sys
from pathlib import Path

PRESET_NAMES = r'^version/name="([^"]+)"$'
PRESET_CODES = r"^version/code=(\d+)$"
PROJECT_VERSION = r'^config/version="([^"]+)"$'


class Repo:
	def __init__(self, root: Path):
		self.presets = root / "export_presets.cfg"
		self.project = root / "project.godot"

	def read(self) -> tuple[str, int, list[str]]:
		"""Текущая (name, code, проблемы) — все вхождения обязаны совпадать."""
		preset_text = self.presets.read_text()
		project_text = self.project.read_text()
		names = re.findall(PRESET_NAMES, preset_text, re.M)
		codes = re.findall(PRESET_CODES, preset_text, re.M)
		project = re.findall(PROJECT_VERSION, project_text, re.M)
		problems: list[str] = []
		if len(set(names)) != 1 or len(names) != 3:
			problems.append(f"version/name в пресетах: {names} (ожидалось 3 одинаковых)")
		if len(set(codes)) != 1 or len(codes) != 3:
			problems.append(f"version/code в пресетах: {codes} (ожидалось 3 одинаковых)")
		if len(project) != 1:
			problems.append(f"config/version в project.godot: {project} (ожидался 1)")
		elif names and project[0] != names[0]:
			problems.append(f"config/version={project[0]}, а в пресетах {names[0]}")
		if not names or not codes:
			return ("", 0, problems)
		return (names[0], int(codes[0]), problems)

	def write(self, name: str, code: int) -> None:
		preset_text = self.presets.read_text()
		preset_text, n_names = re.subn(PRESET_NAMES, f'version/name="{name}"', preset_text, flags=re.M)
		preset_text, n_codes = re.subn(PRESET_CODES, f"version/code={code}", preset_text, flags=re.M)
		project_text = self.project.read_text()
		project_text, n_project = re.subn(
			PROJECT_VERSION, f'config/version="{name}"', project_text, flags=re.M
		)
		if (n_names, n_codes, n_project) != (3, 3, 1):
			sys.exit(f"записано неожиданное число замен: {n_names}, {n_codes}, {n_project}")
		self.presets.write_text(preset_text)
		self.project.write_text(project_text)


def bump_name(name: str, part: str) -> str:
	major, minor, patch = (int(x) for x in name.split("."))
	if part == "major":
		return f"{major + 1}.0.0"
	if part == "minor":
		return f"{major}.{minor + 1}.0"
	return f"{major}.{minor}.{patch + 1}"


def main() -> int:
	parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
	parser.add_argument("part", nargs="?", choices=("patch", "minor", "major"))
	parser.add_argument("--name", help="новая version/name (X.Y.Z)")
	parser.add_argument("--code", type=int, help="новая version/code (по умолчанию: +1)")
	parser.add_argument("--check", action="store_true", help="только сверить четыре места")
	parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parent.parent)
	args = parser.parse_args()

	repo = Repo(args.root)
	name, code, problems = repo.read()
	for p in problems:
		print("ПРОБЛЕМА: " + p)
	if problems:
		return 1
	print(f"сейчас: {name} (код {code})")
	if args.check:
		print("готово")
		return 0

	new_name = args.name or bump_name(name, args.part or "patch")
	if not re.fullmatch(r"\d+\.\d+\.\d+", new_name):
		sys.exit(f"--name {new_name}: ожидается X.Y.Z")
	new_code = args.code if args.code is not None else code + 1
	if new_code <= code:
		sys.exit(f"code не растёт: {code} -> {new_code} (Play не примет; явно укажите --code)")
	repo.write(new_name, new_code)
	print(f"стало:  {new_name} (код {new_code}) — export_presets.cfg ×3 и project.godot")
	return 0


if __name__ == "__main__":
	sys.exit(main())

#!/usr/bin/env python3
"""Готовит Android-шаблон Gradle (android/build) к сборке с Firebase Crashlytics.

Каталог android/ не коммитится, поэтому всё, что нужно шаблону сверх стандартного,
делает этот скрипт. Он идемпотентен: повторный запуск ничего не дублирует.

  python3 tools/prepare_android_build.py                 # подготовить
  python3 tools/prepare_android_build.py --check         # только проверить, что готово
  python3 tools/prepare_android_build.py --google-services ПУТЬ --templates КАТАЛОГ

Что делает:
  1. распаковывает android_source.zip из export templates в android/build (если нет),
     пишет android/.build_version и android/.gdignore (иначе Godot импортирует шаблон);
  2. копирует google-services.json владельца в android/build/ (в git НЕ попадает);
  3. добавляет плагины google-services и crashlytics (settings.gradle, build.gradle),
     зависимости firebase-bom + firebase-crashlytics(-ndk), nativeSymbolUploadEnabled=false;
  4. вписывает в src/main/AndroidManifest.xml мета-данные: сбор отчётов и Analytics выключены
     (сбор Crashlytics включает код игры, если игрок не отказался; см. CrashReporter).

Только стандартная библиотека Python.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ANDROID = ROOT / "android"
BUILD = ANDROID / "build"
GODOT_VERSION = "4.7.2.stable"

# Версии проверены на совместимость с AGP 8.6.1 / Gradle 8.11.1 / Kotlin 2.1.21 шаблона 4.7.2
# (docs/ANDROID_BUILD.md). Менять осознанно, после проверки `gradlew :dependencies`.
GOOGLE_SERVICES_VERSION = "4.4.4"
CRASHLYTICS_GRADLE_VERSION = "3.0.6"
FIREBASE_BOM_VERSION = "34.19.0"

MARK = "bimbleguard-crashlytics"

MANIFEST_META = [
	# Сбор выключен до явного решения кода: игрок мог отказаться в настройках.
	("firebase_crashlytics_collection_enabled", "false"),
	# Ничего из Firebase не собирается само; Crashlytics включается кодом.
	("firebase_data_collection_default_enabled", "false"),
	# Analytics не используется. Если библиотека всё же появится рядом, она молчит.
	("firebase_analytics_collection_deactivated", "true"),
	("firebase_analytics_collection_enabled", "false"),
	("google_analytics_adid_collection_enabled", "false"),
	("google_analytics_default_allow_ad_storage", "false"),
	("google_analytics_default_allow_ad_user_data", "false"),
	("google_analytics_default_allow_ad_personalization_signals", "false"),
	("google_analytics_default_allow_analytics_storage", "false"),
]


def default_templates_dir() -> Path:
	if sys.platform == "darwin":
		base = Path.home() / "Library/Application Support/Godot/export_templates"
	elif sys.platform.startswith("win"):
		base = Path(os.environ.get("APPDATA", "")) / "Godot/export_templates"
	else:
		base = Path.home() / ".local/share/godot/export_templates"
	return base / GODOT_VERSION


def default_google_services() -> Path | None:
	env = os.environ.get("GOOGLE_SERVICES_JSON")
	candidates = [Path(env)] if env else []
	candidates += [ROOT / "google-services.json", Path.home() / "Downloads/google-services.json"]
	for path in candidates:
		if path.is_file():
			return path
	return None


def log(msg: str) -> None:
	print("prepare_android_build: " + msg)


def ensure_template(templates: Path) -> None:
	if not (BUILD / "build.gradle").is_file():
		zip_path = templates / "android_source.zip"
		if not zip_path.is_file():
			sys.exit(f"нет {zip_path}: установите export templates {GODOT_VERSION}")
		log(f"распаковываю {zip_path.name} в {BUILD}")
		BUILD.mkdir(parents=True, exist_ok=True)
		with zipfile.ZipFile(zip_path) as zf:
			zf.extractall(BUILD)
		# extractall не хранит бит исполнения.
		(BUILD / "gradlew").chmod(0o755)
	ANDROID.mkdir(exist_ok=True)
	(ANDROID / ".build_version").write_text(GODOT_VERSION)
	(ANDROID / ".gdignore").touch()
	for imp in ANDROID.rglob("*.import"):
		imp.unlink()  # Godot мог проиндексировать шаблон до .gdignore


def validate_google_services(path: Path) -> None:
	data = json.loads(path.read_text(encoding="utf-8"))
	packages = [
		c.get("client_info", {}).get("android_client_info", {}).get("package_name")
		for c in data.get("client", [])
	]
	if "com.bimbleguard.app" not in packages:
		sys.exit(f"{path}: нет клиента com.bimbleguard.app (есть: {packages})")


def patch_settings() -> bool:
	path = BUILD / "settings.gradle"
	text = path.read_text()
	if MARK in text:
		return False
	anchor = "id 'org.jetbrains.kotlin.android' version versions.kotlinVersion\n"
	if anchor not in text:
		sys.exit("settings.gradle: не найден якорь plugins (шаблон другой версии?)")
	add = (
		f"        // {MARK}\n"
		f"        id 'com.google.gms.google-services' version '{GOOGLE_SERVICES_VERSION}'\n"
		f"        id 'com.google.firebase.crashlytics' version '{CRASHLYTICS_GRADLE_VERSION}'\n"
	)
	path.write_text(text.replace(anchor, anchor + add, 1))
	return True


def patch_build_gradle() -> bool:
	path = BUILD / "build.gradle"
	text = path.read_text()
	if MARK in text:
		return False
	anchor = "    id 'org.jetbrains.kotlin.android'\n}"
	if anchor not in text:
		sys.exit("build.gradle: не найден блок plugins (шаблон другой версии?)")
	plugins = (
		"    id 'org.jetbrains.kotlin.android'\n"
		f"    // {MARK}: google-services строго перед crashlytics\n"
		"    id 'com.google.gms.google-services'\n"
		"    id 'com.google.firebase.crashlytics'\n}"
	)
	text = text.replace(anchor, plugins, 1)
	dep_anchor = '    implementation "androidx.documentfile:documentfile:$versions.documentfileVersion"\n'
	if dep_anchor not in text:
		sys.exit("build.gradle: не найден якорь dependencies")
	deps = (
		f"\n    // {MARK}: только отчёты о сбоях; Analytics и реклама не подключаются\n"
		f"    implementation platform('com.google.firebase:firebase-bom:{FIREBASE_BOM_VERSION}')\n"
		"    implementation 'com.google.firebase:firebase-crashlytics'\n"
		"    implementation 'com.google.firebase:firebase-crashlytics-ndk'\n"
	)
	text = text.replace(dep_anchor, dep_anchor + deps, 1)
	text += (
		f"\n// {MARK}: символы нативных библиотек Godot не загружаем (docs/DEBUG_ANDROID.md)\n"
		"android.buildTypes.configureEach { buildType ->\n"
		"    buildType.firebaseCrashlytics {\n"
		"        nativeSymbolUploadEnabled false\n"
		"        mappingFileUploadEnabled false\n"
		"    }\n"
		"}\n"
	)
	path.write_text(text)
	return True


def patch_manifest() -> bool:
	path = BUILD / "src/main/AndroidManifest.xml"
	text = path.read_text()
	if MARK in text:
		return False
	lines = [f"        <!-- {MARK} -->"]
	for name, value in MANIFEST_META:
		lines.append(f'        <meta-data android:name="{name}" android:value="{value}" />')
	block = "\n".join(lines) + "\n\n"
	anchor = "        <activity\n            android:name=\".GodotApp\""
	if anchor not in text:
		sys.exit("AndroidManifest.xml: не найден якорь activity")
	path.write_text(text.replace(anchor, block + anchor, 1))
	return True


def check() -> list[str]:
	"""Список проблем; пустой, если шаблон готов."""
	problems: list[str] = []
	files = {
		"settings.gradle": BUILD / "settings.gradle",
		"build.gradle": BUILD / "build.gradle",
		"src/main/AndroidManifest.xml": BUILD / "src/main/AndroidManifest.xml",
	}
	for name, path in files.items():
		if not path.is_file():
			problems.append(f"нет {name}")
		elif MARK not in path.read_text():
			problems.append(f"{name} не пропатчен")
	if not (BUILD / "google-services.json").is_file():
		problems.append("нет android/build/google-services.json")
	if not (ANDROID / ".gdignore").is_file():
		problems.append("нет android/.gdignore")
	return problems


def main() -> int:
	parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
	parser.add_argument("--templates", type=Path, default=default_templates_dir())
	parser.add_argument("--google-services", type=Path, default=default_google_services())
	parser.add_argument("--check", action="store_true", help="только проверить")
	args = parser.parse_args()

	if args.check:
		problems = check()
		for p in problems:
			log("ПРОБЛЕМА: " + p)
		log("готово" if not problems else "не готово")
		return 1 if problems else 0

	ensure_template(args.templates)
	target = BUILD / "google-services.json"
	if args.google_services is None:
		if not target.is_file():
			sys.exit(
				"нет google-services.json: Firebase Console → Project settings → Your apps → "
				"google-services.json; положите в ~/Downloads или укажите --google-services"
			)
	else:
		validate_google_services(args.google_services)
		shutil.copyfile(args.google_services, target)
		log(f"google-services.json скопирован из {args.google_services}")
	changed = [patch_settings(), patch_build_gradle(), patch_manifest()]
	log("пропатчено" if any(changed) else "уже было подготовлено")
	problems = check()
	for p in problems:
		log("ПРОБЛЕМА: " + p)
	return 1 if problems else 0


if __name__ == "__main__":
	sys.exit(main())

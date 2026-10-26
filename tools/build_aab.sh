#!/usr/bin/env bash
# AAB для Google Play одной командой: подготовка шаблона Gradle, экспорт,
# проверка подписи. Вместо шести шагов из docs/ANDROID_BUILD.md («AAB для
# Google Play» + «Crashlytics»). Секреты берутся из ~/.bimbleguard-keys и в
# вывод не попадают; версию до сборки поднимает tools/bump_version.py.
#
#   tools/build_aab.sh            # собрать build/bimbleguard.aab
#   tools/build_aab.sh --check    # только проверить готовность машины
set -euo pipefail

KEYS=${BIMBLEGUARD_KEYS:-$HOME/.bimbleguard-keys}
GODOT=${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}
# Отпечаток ключа загрузки (docs/ANDROID_BUILD.md); сборка подписывается им же.
EXPECTED_FP="CC:6E:CB:E8:BA:C1:CC:3B:95:FB:0A:D5:C8:B9:2A:8D:90:F7:4C:20:75:5F:49:B3:60:B5:82:02:91:40:63:51"

command -v "$GODOT" >/dev/null 2>&1 || [ -x "$GODOT" ] || { echo "нет Godot: $GODOT"; exit 1; }
[ -f "$KEYS/upload.keystore" ] || { echo "нет $KEYS/upload.keystore"; exit 1; }
[ -f "$KEYS/upload.pass" ] || { echo "нет $KEYS/upload.pass"; exit 1; }
JAVA_HOME=${JAVA_HOME:-$(/usr/libexec/java_home -v 17 2>/dev/null || true)}
[ -n "$JAVA_HOME" ] || { echo "нет JDK 17 (/usr/libexec/java_home -v 17)"; exit 1; }
export JAVA_HOME
export GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$KEYS/upload.keystore"
export GODOT_ANDROID_KEYSTORE_RELEASE_USER=bimbleguard-upload
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD
GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="$(cat "$KEYS/upload.pass")"

python3 tools/prepare_android_build.py

if [ "${1:-}" = "--check" ]; then
	echo "готово: сборка возможна (Godot, JDK 17, keystore, шаблон Gradle)"
	exit 0
fi

mkdir -p build
"$GODOT" --headless --path . --export-release "Android Play (AAB)" build/bimbleguard.aab

echo "== проверка подписи =="
"$JAVA_HOME/bin/jarsigner" -verify build/bimbleguard.aab | head -1
ACTUAL_FP=$("$JAVA_HOME/bin/keytool" -printcert -jarfile build/bimbleguard.aab \
	| grep 'SHA256:' | head -1 | sed 's/.*SHA256: *//' | tr -d ' :' | tr 'a-f' 'A-F')
EXPECTED_FLAT=$(echo "$EXPECTED_FP" | tr -d ' :')
if [ "$ACTUAL_FP" != "$EXPECTED_FLAT" ]; then
	echo "ОТПЕЧАТОК НЕ СОВПАЛ: $ACTUAL_FP"
	exit 1
fi
echo "отпечаток ключа загрузки совпал"
ls -lh build/bimbleguard.aab

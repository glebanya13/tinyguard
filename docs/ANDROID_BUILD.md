# Сборка Android (Bimbleguard)

> **Статус: сборка APK не проверена.** На машине разработчика (macOS, Godot 4.7.2) есть
> JDK 17 (Temurin), Android SDK (`~/Library/Android/sdk`, build-tools 33–36, platforms 28–37)
> и `~/.android/debug.keystore`, но **не установлены export templates 4.7.2**
> (`godot --headless --export-debug Android` падает с «Шаблоны экспорта не найдены»
> и «Требуется указать верный путь к Java SDK»). Ниже — инструкция, а не отчёт о выполненной
> сборке. Проверенное: `export_presets.cfg` читается Godot 4.7.2, пресет находится, ошибки
> конфигурации — только перечисленные (templates, путь к Java SDK в настройках редактора).

## Что настроено в `export_presets.cfg`

| Параметр | Значение | Зачем |
|---|---|---|
| `package/unique_name` | `com.bimbleguard.app` | id приложения; после публикации менять нельзя |
| `package/name` | `Bimbleguard` | название под иконкой |
| `version/name` / `version/code` | `0.5.0` / `5` | **`code` увеличивать на каждую выкладку**; `name` = `config/version` |
| Иконки | `res://icon.png`, адаптивные `ui/app/icon_foreground.png`, `icon_background.png` | |
| Ориентация | `project.godot`: `window/handheld/orientation=4` (сенсорная альбомная) | проверяется `validate_project.py` |
| Архитектуры | только `arm64-v8a` | все Android 2020+; `armeabi-v7a` отключён ради размера |
| Разрешения | только `INTERNET` | модуль `Online` (Firebase REST); `validate_project.py` падает при других |
| `include_filter` | `firebase.cfg` | файл не в git, но должен попасть в сборку, если лежит рядом |
| `exclude_filter` | tools, tests, docs, wip, firebase, assets/blender, `*.md`… | не тянуть лишнее в APK |
| `gradle_build/use_gradle_build` | `false` | обычный APK из готового шаблона, без Android build template |
| `package/signed` | `true` | debug-сборка подписывается debug keystore |

Игра без `firebase.cfg` полностью работает офлайн; для сборки с онлайном положите
`firebase.cfg` в корень проекта (см. `docs/FIREBASE.md`) — ключ Firebase Web API **публичный**
и не секрет, но файл в git не коммитится.

## Пошагово (debug APK)

1. **Godot 4.7.2** (ровно эта версия, см. `CLAUDE.md`) и **export templates** той же версии:
   Godot → Editor → Manage Export Templates → Download and Install
   (или вручную: `.tpz` с godotengine.org распаковать в
   `~/Library/Application Support/Godot/export_templates/4.7.2.stable/`).
2. **JDK 17**: `java -version` → 17. На macOS: `brew install --cask temurin@17`.
3. **Android SDK**: command-line tools, `platform-tools`, `build-tools;35.0.0` (или 34),
   `platforms;android-35`. Принять лицензии: `sdkmanager --licenses`.
4. **Debug keystore** (если нет `~/.android/debug.keystore`):
   ```
   keytool -keyalg RSA -genkeypair -alias androiddebugkey -keypass android \
     -keystore ~/.android/debug.keystore -storepass android \
     -dname "CN=Android Debug,O=Android,C=US" -validity 9999 -deststoretype pkcs12
   ```
5. **Пути в настройках редактора** (Editor → Editor Settings → Export → Android):
   `Java SDK Path` = `/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home`
   (или вывод `/usr/libexec/java_home -v 17`), `Android SDK Path` = `~/Library/Android/sdk`,
   `Debug Keystore` = `~/.android/debug.keystore`, user `androiddebugkey`, пароль `android`.
   Эти настройки хранятся вне проекта (в `editor_settings-4.7.tres`), в git не попадают.
6. Импорт и экспорт из консоли:
   ```
   godot --headless --path . --import
   mkdir -p build
   godot --headless --path . --export-debug "Android" build/bimbleguard.apk
   ```
   `build/` в `.gitignore`.
7. Установка на устройство (USB-отладка включена): `adb install -r build/bimbleguard.apk`.
8. Проверить: запуск в альбомной ориентации, значок и заставка, работа без сети,
   `adb logcat -s godot` без ошибок, FPS и размеры кнопок (см. `docs/HANDOFF.md`).

## Релиз для Google Play (не проверено)

- Свой release keystore **вне репозитория** (`*.keystore`/`*.jks` в `.gitignore`);
  пароли — только в `export_credentials.cfg` (в `.gitignore`) или переменных окружения
  `GODOT_ANDROID_KEYSTORE_RELEASE_*`, не в `export_presets.cfg`.
- Google Play требует **AAB**: нужен Gradle-экспорт — в редакторе Project → Install Android
  Build Template (создаёт `android/`, в `.gitignore`), затем в пресете
  `gradle_build/use_gradle_build=true`, `gradle_build/export_format=1`; `target SDK` должен
  соответствовать текущему требованию Play. Это изменение пресета нужно проверить отдельно.
- Перед публикацией: ссылка на политику конфиденциальности (`docs/PRIVACY_PUBLISH.md`),
  заполненная форма Data safety (см. `docs/PRIVACY.md`: ID гостя, имя, прогресс; без рекламы
  и аналитики).

## AAB для Google Play (проверено 2026-10-15)

Собрано и проверено `jarsigner`: пакет `com.bimbleguard.app`, версия 0.5.0 (код 5), target SDK 36,
только arm64-v8a, разрешение только `INTERNET`, подпись — ключ загрузки (не отладочный).
**На устройстве AAB не запускался**; в Play он тоже не загружался.

Пресет `Android Play (AAB)` в `export_presets.cfg` (Gradle, `export_format=1`, `target_sdk=36`).
Нужно один раз: шаблон Gradle (`unzip android_source.zip -d android/build`, файл
`android/.build_version` = `4.7.2.stable`; каталог `android/` не коммитится), Android SDK
Build-Tools и платформа 36 (Gradle докачивает сам), JDK 17.

```bash
K=~/.bimbleguard-keys   # upload.keystore + upload.pass, вне репозитория
export JAVA_HOME=/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home
export GODOT_ANDROID_KEYSTORE_RELEASE_PATH=$K/upload.keystore
export GODOT_ANDROID_KEYSTORE_RELEASE_USER=bimbleguard-upload
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="$(cat $K/upload.pass)"
godot --headless --path . --export-release "Android Play (AAB)" build/bimbleguard.aab
```

В настройках редактора Godot (`editor_settings-4.7.tres`) должен быть задан
`export/android/java_sdk_path`; открытый редактор может сбросить его при сохранении.
Первая сборка долгая: Gradle скачивает свой дистрибутив (~130 МБ) и зависимости.

**Ключ загрузки** (`~/.bimbleguard-keys/`): алиас `bimbleguard-upload`, RSA 2048, срок 10000 дней,
SHA-256 отпечаток `CC:6E:CB:E8:BA:C1:CC:3B:95:FB:0A:D5:C8:B9:2A:8D:90:F7:4C:20:75:5F:49:B3:60:B5:82:02:91:40:63:51`.
Храните копию хранилища и пароля отдельно: без них новый вариант подписи для Play придётся
запрашивать у поддержки. Включите Play App Signing при первой загрузке.
Перед каждой новой публикацией увеличьте `version/code` в обоих пресетах.

**Если Gradle падает на «The file name must end with .xml or .png»** (проверено 2026-10-17): Godot проиндексировал
служебную папку `android/build` и создал в ней файлы `*.import`. Нужно: `touch android/.gdignore` (папка
`android/` не коммитится), удалить сгенерированные `find android -name "*.import" -delete` и собрать заново.

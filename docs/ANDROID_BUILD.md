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
| `version/name` / `version/code` | `0.5.1` / `6` | **`code` увеличивать на каждую выкладку**; `name` = `config/version` |
| Иконки | `res://icon.png`, адаптивные `ui/app/icon_foreground.png`, `icon_background.png` | |
| Ориентация | `project.godot`: `window/handheld/orientation=4` (сенсорная альбомная) | проверяется `validate_project.py` |
| Архитектуры | только `arm64-v8a` | все Android 2020+; `armeabi-v7a` отключён ради размера (+~25 МБ AAB за ABI; охват и решение: `docs/DEVICE_COMPATIBILITY.md`, разд. 1) |
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

## Crashlytics: подготовка шаблона Gradle (2026-10-17)

Отчёты о сбоях (Firebase Crashlytics) есть **только в Gradle-сборках**: пресеты «Android Play (AAB)»
и «Android Debug (Gradle)» (APK, `use_gradle_build=true`). Пресет «Android» (обычный APK из готового
шаблона, без Gradle) остаётся как был: Crashlytics в нём нет, игра работает без него (проверено: он
собирается). Решение владельца и границы: `CLAUDE.md` (только Crashlytics, без Analytics и рекламы).

Каталог `android/` не коммитится, поэтому всё готовит скрипт (идемпотентный, только stdlib Python):

```bash
python3 tools/prepare_android_build.py            # подготовить; повтор безопасен
python3 tools/prepare_android_build.py --check    # проверить, что всё на месте
```

Что он делает: распаковывает `android_source.zip` из export templates в `android/build` (если там
пусто), пишет `android/.build_version` и `android/.gdignore`, **копирует `google-services.json`** в
`android/build/`, правит `settings.gradle` и `build.gradle` (плагины `com.google.gms.google-services`
4.4.4 и `com.google.firebase.crashlytics` 3.0.6 — google-services строго перед crashlytics;
зависимости `firebase-bom:34.19.0`, `firebase-crashlytics`, `firebase-crashlytics-ndk`;
`nativeSymbolUploadEnabled false`, `mappingFileUploadEnabled false`) и `src/main/AndroidManifest.xml`
(мета-данные: `firebase_crashlytics_collection_enabled=false`, `firebase_data_collection_default_enabled=false`,
Analytics выключен: `firebase_analytics_collection_deactivated=true`, `google_analytics_adid_collection_enabled=false`,
все `google_analytics_default_allow_*=false`). Манифест правится в `src/main`, а не в `src/release|debug`:
эти два Godot перезаписывает при каждом экспорте.

**`google-services.json`** — файл владельца с публичным конфигом клиента Firebase; в репозиторий **не
коммитится** (`.gitignore`). Взять: Firebase Console → Project settings → Your apps → (Android-приложение
`com.bimbleguard.app`) → `google-services.json`. Скрипт ищет его в `$GOOGLE_SERVICES_JSON`,
`./google-services.json`, `~/Downloads/google-services.json` или по `--google-services ПУТЬ`
и проверяет, что в нём есть клиент `com.bimbleguard.app`.

Версии проверены на совместимость с шаблоном 4.7.2 (AGP 8.6.1, Gradle 8.11.1, Kotlin 2.1.21, JDK 17):
обе сборки (AAB и debug APK) собрались. Менять версии осознанно и сверяться с
`./gradlew :dependencies --configuration standardReleaseRuntimeClasspath` (в `android/build`):
в дереве есть `firebase-crashlytics(-ndk)`, installations, sessions, datatransport и
`firebase-measurement-connector` (только интерфейсы); **`firebase-analytics` и
`play-services-measurement` не подтягиваются**.

Сборка (пути и подпись как выше; `JAVA_HOME` — JDK 17):

```bash
python3 tools/prepare_android_build.py
godot --headless --path . --export-release "Android Play (AAB)" build/bimbleguard.aab   # Play
godot --headless --path . --export-debug "Android Debug (Gradle)" build/bimbleguard-debug.apk  # тест
```

Проверка собранного (результаты 2026-10-17):

| Проверка | Как | Результат |
|---|---|---|
| Размер AAB | `ls -l build/bimbleguard.aab` | было 50 861 198 Б (до Crashlytics), стало 52 587 796 Б (+1,73 МБ, +3,4 %); debug APK (Gradle) 107 441 021 Б, обычный APK 53 033 392 Б |
| Разрешения | `aapt2 dump badging` (APK) | `INTERNET` и `ACCESS_NETWORK_STATE` (второе добавляет Firebase; в пресетах только INTERNET) |
| Классы в dex | `dexdump` | `com/google/firebase/crashlytics/FirebaseCrashlytics`, sessions, installations; нативные `libcrashlytics*.so` (arm64-v8a) |
| Манифест | `aapt2 dump xmltree --file AndroidManifest.xml` | сбор Crashlytics и Analytics выключены, перечисленные мета-данные на месте; `FirebaseInitProvider`, `ComponentDiscoveryService`, `SessionLifecycleService` добавлены библиотеками |
| Подпись AAB | `jarsigner -verify` | jar verified; SHA-256 `CC:6E:CB:E8:BA:C1:CC:3B:95:FB:0A:D5:C8:B9:2A:8D:90:F7:4C:20:75:5F:49:B3:60:B5:82:02:91:40:63:51` (= ключ загрузки) |
| Подпись debug APK | `apksigner verify --print-certs` | ключ Android Debug |
| `google-services` | значения клиента попали в ресурсы AAB | `google_app_id`, `project_id`, `google_api_key`… |

**На устройстве и в эмуляторе не запускалось: реальная отправка отчётов не проверена.** Вызовы из
GDScript идут через `JavaClassWrapper` (`scripts/crash_reporter.gd`, `scripts/exit_reasons.gd`) и
проверены только на компьютере (no-op и подставной объект в `tests/test_exit_reasons.gd`).

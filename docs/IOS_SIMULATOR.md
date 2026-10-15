# Запуск на симуляторе iPhone (только для проверки)

Платформа игры — Android. Симулятор iPhone нужен лишь чтобы посмотреть игру и снять кадры
на вытянутом экране с вырезом. Это **не** поддерживаемая цель сборки: iOS-пресета в
`export_presets.cfg` нет. Проверено 2026-10-15: Godot 4.7.2, Xcode 26.4, iPhone 16 (iOS 18.6),
Mac на Apple Silicon.

## Что ограничивает

- Официальный шаблон `ios.zip` (Godot 4.7.2) кладёт в слот симулятора **только x86_64**, нативной
  arm64-версии для симулятора нет. На Apple Silicon игра идёт через Rosetta: медленно,
  первая загрузка уровня около минуты (серый экран), FPS ничего не говорит о телефоне.
- Игра альбомная, а симулятор стартует портретным и сам не поворачивается: экран виден
  повёрнутым на 90°. Для кадров достаточно повернуть PNG (`PIL: rotate(90, expand=True)`).
- Освещение на симуляторе заметно темнее, чем на десктопе: сравнивать цвета с Android нельзя.

## Шаги

1. Шаблон: из `Godot_v4.7.2-stable_export_templates.tpz` извлечь `templates/ios.zip` в
   `~/Library/Application Support/Godot/export_templates/4.7.2.stable/`.
2. Добавить в `export_presets.cfg` **временный** пресет `iOS` (не коммитить):
   `platform="iOS"`, `export_path="build/ios/Bimbleguard.xcodeproj"`,
   `include_filter="firebase.cfg"`, опции `application/bundle_identifier="com.bimbleguard.app"`,
   `application/app_store_team_id="0000000000"` (фиктивный, подпись не нужна),
   `application/min_ios_version="15.0"`, `application/export_project_only=true`.
3. Экспорт: `godot --headless --path . --export-debug "iOS" build/ios/Bimbleguard.xcodeproj`.
4. Сборка под симулятор (обязательно x86_64):
   ```bash
   xcodebuild -project build/ios/Bimbleguard.xcodeproj -scheme Bimbleguard -configuration Debug \
     -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath build/ios_dd \
     ARCHS=x86_64 ONLY_ACTIVE_ARCH=NO EXCLUDED_ARCHS=arm64 CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" build
   ```
   Без `ARCHS=x86_64` линкер падает с `Undefined symbols: _main`.
5. Установка и запуск (офлайн, чтобы не трогать настоящий Firebase-проект):
   ```bash
   xcrun simctl install booted build/ios_dd/Build/Products/Debug-iphonesimulator/Bimbleguard.app
   SIMCTL_CHILD_BIMBLEGUARD_OFFLINE=1 xcrun simctl launch booted com.bimbleguard.app
   ```
   `BIMBLEGUARD_OFFLINE=1` отключает `firebase.cfg` (см. `scripts/online.gd`). Без неё сборка
   с `firebase.cfg` при запуске сама входит гостем в настоящий проект.

## Что показал запуск

- Игра стартует, экран ника и первый уровень с туториалом отрисованы, ввод работает.
  Кадры: `docs/screenshots/ios_sim_nickname.jpg`, `ios_sim_tutorial.jpg`.
- Вырез (Dynamic Island) на повёрнутом кадре виден слева: игра не учитывает безопасную зону.
  Для Android с вырезом камеры и жестовой панелью это тоже стоит учесть (`DisplayServer.get_display_safe_area()`).

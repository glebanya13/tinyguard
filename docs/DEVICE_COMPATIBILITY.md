# Совместимость с Android-устройствами (аудит перед закрытым тестом)

Дата: 2026-10-17. Версия: 0.5.0 (versionCode 5), Godot 4.7.2, Compatibility (OpenGL ES 3.0).
**Реальные устройства не использовались; эмуляторы не запускались.** Всё ниже — чтение кода и
сборки, headless-тесты и документация. Что не подтверждено, помечено «не проверено».
Ссылки собраны 2026-10-17; правила и числа Google меняются.

## Главные риски (по убыванию)

### Блокеры
Блокеров совместимости в коде не найдено. Остаются блокеры релиза из `docs/RELEASE_READINESS.md`
(политика, аккаунт, тест 12 человек) и первый запуск на реальном железе (никогда не делался).

### Высокие
1. **MSAA 3D в Compatibility на Android: рост нативной памяти.** Открытые баги Godot
   [#97967](https://github.com/godotengine/godot/issues/97967) (Mali-G57 MC2, «растёт непрерывно, возможны
   падения после простоя») и [#124258](https://github.com/godotengine/godot/issues/124258) (4.7.2, Pixel 9 Pro XL
   Mali и Galaxy S23 Ultra Adreno 740: ~5 МБ/с, но только при MSAA + `scaling_3d_scale < 1`). Наш проект
   имел `msaa_3d=1` (2x) на телефонах: ровно «лагает, потом вылетает» из `docs/SOAK_REPORT.md`.
   **Исправлено:** `anti_aliasing/quality/msaa_3d.mobile=0` в `project.godot`, превью Лавки на телефоне тоже
   без MSAA. Цена: чуть более «лесенчатые» края (на 1080p+ терпимо; владелец может вернуть, сверив с
   актуальным состоянием бага).
2. **Первый запуск на реальном телефоне не выполнен** (`docs/SOAK_REPORT.md`, `docs/ANDROID_BUILD.md`).
   Нужны хотя бы 3 устройства из плана ниже до рассылки тестерам.
3. **Память на 2–3 ГБ телефонах (lowmemorykiller).** Замеры только на компьютере: RSS 128–340 МБ,
   VRAM ~55 МБ (все текстуры без сжатия VRAM, см. ниже). Уровень 6: до 190 draw calls, 117–127 тыс.
   треугольников (цель CLAUDE.md: <100 / ≤100 тыс.). На слабом GPU это 25–40 FPS по оценке, не по измерению.
   **Сделано:** авто-определение слабого устройства и стартовый уровень качества (ниже).

### Средние
4. **Часы устройства.** Ежедневное задание и серия используют UTC-дату с часов телефона
   (`Daily.today_key()`); сервер принимает результат дня только по своему `request.time`. Телефон с
   неверной датой увидит чужой «день», результат отклонится, очередь молча сбросится
   (`online_daily.gd`: «отклонено правилами — удалить»). Награды: клиентские серии можно накрутить
   переводом часов вперёд, но кошелёк ограничен правилами (`earned <= 20000 + 700 * дней аккаунта`,
   время сервера). Рекомендация: брать дату из заголовка `Date` ответа Firestore для показа задания и
   предупреждать при расхождении > 5 минут. Не реализовано (чужая зона `Online`).
5. **Карта уровней (`level_select`)**: кнопки «Лавка» и «Серия» перекрывают кнопки справа вверху и
   «Sites» на всех разрешениях (110 находок в `test_device_matrix`, 800x480…2560x1600). Файлы
   `scenes/level_select.tscn`, `scripts/level_select.gd` ведёт другой агент: **не правились**. Проверить
   после его слияния: `tests/test_device_matrix.gd` печатает находки по карте отдельным списком, не как ошибку.
6. **Многооконный режим / складные / Chromebook.** Манифест: `resizeableActivity=true` (APK-шаблон),
   `screenOrientation=userLandscape`, `supportsPictureInPicture=true` (умолчание Godot; PiP игре не нужен).
   HUD пересчитывается при изменении окна (проверено тестом на 5 размерах подряд), но боевая симуляция
   в split-screen с маленькой высотой (<480 dp) не проверена руками.
7. **Системные вырезы и жесты Android 15–16 (edge-to-edge принудительно).** `SafeArea` берёт
   `DisplayServer.get_display_safe_area()`; что именно Godot 4.7 кладёт в эту область на Android
   (вырез + системные панели?) — **не проверено**. Добавлена диагностика: в оверлее (5 тапов по версии)
   строка `safe l,t,r,b` показывает значения с телефона.
8. **Кнопки настроек шире 64 px.** В `SettingsPanel` общие кнопки по-прежнему 64 px высотой
   (звук, эффекты, язык); новые «Качество графики» и опции управления — 84 px (48 dp).

### Низкие
9. Нет доступности (TalkBack, масштаб текста), нет вибро/хэптики, нет поддержки геймпада на HUD (карта
   действий для геймпада есть в Input Map).
10. `supportsPictureInPicture=true` и `FileProvider`/`ProcessPhoenix` из шаблона Godot — безвредны.

## 1. ABI и архитектуры

Пресеты: `armeabi-v7a=false, arm64-v8a=true, x86=false, x86_64=false` (APK и AAB).

- Шаблоны 4.7.2 содержат все четыре ABI (проверено по `android_release.apk` из
  `export_templates/4.7.2.stable`): `libgodot_android.so` сжато (deflate) arm64 24,0 МБ, armeabi-v7a
  25,5 МБ, x86 26,2 МБ, x86_64 25,4 МБ (в несжатом виде 71/75/84/74 МБ).
- Фактический AAB сейчас 50,6 МБ (только arm64; `build/bimbleguard.aab`, `build/bimbleguard-debug.apk` 56,5 МБ).
- Каждый добавленный ABI: **+~25 МБ в загружаемом AAB**. Скачивание пользователем не растёт: Play
  выдаёт только нужный ABI (split APK). Увеличивается время сборки/загрузки и матрица тестов.
- Godot требует 64-битный ABI рядом с 32-битным (`armeabi-v7a` только вместе с `arm64-v8a`, `x86` — с
  `x86_64`) — [документация Android Developers](https://developer.android.com/games/engines/godot/godot-export).
- 16 KB page size: `PT_LOAD` выравнивание `libgodot_android.so` и `libc++_shared.so` arm64 в шаблоне 4.7.2 =
  `0x4000` (16 КБ), **проверено** чтением ELF; armeabi-v7a — 4 КБ (для 32-бит не требуется).
  `compress_native_libraries=false` (AAB хранит `.so` без сжатия, для выравнивания).

Кого отсекает arm64-only:
- устройства только с armeabi-v7a (старые 32-битные телефоны, Android Go с 32-битным userspace на
  64-битном железе, часть планшетов, в т.ч. некоторые Fire; точной доли нет — **не проверено**: смотрите
  в Play Console, Device catalog, после загрузки AAB: «Supported / Excluded», экспорт в CSV);
- x86/x86_64-эмуляторы (на Mac Apple Silicon не нужны: образы arm64) и Chromebook на Intel (ARCVM запускает
  arm-приложения через трансляцию, **не проверено** для Bimbleguard).

Рекомендация: **для закрытого теста оставить только arm64-v8a.** 32-битные устройства — это 1–2 ГБ ОЗУ и
слабые GPU: игра на них и так не уложилась бы в бюджет. Добавлять `x86_64` (+~25 МБ AAB) только если
в тесте нужны Intel-Chromebook или x86_64-AVD; `armeabi-v7a` — только если после загрузки в Device catalog
доля отсечённых нужных вам устройств заметна (тогда и протестировать на 1 реальном 32-битном).
`GodotApp` объявляет `glEsVersion=0x00030000, required=true`: Play сам не показывает игру устройствам без
GLES 3.0 (таких почти нет).

## 2. minSdk / targetSdk, Android 16

- `minSdk=24` (Android 7.0), `targetSdk=36`, `compileSdk=36` — из `config.gradle` шаблона 4.7.2 и
  `aapt2 dump` APK (`uses-sdk 24/36`). Умолчание движка, в пресете `min_sdk=""`.
- Доля: по данным Google на 2025-12-01 ([heise](https://heise.de/-11162154)) Android 11–16 ≈ 83 % активных
  устройств; Android 9–10 и 7–8 вместе остальные ~17 %. minSdk 24 отсекает только Android 5–6 (долей по
  этим версиям не нашёл — **не проверено**; Google больше не публикует таблицу на developer.android.com).
- **Pre-launch report Play запускается на Android 9+**
  ([справка](https://support.google.com/googleplay/android-developer/answer/9842757)): устройства 7–8
  автотестами не покрываются; нужен хотя бы один реальный Android 8 (план ниже).
- **Android 16 (target 36)** ([behavior changes](https://developer.android.com/about/versions/16/behavior-changes-16)):
  - edge-to-edge нельзя отключить: контент идёт под системные панели; `screen/immersive_mode=true` +
    `SafeArea` готовы, значения insets на устройстве не проверены (риск 7);
  - predictive back включён: `KEYCODE_BACK` не доставляется на 16; у Godot кнопка «Назад» приходит как
    `NOTIFICATION_WM_GO_BACK_REQUEST` (используется на всех экранах, `quit_on_go_back=false`). Как Godot 4.7.2
    сопоставляет это с predictive back на Android 16 — **не проверено** (в манифесте шаблона нет
    `enableOnBackInvokedCallback`); проверить на Android 16 AVD: «Назад» в бою (пауза), на карте, на экране ника;
  - ограничения ориентации и изменения размера игнорируются на экранах sw >= 600 dp, **кроме игр**
    (`appCategory=game` и `isGame=true` выставлены в манифесте — проверено в APK). Планшеты с target 36 для нас
    остаются в ландшафте. Временный opt-out не нужен; в target 37 правила могут измениться (следить).
- Поворот/складывание: `configChanges` содержит `orientation|screenSize|smallestScreenSize|screenLayout|density`,
  активность не пересоздаётся; поворот ландшафт↔ландшафт и сгиб поддерживаются изменением размера окна
  (тест `_live_resize` — 1280x720 -> 800x480 -> 1024x768 -> 2560x1600 -> 2340x1080).

## 3. Графика

- **Рендерер:** `gl_compatibility` на всех платформах, GLES 3.0 обязателен. Своих шейдеров нет (проверено
  поиском: ни `.gdshader`, ни `shader_type`, ни `ShaderMaterial` в проекте). Материал один общий,
  `StandardMaterial3D` (`tg_palette.tres`: albedo + ORM-карта, `vertex_color_use_as_albedo`).
- **Сжатие текстур:** `textures/vram_compression/import_etc2_astc=true` включён (нужен экспортёру
  Android), но **все 137 PNG импортируются с `compress/mode=0` (Lossless)**, в метаданных `vram_texture:false`:
  ETC2/ASTC в игре не используются, зависимости от ASTC нет (устройства без ASTC не пострадают). Цена —
  VRAM без сжатия (~55 МБ). Максимальная текстура 1280 px (лимит GLES 3.0 минимум 2048).
- **MultiMesh врагов** (`enemy_crowd.gd`): `use_colors` (вспышка попадания) + `custom_aabb`, без
  `use_custom_data` и без `INSTANCE_CUSTOM`. Цвет инстанса — стандартный атрибут вершины; риска «лимит
  атрибутов» нет. Материал копируется на каждую часть меша (а не на врага). Деревья и молнии — MultiMesh без цветов.
  Рост буфера `instance_count` удвоением; при росте содержимое сбрасывается и переписывается за кадр (в коде учтено).
- **Тени:** один `DirectionalLight3D`, карта 2048 на телефоне (`size.mobile`); средний уровень качества — 1024.
- **SubViewport в Лавке** (`cosmetic_preview.gd`): `own_world_3d`, прозрачный фон, UPDATE_ALWAYS (кроме
  превью искр), свой DirectionalLight без теней, MSAA на телефоне выключен. Риск: прозрачный
  SubViewport + `own_world_3d` в Compatibility на некоторых GPU даёт чёрный фон — **не проверено**; в чек-листе.
- `Label3D` только в кооперативе (имена игроков), частицы — `CPUParticles3D`, `GPUParticles` нет
  (хорошо: [#94915](https://github.com/godotengine/godot/issues/94915) — GPUParticles в gl_compatibility на Mali-G71/G52 не видны).
- Известные проблемы Godot на Android (поиск 2026-10-17, ничего больше конкретного для 4.7.2 не найдено —
  **полнота не гарантирована**): MSAA-рост памяти (риск 1); падение в драйвере Mali
  [#119626](https://github.com/godotengine/godot/issues/119626) (4.5.1, SIGSEGV в libGLES_mali.so, на обоих
  рендерерах); 4.5.2 исправил падения на Adreno 5xx в Vulkan (мы на OpenGL). Все тесты — на устройствах.

## 4. Память и производительность по классам

Оценка по `docs/SOAK_REPORT.md` (M4, не телефон) и бюджетам. **Это модель, не измерение.**

| Класс | RAM / GPU | Ожидание | Что включает авто |
|---|---|---|---|
| Бюджет | 2–3 ГБ, Mali-G31/G52, Adreno 610–613, PowerVR | 25–45 FPS на уровнях 4–6 (оценка), риск OOM на 6 | «низкое»: тени выкл., MSAA выкл., эффекты «минимум» |
| Средний | 4–6 ГБ, Mali-G57/G68, Adreno 618–642 | 50–60 FPS | «среднее»: тени есть, карта 1024 |
| Флагман | 8+ ГБ, Adreno 7xx, Mali-G7xx/Immortalis, Xclipse | 60 FPS, троттлинг через 10–15 мин в жару | «высокое»: тени 2048 |

Частота кадров: `run/max_fps.mobile=60` — на 90/120 Гц экранах игра рисует 60 кадров (меньше нагрев);
визуально «60 на 120 Гц» нормально для игры без быстрого скролла. Если нужна плавность 120 — отдельное решение
(цена: нагрев, `docs/SOAK_REPORT.md` п. 2).

`QualityGuard` (пороги: средний кадр >30 мс за 2 с, пауза 5 с между ступенями, 6 с без оценки после
старта; ступени 1 тени, 2 MSAA, 3 эффекты «минимум», 4 эффекты выкл.; не поднимает обратно): для слабых
устройств пригоден как страховка, но реагирует через 8–13 с и тени по-прежнему первый удар — при 30 мс/кадр
(33 FPS) игрок уже страдает. Поэтому добавлен **стартовый уровень по железу** (ниже). Порог 30 мс
(≈33 FPS) оставлен: ниже порога игра играбельна.

### Что сделано: качество графики «авто/низкое/среднее/высокое»

- `GameSettings.graphics()` / `set_graphics()` (`user://settings.cfg`, секция `ui`, ключ `graphics`),
  `classify_device(ram_mb, adapter, mobile)` (чистая функция, покрыта тестом), `detected_tier()` берёт
  `OS.get_memory_info()["physical"]` и `RenderingServer.get_video_adapter_name()`; на десктопе всегда «высокое»,
  при неизвестной памяти не понижает.
- Правила: ОЗУ < 3300 МБ (телефон «3 ГБ» сообщает ~2,7–2,9 ГБ) или слабый GPU (регулярка
  `WEAK_GPU_PATTERN`: Mali-4xx/T/G31/G51/G52/G71, Adreno 3xx–5xx и 610–613, PowerVR) -> низкое; ОЗУ >= 5400 МБ
  -> высокое; иначе среднее. **Список GPU и пороги — эвристика, не измерение**; игрок всегда выбирает вручную.
  Будет полезно сверить имена адаптеров с реальными устройствами по строке диагностики.
- `QualityGuard.setup()` начинает бой со ступени 3 на низком уровне (тени и MSAA выкл., эффекты «минимум»),
  на среднем уменьшает карту теней, на высоком — как раньше. Меняет только визуал; симуляция и реплеи не затронуты.
  Смена выбора в настройках сбрасывает уже понижённое охранником (`QualityGuard.reset_session()`),
  действует со следующего боя.
- Настройки -> «Общие»: ряд из 4 кнопок высотой 84 px, RU/EN (`SET_GFX*`). Тесты: `test_quality_guard.gd`
  (классификация, сохранение, старт), `test_hud_layout.gd` (кнопки >= 84 px), `test_device_matrix.gd` (раскладка).
- Оверлей диагностики теперь показывает уровень, обнаруженный уровень и строку устройства (GPU, ОЗУ, окно, dpi,
  Гц, safe-area).

Размер: AAB 50,6 МБ (`.glb` ~31 МБ в `assets/models`). Установка = распаковка пакетов Play (`assetPackInstallTime`
asset pack внутри AAB — стандарт Godot 4.6+); отдельной распаковки при первом запуске нет, но на 2 ГБ телефонах
с мало свободного места (<500 МБ) установка может не пройти — стандартно.

## 5. Ввод и экран

`project.godot`: база 1280x720, `stretch/mode=canvas_items`, `aspect=expand`, ориентация 4 (сенсорная
альбомная). `expand` даёт каноничную высоту 720 и ширину от 960 (4:3) до 1707 (21:9 при 2560x1080)
и шире. Авто-проверка раскладки — `tests/test_device_matrix.gd` (в `run_all.sh`, ~6 с):

- 11 экранов: 800x480, 1280x720, 1600x720, 1920x1080, 2160x1080, 2340x1080, 2400x1080, 2560x1440,
  1024x768, 1280x800, 2560x1600; на трёх узких (1600x720, 2340x1080, 2400x1080) повтор с выемкой
  (слева/справа 48, снизу 24 canvas px);
- два языка (RU/EN); экраны: магазин, приветствие, ник, лобби кооператива, обучение, настройки (2
  вкладки), профиль, e-mail (4 режима), HUD (старт, меню строительства, выбранная башня, большой джойстик
  слева/справа, пауза, итог), карта (только отчёт);
- проверяется: интерактивные элементы (кнопки, поля, джойстик) целиком в видимой/безопасной области (внутри
  прокрутки — по горизонтали), нет перекрытий, текст не обрезан (метки с переносом/усечением, кнопки с `clip_text`),
  плюс «канарейка»: тест сам убеждается, что видит выход за экран, перекрытие и обрезку;
- результат: **0 находок по ~4200 элементам** (кроме карты, см. риск 5). Ограничение: `get_display_safe_area`
  в тесте подменяется (`ScreenUtil.fake_margins`); экранную клавиатуру и реальный dpi тест не воспроизводит.
- Размеры кнопок: HUD и карта >= 84 canvas px (48 dp на 1080p/420 dpi). Масштаб зависит от высоты окна:
  на 720p-экране 84 px = 84 физ. px = ~28 dp (mdpi-подобные 800x480 ещё меньше: `tools/measure_buttons.gd`).
  Если на 800x480 / 1280x720 телефонах (редко) нажимать трудно — это ограничение единого масштаба canvas.
- Мультитач: `VirtualJoystick` ведёт собственный `touch.index`, кнопки HUD — обычные `Button`; одновременное
  движение и атака поддерживаются кодом. `emulate_touch_from_mouse/mouse_from_touch` включены (Chromebook:
  мышь = палец). Стилус — как мышь. Проверить руками (чек-лист).
- Экранная клавиатура: `EmailAuthDialog`/ник поднимают окно над клавиатурой (`ScreenUtil.keyboard_height`,
  прокрутка к полю в фокусе, подсказка скрывается). `windowSoftInputMode=adjustResize`. На разных клавиатурах
  (Gboard, Samsung, SwiftKey) и в форме регистрации (3 поля) — проверить руками.
- Кнопка «Назад»: см. раздел 2.

## 6. Сеть и Firebase на устройствах

- Только HTTPS (поиск `http://` в `scripts/`: единственный — пример эмулятора RTDB в комментарии). Cleartext
  (Android 9+ блокирует) не нужен. Разрешения: `INTERNET` (и всё; `ACCESS_NETWORK_STATE` отключён).
- TLS: Godot по умолчанию пытается взять системное хранилище сертификатов ОС и держит в экспорте набор
  Mozilla как запасной ([документация](https://docs.godotengine.org/en/stable/tutorials/networking/ssl_certificates.html));
  настройка переопределения в проекте не задана. Корни Google (Firebase) есть и в системных, и в Mozilla-наборе,
  Let's Encrypt/ISRG не нужен. Поведение именно на Android 7–8 с устаревшим хранилищем — **не проверено**:
  проверить вход (анонимная авторизация) на реальном Android 8 при первой возможности.
- `HTTPRequest` `timeout=10 с` (`http_transport.gd`), очередь рекордов/ежедневных результатов повторяет при
  сетевой ошибке, игра офлайн полноценна. Режим экономии трафика/VPN: запросы малы (JSON), особых мер нет;
  за VPN с подменой TLS ошибка соединения -> «нет сети».
- Часы: см. риск 4. Серия (`Streak.check_in`) обрабатывает откат часов (`CLOCK_BACK`), не платит дважды за один
  день; перевод вперёд даёт серию, но не выше серверных лимитов кошелька.

## 7. Play Console, тесты

- Исключения устройств: Monitor and improve -> Reach and devices -> Device catalog
  ([справка](https://support.google.com/googleplay/android-developer/answer/7353455)): вкладки All / Supported /
  Excluded / Targeted, «Export device list» (CSV), «Manage exclusion rules» (по ОЗУ или SoC), исключение
  отдельной модели. Правила по ОЗУ действуют на новые устройства, **не действуют на внутренних тестеров**.
  Рекомендация для закрытого теста: ничего не исключать; после первых отчётов Android vitals исключить
  модели с аномальными ANR/краш. При желании: правило «ОЗУ < 2 ГБ» — вместо боя с OOM.
- **Pre-launch report** (автоматический, при загрузке AAB в тест-трек; Robo-краулер на реальных устройствах,
  телефоны, планшеты, Chromebook, Android 9+; кастомизация: логин-данные, Robo-скрипт, deep links, до 5 языков
  — [справка](https://support.google.com/googleplay/android-developer/answer/9842757)): Test and release ->
  Testing -> Pre-launch report -> Overview/Details (Stability, Performance, Accessibility, Screenshots).
  Для игры Robo ничего не пройдёт дальше меню — смотреть крэши запуска, ANR и скриншоты меню на разных экранах.
- **Android vitals**: [пороги «плохого поведения»](https://developer.android.com/google/play/vitals): user-perceived
  crash rate 1,09 %, ANR 0,47 % по приложению; по модели телефона 8 % (превышение снижает видимость на этой модели).
  Данные по версии/устройству/ОС в Monitor and improve -> Android vitals.
- **Firebase Test Lab** (Spark): [10 прогонов в день на виртуальных + 5 на физических](https://firebase.google.com/docs/test-lab/usage-quotas-pricing)
  (всего 15); Blaze: бесплатно 60 мин/день виртуальные и 30 мин/день физические. Подходит: Robo-прогон
  AAB/APK на 5 физических устройствах в день (загрузка `.apk` через консоль Firebase, без кода). Сначала нужен
  debug APK; нужен ли для этого отдельный Firebase-проект — не проверено. Живой Firebase-проект игры не трогали.
- План на 6–8 устройствах и 15-минутный чек-лист: `docs/DEVICE_TEST_CHECKLIST.md`.

### Матрица AVD для владельца (запуск — только с вашего разрешения)

На машине: `~/Library/Android/sdk/emulator`, AVD `lv_test` и `analytics_test` (оба: pixel_7, 1080x2400,
420 dpi, **3 ГБ ОЗУ**, arm64, системный образ `android-36 / google_apis_playstore / arm64-v8a`, `hw.gpu.mode=auto`).
Единственный установленный образ — Android 16 (API 36) arm64; на Apple Silicon образы x86_64 не запускаются
быстро. Профили устройств доступны в `avdmanager list device` (`pixel_fold`, `pixel_tablet`, `medium_tablet`,
`desktop_medium`, `pixel_5`, `Nexus 5`…). Предлагаемые AVD (создать, не запускать без разрешения):

| AVD | Профиль | Особенность | Что проверять |
|---|---|---|---|
| `lv_test` (есть) | pixel_7, 3 ГБ | Android 16 | кнопка «Назад» (predictive back), выемка, фон/возврат |
| `bg_small` | Nexus 5 / 1280x720 xhdpi, 2 ГБ | малый экран | размеры кнопок, память, низкое качество |
| `bg_wide` | свои 2400x1080 / 21:9 | широкий | safe area, HUD |
| `bg_fold` | pixel_fold (разложен/сложен) | складное | смена размера окна |
| `bg_tablet` | pixel_tablet / medium_tablet | 16:10, sw>=600 | отсутствие растягивания, landscape lock |
| `bg_desktop` | desktop_medium | Chromebook-режим | мышь, окно произвольного размера |

Образы Android 8 / 10 / 13 надо докачать (`sdkmanager "system-images;android-26;google_apis;arm64-v8a"` может не
существовать для arm64 — **не проверено**). Эмулятор GPU != Mali/Adreno: производительность и драйверные баги
по нему не проверяются.

## Источники (проверено 2026-10-17)

- Android 16 behavior changes: <https://developer.android.com/about/versions/16/behavior-changes-16>
- Godot Android export (архитектуры): <https://developer.android.com/games/engines/godot/godot-export>
- Godot TLS: <https://docs.godotengine.org/en/stable/tutorials/networking/ssl_certificates.html>
- Pre-launch report: <https://support.google.com/googleplay/android-developer/answer/9842757>
- Device catalog: <https://support.google.com/googleplay/android-developer/answer/7353455>
- Android vitals: <https://developer.android.com/google/play/vitals>
- Test Lab квоты: <https://firebase.google.com/docs/test-lab/usage-quotas-pricing>
- Версии Android (Google, 2025-12): <https://heise.de/-11162154>
- Godot issues: [#97967](https://github.com/godotengine/godot/issues/97967), [#124258](https://github.com/godotengine/godot/issues/124258),
  [#119626](https://github.com/godotengine/godot/issues/119626), [#94915](https://github.com/godotengine/godot/issues/94915)
- Локально проверено: `export_templates/4.7.2.stable/android_release.apk` (ABI, ELF), `android/build/config.gradle`
  (minSdk 24 / targetSdk 36 / NDK 29), `build/bimbleguard-debug.apk` (манифест через `aapt2`), `build/bimbleguard.aab`.

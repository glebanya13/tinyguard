# Tinyguard

Небольшая оригинальная 3D Tower Defense для Android в low-poly стиле.
Движок — **Godot 4.x**, язык — **GDScript**, рендерер — **Compatibility** (OpenGL ES 3).

> Статус: этап 2 — минимальный игровой цикл и строительство башен на площадках.
> Код проверен статически; **запуск в Godot ещё не проверялся.**

## Концепция

Игрок защищает маленькую крепость в центре компактной диорамы. По фиксированной
тропе идут волны врагов, игрок ставит башни на заранее отмеченные площадки,
тратит монеты и улучшает башни между волнами. Одна партия — 5–10 минут.

- Одна небольшая карта на экран, без прокрутки (масштаб — жестом, позже).
- Фиксированная изометрическая камера.
- Альбомная ориентация, управление касанием.
- Без сети, рекламы на старте и мультиплеера — всё работает офлайн.
- Яркий low-poly стиль: плоские цвета, без текстур, мягкий свет.

Подробности — в [`docs/GAME_DESIGN.md`](docs/GAME_DESIGN.md).

## Структура

```
tinyguard/
├── project.godot          # настройки проекта (Compatibility, landscape)
├── icon.svg               # временная иконка
├── scenes/
│   ├── main.tscn          # уровень: карта, башня, тропа, GameState, WaveManager, HUD
│   ├── enemy.tscn         # враг (PathFollow3D)
│   ├── tower.tscn         # башня (стрельба по ближайшему врагу)
│   ├── tower_slot.tscn    # площадка под башню (Area3D)
│   └── projectile.tscn    # снаряд
├── scripts/               # main, enemy, tower, tower_slot, tower_data, projectile,
│                          # wave_manager, wave_config, build_manager, game_state, hud
├── resources/
│   ├── waves_level_01.tres  # параметры волн
│   └── tower_archer.tres    # башня: название, цена, сцена
├── ui/hud.tscn            # показатели и кнопка «Начать волну»
├── assets/
│   ├── blender/           # исходники .blend
│   ├── models/            # экспорт .glb для Godot
│   └── materials/         # общие материалы .tres
├── tools/validate_project.py  # проверка структуры без Godot
└── docs/                  # дизайн, архитектура, арт-гайд, роадмап
```

## Запуск

### Требования

- Godot **4.3** или новее (стандартная сборка, не .NET).
- Для Android: Android Studio / SDK, JDK 17, export templates той же версии Godot.

### Десктоп (проверка в редакторе)

1. Установите Godot 4.3+ (macOS: `brew install --cask godot` или архив с godotengine.org).
2. Откройте Godot → **Import** → выберите `project.godot` в корне репозитория.
3. Дождитесь первого импорта (создастся папка `.godot/`, она в `.gitignore`).
   Без импорта игра не запустится: типы `class_name` (`Enemy`, `TowerData`…)
   регистрируются только при сканировании проекта редактором.
4. Нажмите **Run Project** (F5 / ⌘B). Ожидаемое поведение: изометрическая карта,
   через 3 с из красного спавна идут враги, башня стреляет жёлтыми снарядами,
   золото растёт за убийства, жизни падают, когда враг доходит до синей базы.
   Кнопка «Начать волну» запускает следующую волну досрочно. Клик по серой
   площадке подсвечивает её и открывает меню «Построить / Отмена» (50 золота).
   После победы или поражения кнопка «Играть заново» перезапускает уровень.

Из терминала:

```bash
godot --path . --editor            # открыть редактор
godot --headless --path . --import # импорт ресурсов и кэша class_name, затем выход
godot --path .                     # запустить игру (после импорта)
```

### Android

1. **Editor → Manage Export Templates** → скачать шаблоны.
2. **Editor Settings → Export → Android**: путь к Android SDK и Java SDK, debug keystore.
3. **Project → Export → Add… → Android**, ориентация уже задана в проекте (landscape).
4. Подключите устройство с включённой отладкой по USB → кнопка **Remote Deploy**.

Ключи подписи (`*.keystore`, `*.jks`) не коммитятся.

### Проверка без Godot

```bash
python3 tools/validate_project.py
```

Скрипт проверяет обязательные файлы и каталоги, настройки рендерера и ориентации,
ссылки `res://`, объявленные ресурсы и `load_steps`, `NodePath` в сценах, пути `$...`
в скриптах корней сцен, уникальность `class_name`, `script_class` у `.tres` и
отступы табами. Это **не** замена запуску в движке.

## Документация

- [`CLAUDE.md`](CLAUDE.md) — технические правила проекта
- [`docs/GAME_DESIGN.md`](docs/GAME_DESIGN.md) — механики
- [`docs/TECHNICAL_DESIGN.md`](docs/TECHNICAL_DESIGN.md) — архитектура
- [`docs/ART_GUIDE.md`](docs/ART_GUIDE.md) — визуальный стиль
- [`docs/ROADMAP.md`](docs/ROADMAP.md) — этапы разработки

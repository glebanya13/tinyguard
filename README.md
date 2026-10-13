# Tinyguard

Небольшая оригинальная 3D Tower Defense для Android в low-poly стиле.
Движок — **Godot 4.x**, язык — **GDScript**, рендерер — **Compatibility** (OpenGL ES 3).

> Статус: герой-строитель с командной картой, 3 уровня башен, автоматические волны,
> большой мир, звуки и частицы. Проверено в Godot 4.3 на Linux (headless и программный
> OpenGL); на Mac и Android — ещё нет.

## Управление

| Действие | Клавиатура / мышь | Геймпад | Телефон |
|---|---|---|---|
| Идти | WASD или стрелки, клик по земле | левый стик, крестовина | экранный джойстик, тап по земле |
| Выбрать площадку | клик по ней или подойти | подойти | тап или подойти |
| Построить «Лучника» (50) | B или кнопка карты | A | кнопка карты |
| Улучшить башню (60 / 90) | U | Y | кнопка карты |
| Снять выбор | Esc | B | кнопка ✕ |

Волны начинаются сами: первая через 30 с, следующие — через 30 с после окончания предыдущей.

![Tinyguard, уровень 1](docs/screenshots/level_01.png)

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
├── assets/
│   ├── blender/           # Python-скрипты, генерирующие все модели (см. README там)
│   ├── models/            # GLB + .glb.import (общий материал)
│   └── materials/         # палитра-атлас и общий материал tg_palette.tres
├── scenes/
│   ├── main.tscn          # уровень: карта, башня, тропа, GameState, WaveManager, HUD
│   ├── enemy.tscn         # враг (PathFollow3D)
│   ├── tower.tscn         # башня (стрельба по ближайшему врагу)
│   ├── tower_slot.tscn    # площадка под башню (Area3D)
│   ├── hero.tscn          # герой-рыцарь (визуал, анимация idle)
│   └── projectile.tscn    # стрела
├── scripts/               # логика: main, enemy, tower, tower_slot, tower_data, projectile,
│                          #   wave_manager, wave_config, build_manager, game_state, hud
│                          # герой и ввод: hero, camera_follow, virtual_joystick
│                          # визуал: tower_model, looping_model, no_shadow, hud_icon, one_shot_fx
├── resources/
│   ├── waves_level_01.tres  # параметры волн
│   └── tower_archer.tres    # башня: название, цена, сцена
├── ui/                    # hud.tscn, theme.tres
├── assets/audio/          # звуки (генерирует tools/gen_sounds.py)
├── tools/validate_project.py  # проверка структуры без Godot
├── tools/gen_sounds.py    # синтез звуков без зависимостей
└── docs/                  # дизайн, архитектура, арт-гайд, план ассетов, роадмап
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
4. Нажмите **Run Project** (F5 / ⌘B). Герой стоит у замка; через 30 с из портала
   пойдут слаймы. Подведите героя к площадке и нажмите B, чтобы построить башню,
   U — чтобы улучшить. После победы или поражения кнопка «Играть заново»
   перезапускает уровень.

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
- [`docs/ASSET_PLAN.md`](docs/ASSET_PLAN.md) — план и итог 3D-ассетов
- [`assets/blender/README.md`](assets/blender/README.md) — сборка моделей в Blender
- [`docs/ROADMAP.md`](docs/ROADMAP.md) — этапы разработки

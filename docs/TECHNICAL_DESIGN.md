# Technical Design — Tinyguard

Простая архитектура «сцена = сущность», данные — в ресурсах, связь — сигналами.

## Платформа и настройки

| Параметр | Значение |
|---|---|
| Движок | Godot 4.3+ (стандартная сборка) |
| Язык | GDScript со статической типизацией |
| Рендерер | Compatibility (`gl_compatibility`, OpenGL ES 3.0 / WebGL2-уровень) |
| Viewport | 1280×720, stretch `canvas_items`, aspect `expand` |
| Ориентация | landscape (`display/window/handheld/orientation=0`) |
| Сжатие текстур | ETC2/ASTC (требуется для Android) |

Почему Compatibility: максимальная совместимость с недорогими Android-устройствами,
низкое энергопотребление; для плоских low-poly материалов возможностей Forward+/Mobile
не нужно.

## Дерево главной сцены (текущее)

```
Main (Node3D, main.gd)               — связывает системы сигналами
├── WorldEnvironment, Sun, Camera     — окружение, свет, изометрия
├── Level (Node3D)                    — статическая карта из примитивов
│   ├── Ground, PathA/B/C, Spawn, Base, TowerSlot1..3
│   ├── PlaceholderTower (tower.gd)   — единственная башня
│   └── EnemyPath (Path3D)            — маршрут; враги спавнятся его детьми
├── GameState (Node, game_state.gd)   — золото, жизни, поражение
├── WaveManager (Node, wave_manager.gd) — волны по WaveConfig
└── HUD (ui/hud.tscn)                 — волна, золото, жизни, кнопка волны
```

Позже `Level` станет отдельной сценой `levels/level_01.tscn`, а площадки — `Area3D`
для тапа.

## Камера

- `Camera3D`, `projection = Orthogonal`, `size ≈ 10`.
- Истинная изометрия: камера смотрит на центр карты из направления `(1, 1, 1)`
  (наклон ≈ 35.26°, поворот 45°). Камера не вращается.
- Позже: ограниченный zoom жестом pinch (изменение `size` в диапазоне).

## Сущности

| Сцена | Корень | Скрипт | Назначение |
|---|---|---|---|
| `scenes/enemy.tscn` | `PathFollow3D` | `enemy.gd` (`Enemy`) | движение, HP, полоска здоровья |
| `scenes/projectile.tscn` | `Node3D` | `projectile.gd` (`Projectile`) | самонаводящийся снаряд |
| — (узел в `main.tscn`) | `Node3D` | `tower.gd` (`Tower`) | поиск цели, стрельба |
| `ui/hud.tscn` | `CanvasLayer` | `hud.gd` (`Hud`) | показатели и кнопка |

**Движение врагов:** `PathFollow3D` внутри `Path3D` (`loop = false`,
`rotation_mode = Y`), `progress += speed * delta`. При `progress_ratio ≥ 0.999`
враг испускает `reached_base(damage)` и удаляется. NavMesh не нужен.

**Смерть врага:** `take_damage()` уменьшает HP; при 0 — флаг `_is_dead`,
выход из группы `enemies`, `died(reward)`, `queue_free()`. Флаг защищает от
повторных сигналов, если в один кадр прилетело несколько снарядов.

**Выбор цели:** башня перебирает группу `enemies` и берёт **ближайшего** врага
в радиусе `range_m` (расстояние в плоскости XZ). При единицах–десятках врагов это
дешевле и проще, чем `Area3D` со слоями коллизий; пересмотреть, если врагов станет
сотни.

**Снаряд:** `top_level = true` (живёт в мировых координатах), летит к
`get_aim_point()` цели, наносит урон при сближении. Если цель умерла или
удалена — снаряд исчезает (`is_instance_valid`).

## Волны

`WaveConfig` (`scripts/wave_config.gd`, данные — `resources/waves_level_01.tres`):
число волн, задержки, интервал спавна, базовое число врагов + шаг за волну,
базовое HP × множитель за волну, скорость, награда, урон базе.

`WaveManager`:
- `start_next_wave() -> bool` — возвращает `false` и ничего не делает, если волна
  уже идёт или волны кончились (защита от двойного запуска кнопкой и таймером).
- Спавн через дочерний `Timer` с интервалом `spawn_interval`.
- Волна закончена, когда все враги заспавнены и каждый либо умер, либо дошёл до базы.
- Следующая волна стартует через `time_between_waves` (`auto_continue`) или по кнопке.
- `stop()` — окончательная остановка после поражения.

Сигналы: `wave_started(wave, total)`, `wave_cleared(wave)`, `all_waves_cleared`,
`enemy_killed(reward)`, `enemy_reached_base(damage)`.

## Состояние игры

`GameState` — **обычный узел** в `main.tscn`, а не autoload: пока уровень один,
глобальный синглтон не нужен (CLAUDE.md: autoload только при необходимости).
Поля `gold`, `lives`, `is_defeated`; сигналы `gold_changed`, `lives_changed`,
`defeated`. Стартовые значения — `@export` (100 золота, 20 жизней).

`main.gd` соединяет: `WaveManager → GameState` (награда, потеря жизней),
`GameState/WaveManager → HUD` (показатели), `HUD → WaveManager` (кнопка).
При поражении или победе — сообщение и `get_tree().paused = true`.

## Будущие данные (Resource)

При появлении нескольких типов башен и врагов — `TowerData` / `EnemyData`
(`cost`, `damage`, `fire_interval`, `range_m`, `hp`, `speed`, `reward`...),
а `WaveConfig` заменится списком групп «тип × количество × интервал».

## Ввод

- Тап → луч из камеры (`project_ray_origin/normal`) → `PhysicsRayQueryParameters3D`
  по слою «tower_slots/towers».
- Слои коллизий (когда появятся): 1 — площадки, 2 — башни. Враги коллизий не имеют.

## Сохранения

`user://save.cfg` через `ConfigFile`: открытые уровни, звёзды, громкость.

## Производительность

- Пул врагов и снарядов при необходимости (после профилирования).
- Общие материалы, без уникальных материалов на инстанс.
- Тени: только от `DirectionalLight3D`, ограниченная дистанция теней.
- Профилирование на реальном устройстве через Remote Debug.

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
│   ├── Ground, PathA/B/C, Spawn, Base
│   ├── TowerSlot1..3 (tower_slot.tscn) — площадки, Area3D на слое 1
│   │   └── PlaceholderTower (tower.tscn) — стартовая башня в TowerSlot2
│   └── EnemyPath (Path3D)            — маршрут; враги спавнятся его детьми
├── GameState (Node, game_state.gd)   — золото, жизни, поражение
├── WaveManager (Node, wave_manager.gd) — волны по WaveConfig
├── BuildManager (Node, build_manager.gd) — выбор площадки и постройка
└── HUD (ui/hud.tscn)                 — показатели, кнопка волны, меню строительства
```

Позже `Level` станет отдельной сценой `levels/level_01.tscn`.

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
| `scenes/tower.tscn` | `Node3D` | `tower.gd` (`Tower`) | поиск цели, стрельба |
| `scenes/tower_slot.tscn` | `Area3D` | `tower_slot.gd` (`TowerSlot`) | площадка, состояния |
| `ui/hud.tscn` | `CanvasLayer` | `hud.gd` (`Hud`) | показатели, кнопки, меню строительства |

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

## Строительство

**Площадка** (`TowerSlot`, корень `Area3D`, `collision_layer = 1`, цилиндрическая
форма): состояния `FREE` / `SELECTED` / `OCCUPIED`. Состояние показывается
`material_override` площадки (серый / жёлтый со слабым свечением / тёмный) и
кольцом `TorusMesh`, которое видно только при выборе. Построенная башня становится
дочерним узлом площадки; `Tower`, размещённый под площадкой в редакторе, делает её
занятой с самого старта.

**Данные башни:** `TowerData` (`scripts/tower_data.gd`,
`resources/tower_archer.tres`): `display_name`, `cost`, `scene`. Это единственное
место, где задана цена; HUD получает её параметром. Боевые параметры пока остаются
`@export` в `tower.gd`.

**Ввод:** `BuildManager._unhandled_input` реагирует только на нажатие левой кнопки
мыши. На Android касания превращаются в события мыши
(`input_devices/pointing/emulate_mouse_from_touch=true`, явно задано в
`project.godot`), поэтому мышь и тач идут одним путём, а кнопки HUD перехватывают
свои нажатия раньше `_unhandled_input`. `InputEventScreenTouch` отдельно не
обрабатывается, чтобы одно касание не обрабатывалось дважды. Верхняя панель HUD
имеет `mouse_filter = IGNORE`, чтобы не блокировать карту.

**Выбор:** луч `Camera3D.project_ray_origin/normal` → `intersect_ray` с
`collide_with_areas = true` по маске слоя 1. Свободная площадка → выбор и
`slot_selected`; занятая площадка или пустое место → `clear_selection()` и
`selection_cleared`.

**Покупка:** `build_selected()` проверяет, что площадка выбрана и свободна, затем
`GameState.spend_gold(cost)`; при нехватке золота ничего не меняется и возвращается
`false`. Кнопка «Построить» в HUD при нехватке золота неактивна, но это только
подсказка — решение принимает `BuildManager`. Новая башня автоматически ищет врагов
через группу `enemies`, отдельной регистрации не требуется.

Сигналы: `slot_selected(slot)`, `selection_cleared`, `tower_built(slot, tower)`;
HUD: `build_pressed`, `build_cancelled`. Связывает их `main.gd`.

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
Поля `gold`, `lives`, `is_defeated`; методы `add_gold`, `spend_gold -> bool`,
`lose_lives`; сигналы `gold_changed`, `lives_changed`, `defeated`. Стартовые значения — `@export` (100 золота, 20 жизней).

`main.gd` соединяет: `WaveManager → GameState` (награда, потеря жизней),
`GameState/WaveManager → HUD` (показатели), `HUD → WaveManager` (кнопка).
При поражении или победе — сообщение и `get_tree().paused = true`.

## Будущие данные (Resource)

`TowerData` уже есть (имя, цена, сцена). При появлении нескольких типов башен и
врагов в неё переедут `damage`, `fire_interval`, `range_m`, появится `EnemyData`,
а `WaveConfig` заменится списком групп «тип × количество × интервал».

## Ввод

- Тап/клик → луч из камеры → `PhysicsRayQueryParameters3D` (см. «Строительство»).
- Слои коллизий: 1 — площадки (используется), 2 — башни (зарезервирован).
  Враги коллизий не имеют.

## Сохранения

`user://save.cfg` через `ConfigFile`: открытые уровни, звёзды, громкость.

## Производительность

- Пул врагов и снарядов при необходимости (после профилирования).
- Общие материалы, без уникальных материалов на инстанс.
- Тени: только от `DirectionalLight3D`, ограниченная дистанция теней.
- Профилирование на реальном устройстве через Remote Debug.

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

## Дерево главной сцены (целевое)

```
Main (Node3D, main.gd)               — запуск уровня, переходы
├── WorldEnvironment                  — фон, ambient
├── Sun (DirectionalLight3D)          — единственный источник с тенями
├── Camera (Camera3D, ortho)          — фиксированная изометрия
├── Level (Node3D)                    — сцена уровня, инстанс levels/level_01.tscn
│   ├── Ground / декор
│   ├── EnemyPath (Path3D)            — маршрут врагов
│   ├── TowerSlots (Node3D)           — площадки (Area3D для тапа)
│   ├── Base                          — крепость
│   ├── Enemies (Node3D)              — контейнер врагов
│   └── Towers (Node3D)               — контейнер башен
├── WaveSpawner (Node)                — выпуск врагов по WaveData
└── HUD (CanvasLayer)                 — ui/hud.tscn
```

Сейчас в `scenes/main.tscn` есть только окружение, камера и статическая карта
из примитивов (`BoxMesh`, `CylinderMesh`) — без логики.

## Камера

- `Camera3D`, `projection = Orthogonal`, `size ≈ 10`.
- Истинная изометрия: камера смотрит на центр карты из направления `(1, 1, 1)`
  (наклон ≈ 35.26°, поворот 45°). Камера не вращается.
- Позже: ограниченный zoom жестом pinch (изменение `size` в диапазоне).

## Сущности

| Сцена | Корень | Скрипт | Данные |
|---|---|---|---|
| `scenes/enemy.tscn` | `PathFollow3D` | `enemy.gd` | `EnemyData` |
| `scenes/tower.tscn` | `Node3D` + `Area3D` (радиус) | `tower.gd` | `TowerData` |
| `scenes/projectile.tscn` | `Node3D` | `projectile.gd` | — |
| `scenes/tower_slot.tscn` | `Area3D` | `tower_slot.gd` | — |

**Движение врагов:** `PathFollow3D` внутри `Path3D`, `progress += speed * delta`.
Никакой навигации/NavMesh не требуется — тропа фиксирована.

**Выбор цели:** `Area3D` башни собирает врагов в радиусе; цель — с наибольшим
`progress` (ближе к базе). Без физики снарядов — снаряд летит к цели по прямой,
урон наносится при прибытии (или мгновенно для лучника).

## Данные (Resource)

```gdscript
class_name TowerData extends Resource
@export var display_name: String
@export var cost: int
@export var damage: float
@export var fire_interval: float
@export var range_m: float
@export var upgrades: Array[TowerData]   # следующий уровень
```

Аналогично `EnemyData` (hp, speed, reward, base_damage, scene) и
`WaveData` (массив групп: enemy, count, interval). Экземпляры — в `resources/`.

## Состояние игры

Один autoload `GameState` (появится на этапе 3): монеты, прочность базы, номер
волны, сигналы `coins_changed`, `base_hp_changed`, `wave_changed`, `game_over`.
HUD только подписывается на сигналы.

## Ввод

- Тап → луч из камеры (`project_ray_origin/normal`) → `PhysicsRayQueryParameters3D`
  по слою «tower_slots/towers».
- Слои коллизий: 1 — площадки, 2 — башни, 3 — враги (для радиусов `Area3D`).

## Сохранения

`user://save.cfg` через `ConfigFile`: открытые уровни, звёзды, громкость.

## Производительность

- Пул врагов и снарядов при необходимости (после профилирования).
- Общие материалы, без уникальных материалов на инстанс.
- Тени: только от `DirectionalLight3D`, ограниченная дистанция теней.
- Профилирование на реальном устройстве через Remote Debug.

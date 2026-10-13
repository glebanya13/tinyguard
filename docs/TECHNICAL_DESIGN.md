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

## Сцены и данные уровня

`run/main_scene` — `scenes/level_select.tscn` (`level_select.gd`): 3D-остров
`worldmap.glb`, кнопки уровней ставятся по проекции пустышек `Site1..3`.
Выбор пишется в статическую `LevelCatalog.selected_id`, затем грузится `main.tscn`.

`resources/levels.json` — единый источник для Godot (`LevelCatalog`) и Blender
(`build_terrain.py`): границы, старт (золото/дерево/жизни), план волн, тропа
(ломаная из осевых отрезков), замок, герой, площадки, рубимые деревья.
`tools/validate_project.py` проверяет расстояния между ними.

```
Main (Node3D, main.gd)               — строит уровень из данных и связывает системы
├── WorldEnvironment, Sun, Camera     — окружение, свет, изометрия (camera_follow.gd)
├── Level (Node3D)
│   ├── Hero (hero.tscn)              — ставится в level.hero
│   ├── EnemyPath (Path3D)            — Curve3D из level.path
│   └── (в _ready) level_N_terrain/decor/forest.glb, портал, замок,
│       TowerSlot × N (tower_slot.tscn), Grove (MultiMesh стоящих деревьев),
│       WoodTree × N на метках Chop_<вид>_<i> из level_N_decor.glb
├── GameState (Node)                  — золото, дерево, жизни
├── WaveManager (Node)                — спавн по WavePlan
├── BuildManager (Node)               — площадки, tower_types: archer/cannon/frost.tres
├── Sfx                               — рог, рёв босса, удар по замку, победа/поражение
└── HUD (ui/hud.tscn)                 — показатели, командная карта, атака, баннер босса
```

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
`false`. Меню стоит в левом нижнем углу: по расчёту проекции камеры это единственная
нижняя область без площадок, базы и тропы на 16:9 и 20:9 (в центре оно закрывало
площадку 3 и базу). Кнопка «Построить» при нехватке золота неактивна, но это только
подсказка — решение принимает `BuildManager`. Новая башня автоматически ищет врагов
через группу `enemies`, отдельной регистрации не требуется.

Сигналы: `slot_selected(slot)`, `selection_cleared`, `tower_built(slot, tower)`;
HUD: `build_pressed`, `build_cancelled`. Связывает их `main.gd`.

## Волны

`WavePlan` (`scripts/wave_plan.gd`) строится из блока `waves` уровня: число волн,
задержки, `count_base + count_step·(n−1)` врагов, HP × `hp_mult·hp_growth^(n−1)`,
с какой волны идут быстрые (`fast_from`, каждый 3-й) и толстые (`tank_from`,
каждый 4-й), интервал спавна ×0.97 за волну до `interval_min`. Каждая
`boss_every`-я и последняя волна заканчивается боссом (на 20+ — двумя), его HP
растёт медленнее (показатель 0.75). Типы врагов — `EnemyData` в `resources/enemies/`.

`WaveManager`: очередь спавна `[{data, hp}]`, `start_next_wave() -> bool`
(защита от двойного запуска), `schedule_next_wave`, `stop()`.
Сигналы: `wave_started(wave, total, boss)`, `wave_cleared`, `all_waves_cleared`,
`enemy_killed(reward)`, `enemy_reached_base(damage)`.

## Состояние игры

`GameState` — **обычный узел** в `main.tscn`, а не autoload: пока уровень один,
глобальный синглтон не нужен (CLAUDE.md: autoload только при необходимости).
Поля `gold`, `wood`, `lives`, `is_defeated`; методы `configure(start)`, `add_gold`,
`add_wood`, `can_afford(Vector2i)`, `spend(Vector2i) -> bool`, `lose_lives`; сигналы
`gold_changed`, `wood_changed`, `lives_changed`, `defeated`. Старт — из `level.start`.

Герой (`hero.gd`): `try_attack()` с кулдауном 0.5 с, удар через 0.2 с по врагам
(группа `enemies`) и деревьям (группа `wood_trees`, `WoodTree.chop() -> int`) в
конусе перед собой; сигнал `wood_gathered(amount, at)`. Деревья — слой коллизий 3,
маска героя 1 + 3.

Все деревья внутри поля рубятся. `build_terrain.py` не запекает их в декор, а
кладёт пустышки `Chop_<pine|round>_<i>`; `main.gd` ставит на них `WoodTree`.
Стоящие деревья рисует `Grove`: по одному `MultiMeshInstance3D` на модель
(около 50 деревьев = 2 draw call вместо 50). Дерево, которое качается, падает,
растёт или подсвечено как цель, прячет свой экземпляр и показывает собственную
модель. Замер на уровне 1: 90–120 draw calls в кадре (было 150–180).

Приказы героя идут по `WalkGrid` (`AStarGrid2D`, клетка 0.5 м): сетка строится
один раз после первого физического кадра запросами `intersect_shape` (цилиндр
r = 0.34) к слоям 1 и 3; новая башня блокирует свои клетки. Путь упрощается
проверкой прямой видимости по клеткам.

Тап (`BuildManager`) срабатывает на отпускание, если палец сдвинулся меньше
24 px и не было второго пальца (`CameraFollow.is_pinch_gesture()`); щипок и
колесо мыши меняют `size` орто-камеры в пределах 7–16.

`main.gd` соединяет: `WaveManager → GameState` (награда, потеря жизней),
`GameState/WaveManager → HUD` (показатели), `HUD → WaveManager` (кнопка).
При поражении или победе — сообщение и `get_tree().paused = true`.

## Конец игры и перезапуск

- Победа (`all_waves_cleared`, если не было поражения) или поражение (`defeated`) →
  `main._end_game()`: снимает выбор площадки (меню закрывается), показывает
  `Hud.show_end_screen()` и ставит `get_tree().paused = true`.
- Экран конца — `MessageLabel` и `RestartButton` («Играть заново») по центру,
  оба скрыты до конца игры. У кнопки `process_mode = ALWAYS`, поэтому она
  нажимается на паузе — мышью и касанием (через `emulate_mouse_from_touch`).
  После первого нажатия кнопка блокируется до перезагрузки.
- `restart_pressed` → `main._on_restart_pressed()`: **сначала**
  `get_tree().paused = false`, затем `get_tree().reload_current_scene()`.
  Если перезагрузка вернула ошибку — `push_error` и пауза возвращается.

Почему перезагрузки сцены достаточно: всё состояние уровня хранится в узлах
`main.tscn` — золото и жизни (`GameState`), номер волны и таймеры (`WaveManager`),
враги (дети `EnemyPath`), снаряды (дети башен), построенные башни (дети площадок),
выбор (`BuildManager`). Autoload'ов и `static var` нет, `Engine.time_scale` не
меняется. Все соединения сигналов создаются в `_ready()` узлов сцены (и на новых
врагах в `WaveManager`), поэтому при перезагрузке они удаляются вместе со старыми
узлами и подключаются заново ровно один раз; `WaveManager` в сцене один.
Единственное, что переживает перезагрузку, — `SceneTree.paused`, его снимаем вручную.

При появлении autoload'а (например, для настроек или прогресса) его состояние
уровня придётся сбрасывать явно — перезагрузка сцены его не затронет.

## Будущие данные (Resource)

`TowerData` уже есть (имя, цена, сцена). При появлении нескольких типов башен и
врагов в неё переедут `damage`, `fire_interval`, `range_m`, появится `EnemyData`,
а `WaveConfig` заменится списком групп «тип × количество × интервал».

## Ввод

- Тап/клик → луч из камеры → `PhysicsRayQueryParameters3D` (см. «Строительство»).
- Слои коллизий: 1 — площадки (используется), 2 — башни (зарезервирован).
  Враги коллизий не имеют.

## Визуал и игровая логика

Логика не зависит от мешей: модели — дочерние узлы `Model` (инстансы `.glb`), у них
нет коллизий, они не участвуют в выборе цели и в лучах выбора площадок.

| Скрипт | Где | Что делает |
|---|---|---|
| `looping_model.gd` | `Model` героя и слайма | зацикливает анимацию `idle`, случайная фаза |
| `tower_model.gd` | `Model` башни | по сигналу `Tower.fired(target)` поворачивает `Turret` к цели и играет `attack` |
| `no_shadow.gd` | террейн, кольца площадок | отключает отбрасывание теней у мешей ниже (экономия draw calls) |
| `hud_icon.gd` | HUD | рисует иконки флага, монеты, сердца |

- `tower.gd` только испускает `fired` и выпускает снаряд у кончика арбалета
  (`muzzle_reach`); урон, радиус и темп не менялись.
- `projectile.gd` разворачивает стрелу по направлению полёта (`look_at`).
- Слайм в `enemy.tscn` повёрнут на 180°: модель смотрит в +Z, а `PathFollow3D` ведёт по −Z.
- Все модели используют один материал `assets/materials/tg_palette.tres`
  (альбедо-палитра × цвет вершин с AO; roughness/metallic из ORM).
- Тени: один ортогональный каскад, `shadow_blur = 1.5`; мелкие пропсы теней не отбрасывают.
- Замер (Godot 4.3, Compatibility, 1280×720, программный OpenGL): ~56 draw calls 3D
  (вместе с тенями) и ~45 2D-вызовов HUD, 100–125 всего; ~160 тыс. треугольников в кадре
  (с тенью). Дальний лес (`level_01_forest.glb`) теней не отбрасывает; декор и лес разбиты на
  чанки 10 × 10 м для отсечения. FPS на телефоне не измерялся.

## Интерфейс

`ui/hud.tscn` с темой `ui/theme.tres`: `Root` (Control, `mouse_filter = IGNORE`) →
`TopBar` (таблетки волны, золота, жизней), `StartWaveButton`, `BuildMenu`,
`EndScreen` (затемнение + панель с `MessageLabel` и `RestartButton`). Контейнеры и
иконки не перехватывают клики, чтобы касание проходило к карте.
`Hud.show_end_screen(text, victory)` красит заголовок золотым или коралловым и прячет
кнопку волны.

## Герой, камера, ввод

- `scenes/hero.tscn`: `Hero` (`CharacterBody3D`, слой 2, маска 1, `motion_mode = FLOATING`) + капсула
  + модель. `hero.gd`: движение по действиям `move_up/down/left/right` **относительно камеры**
  («вверх» — вверх по экрану) плюс `joystick_vector`; приказы `move_to(point, reach, callback)`,
  отмена при ручном вводе или если 1.5 с нет продвижения; анимации `idle` / `walk`.
- Действия ввода — в `project.godot` (`[input]`): WASD, стрелки, левый стик и крестовина;
  `build_tower` (B / A), `upgrade_tower` (U / Y), `cancel_command` (Esc / B геймпада).
- Препятствия: модели с узлами `*-colonly` из Blender импортируются как `StaticBody3D`
  (слой 1): башня, замок, портал, стволы деревьев, стены зоны 26 × 18 м. Площадки — `Area3D`,
  герою не мешают; луч выбора площадок их тел не видит (`collide_with_bodies = false`).
- `camera_follow.gd`: камера сохраняет изометрический угол и плавно следует за героем;
  точка взгляда ограничена `bounds`.
- `virtual_joystick.gd`: виден только на мобильных (`OS.has_feature("mobile")`), работает с
  `InputEventScreenTouch/Drag` по индексу пальца (мультитач), мышиные события от того же
  касания поглощает.
- Тап по земле: `BuildManager.ground_tapped(point)` → герой идёт туда.

## Командная карта и приказы

`main.gd` превращает кнопки карты в приказы: выбранная площадка (тапом или подходом героя
ближе 1.1 м) + команда BUILD / UPGRADE → если герой ближе 1.25 м — сразу, иначе
`hero.move_to(..., callback)`. `BuildManager.build_on(slot)` / `upgrade(slot)` проверяют
золото в момент выполнения. Уровни башни — массивы в `TowerData`
(`upgrade_costs`, `damage_levels`, `range_levels`, `interval_levels`); `Tower.apply_level()`
берёт статы, `level_changed` включает украшения `Lv2` / `Lv3` модели.

## Отклик: звук и частицы

- Звуки синтезируются `tools/gen_sounds.py` в `assets/audio/*.wav` (детерминированно).
- `one_shot_fx.gd`: сцена эффекта запускает свои `CPUParticles3D` и `AudioStreamPlayer`
  **в конце кадра** (позицию ставят после `add_child`) и удаляет себя по `lifetime`.
- `scenes/fx/`: `hit_fx` (снаряд при попадании), `death_fx` (враг при смерти, + монеты),
  `build_fx`, `upgrade_fx` (main.gd по сигналам `BuildManager`). Выстрел — `ShotSound`
  в `tower.tscn`; рог волны, удар по замку, победа/поражение — узел `Sfx` в `main.tscn`.

## Ссылки на узлы в сценах

Экспортируемое свойство типа узла (`@export var enemy_path: Path3D`) в `.tscn`
записывается как `NodePath(...)` **и** должно быть перечислено в заголовке узла:
`[node ... node_paths=PackedStringArray("enemy_path")]`. Без этого Godot 4 оставляет
свойство `null` (так было с `WaveManager` и `BuildManager` до проверки в движке).
Редактор пишет это сам; при ручной правке `validate_project.py` это проверяет.

## Известные ограничения

- `emulate_touch_from_mouse=true` порождает лишние `InputEventScreenTouch` на
  десктопе; код их игнорирует. Настройку можно убрать, если не понадобится тач-отладка.
- Луч выбора площадки делается из `_unhandled_input`, а не из `_physics_process`.
  При физике в основном потоке (по умолчанию) это допустимо; при
  `physics/3d/run_on_separate_thread` выбор нужно перенести в физический кадр.
- `WaveManager` считает живых врагов по сигналам `died` / `reached_base`. Враг,
  удалённый иначе (например, `queue_free()` извне), навсегда «зависит» волну.
- На 4:3 при `keep_height` обрезаются пустые углы земли (≈0.4 м); геймплейные
  объекты остаются в кадре.

## Сохранения

`user://save.cfg` через `ConfigFile`: открытые уровни, звёзды, громкость.

## Производительность

- Пул врагов и снарядов при необходимости (после профилирования).
- Общие материалы, без уникальных материалов на инстанс.
- Тени: только от `DirectionalLight3D`, ограниченная дистанция теней.
- Профилирование на реальном устройстве через Remote Debug.

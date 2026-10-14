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
│       WoodTree × N на метках Chop_<вид>_<i> из level_N_decor.glb,
│       Villagers (villagers.gd) → Villager × 2 (villager.tscn), после сетки ходьбы
├── GameState (Node)                  — золото, дерево, жизни
├── WaveManager (Node)                — спавн по WavePlan
├── BuildManager (Node)               — площадки, tower_types: archer/cannon/frost.tres
├── Sfx                               — рог, рёв босса, удар по замку, победа/поражение
└── HUD (ui/hud.tscn)                 — показатели, командная карта, атака, баннер босса
```

## Пауза, скорость, звёзды, кузница

- Пауза — `SceneTree.paused`; меню паузы и экран конца — один узел `HUD/EndScreen`
  (кнопки с `process_mode = ALWAYS`). Пауза включается кнопкой, действием `pause`,
  `NOTIFICATION_WM_GO_BACK_REQUEST` (`application/config/quit_on_go_back=false`) и
  на мобильных при `NOTIFICATION_APPLICATION_PAUSED/FOCUS_OUT`. На карте «Назад» — выход.
- ×2 — `Engine.time_scale`, сбрасывается в конце уровня и при выходе со сцены.
- Звёзды и звук — `LevelCatalog` (`user://progress.cfg`: `stars_<id>`, `settings/sound`);
  тесты подменяют `LevelCatalog.save_path`.
- Кузница — карта команд `main.gd` (`_forge_card`), цены меча — `@export` героя,
  ремонт — `@export` `GameState` (`repair_lives`, `repair_wood`).
- Продажа — `BuildManager.sell()` → `TowerData.sell_value()` (70 %), `WalkGrid.unblock()`.
- «Вихрь» — `Hero.try_spin()`, эффект `scenes/fx/spin_fx.tscn`.

## Прогресс, улучшения, осада

- `Perks` (`scripts/perks.gd`, статический) — звёзды и улучшения: `earned_stars`,
  `free_stars`, `buy`, `reset`, `value(id)`. Улучшения — `PerkData` в
  `resources/perks/`; загружаются лениво (`Perks.all()`): `preload` в константе
  ломал ресурсы, пока компилируются скрипты с типом `PerkData`.
- `main.gd` применяет улучшения при старте: `GameState.configure` (золото, дерево,
  жизни), `Hero.damage_multiplier` / `wood_bonus`, `BuildManager.damage_multiplier`
  (умножается после каждого `apply_level`).
- Осада: `LevelCatalog.endless` → `WavePlan(waves, true)` (`ENDLESS_WAVES`, без
  финального босса); рекорд — `LevelCatalog.save_endless()`.

## Иконки, иконка приложения, заставка

- `assets/blender/build_icons.py` → `icon_*.glb` (палитра, без текстур).
- `tools/render_icons.gd` → `ui/icons/*.png` 256 px: ортокамера по силуэту, небо для
  бликов металла, обводка и тень (дилатация альфы через `blit_rect_mask`).
  Импорт с мипмапами, `default_texture_filter` = Linear Mipmap.
- `tools/render_app_icon.gd` → `icon.png` (192), `ui/app/icon_foreground.png` и
  `icon_background.png` (адаптивная 432), `ui/app/splash.png` (заставка
  `application/boot_splash`). Пути прописаны в `export_presets.cfg`.

## Биомы, новые враги и башни

- `levels.json` → `"biome"`: `meadow` / `winter` / `autumn` / `desert`. Blender
  перекрашивает террейн, декор и лес по `tg.BIOMES` (замена цветов палитры), рубимые
  деревья — `tree_<round|pine>_<biome>.glb`; `WoodTree.model_scene()` грузит модель по
  имени варианта.
- `EnemyData.flying` / `fly_height` (летун; снаряды пушки и её прицел его не видят),
  `arrow_damage_mult` (щитовик). Урон передаётся с типом: `take_damage(amount, kind)`.
- `TowerData.chain_levels` / `chain_range` (молния: без снаряда, мгновенный урон по
  цепи, эффект `scenes/fx/lightning_fx.tscn`), `damage_kind`, `hits_air`.
- Коллайдеры моделей — выпуклые (`-convcolonly`, `tg.COLLIDER_SUFFIX`), по одному на
  ствол: полые trimesh-коллайдеры позволяли рыцарю «провалиться» внутрь куста.

## Онлайн (Firebase)

`scripts/online.gd` — autoload `Online` (единственный): REST Firebase без плагинов.
Анонимный вход (Identity Toolkit, обновление токена), рекорды осады
(`leaderboards/level_<id>/scores/<uid>`, запрос `runQuery` топ-10), облачная копия
прогресса (`saves/<uid>`, текст `ConfigFile`). Конфиг — `res://firebase.cfg`
(не коммитится, есть `firebase.example.cfg`), правила — `firestore.rules`.
Без конфига `Online.is_configured()` = false, кнопка «Рекорды» скрыта.

## Сохранение

`LevelCatalog.data()` — кэш `ConfigFile`; `commit()` пишет атомарно (`.tmp` →
переименование, прошлая версия — `.bak`). Повреждённый файл: берётся `.bak`, а если
и он не читается — игра работает на значениях по умолчанию и **не** перезаписывает
файл.

## Тесты и баланс

`tests/run_all.sh <godot>` — headless-тесты: `test_gameplay.gd` (рубка, постройка,
улучшение, продажа, кузница, вихрь, боссы; на каждом уровне), `test_walk.gd` (рыцарь
доходит до всех площадок), `test_pause.gd` (пауза, «Назад», ×2, звёзды, звук),
`test_meta.gd` (звёзды, улучшения, осада, повреждённое сохранение), `test_combat.gd`
(летуны, щиты, молния), `test_villagers.gd` (жители: появление, курс, падение цены,
нельзя продать больше, чем есть; карта торговли; на каждом уровне), `test_online.gd` (Firebase без сети: разбор ответов,
восстановление прогресса). Геймплей и проходимость — на всех 6 уровнях.
`tools/balance_sim.py` — дискретная симуляция волн с жадным игроком и героем у замка.

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
модель. Замер на уровне 1: 85–120 draw calls в кадре (было 150–180).
Декор, земля и дальний лес не отбрасывают теней: кадр уровня 1 ≈ 99 тыс.
треугольников (было 127 тыс.), уровня 3 ≈ 109 тыс. Полоска HP видна только у
раненых врагов и боссов; HUD обновляет текст только при изменениях.

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
| `tower_model.gd` | `Model` башни | по сигналу `Tower.fired(target)` поворачивает `Turret` к цели и играет `attack`; тень — только у `Base` и `Turret` |
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
- Тени (v0.5): у башни тень отбрасывают только `Base` и `Turret` (`tower_model.gd` гасит
  `Lv2`, `Lv3` и деталь на турели), не отбрасывают плита площадки, снаряды (в сценах
  снарядов, а не в `_ready` каждого выстрела) и все `CPUParticles3D` эффектов. Молния
  рисуется одним `MultiMeshInstance3D` на разряд вместо `MeshInstance3D` на отрезок.
  Уровень 6, все 14 площадок застроены и улучшены до 3-го уровня (`RENDERING_INFO_TOTAL_
  DRAW_CALLS_IN_FRAME`, 1280×720): 153 → 118 draw calls (без HUD 119 → 92); пустой
  уровень 90 → 72; в бою (волны идут) в среднем 154 → 119, пик 165 → 124.

## Интерфейс

`ui/hud.tscn` с темой `ui/theme.tres`: `Root` (Control, `mouse_filter = IGNORE`) →
`TopBar` (компактные «фишки» `HudChip`: флаг «3/15», золото, дерево, жизни),
`TopRight` (только ×2 и пауза), `Hint` (подсказка первых шагов — сама гаснет через
`hint_seconds` и возвращается только при смене текста), `Banner` (один раз на событие:
«Первая волна через 30 секунд» в начале, «Волна N!» + «Следующая через 30 секунд» при старте
волны, «Последняя волна!»; волна с боссом — тот же баннер с иконкой короля и коралловым
заголовком), `CommandCard`, `AttackButton`/`SpinButton`, `Joystick`, `EndScreen`.
Вызова волны раньше времени нет: волны идут строго по таймеру `WavePlan.wave_duration`;
при старте волны звучит `wave_boom.wav`.

- Кузница открывается из меню паузы (кнопка «Кузница» снимает паузу и открывает карту)
  или клавишей K (`Hud._unhandled_key_input`), поэтому справа сверху не больше двух кнопок.
- Командная карта компактная: заголовок и статы в одной строке («Лучник · ур. 2/3  Урон
  24 · радиус 5.2 · 0.42 с»), кнопки 84 × 84 (≈ 48 dp на телефоне 1080p, холст 720 px),
  строка подсказки — только «Не хватает…» / «Рыцарь идёт…». Роли башен, «Дальше: …» и
  цена ремонта — во всплывающих подсказках кнопок (только на ПК; на тач-сборке `_touch`
  их нет). Доход от продажи — зелёными цифрами. Карта растёт влево-вверх от кнопки атаки
  и не заходит в центр поля и на джойстик (проверено при 1280×720 и 1600×720).
- Снимки: `docs/screenshots/hud_desktop.png`, `hud_phone.png`, `hud_phone_build.png`.

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

## Жители и торговля деревом

`Villagers` (узел в `Level`, создаётся `main.gd`) после постройки `WalkGrid` выбирает дома
жителей на решётке 1 м в 3–9 м от замка: клетка свободна на сетке ходьбы (с запасом на
ширину жителя), ≥ 1.5 м от осевой тропы, ≥ 1.4 м от площадок, ≥ 2.5 м от старта героя,
вокруг достаточно свободного места; лучшие по простору и близости к замку, через 2.5 м.
`Villager` гуляет по прямой к случайной точке в 1.8 м от дома, если весь отрезок прошёл
`Villagers.is_open()` (башни блокируют сетку, так что и их обходит); без тел и коллизий,
без теней (`no_shadow.gd`), 6 мешей = 6 draw calls на жителя. Анимации `idle`, `walk`,
`wave` (приветствие и продажа). Торговлей правит `Villagers.sell(lots)`: не больше целых
партий, чем есть дерева; цена партии — `VillagerTrade.lot_gold(lots_sold)` =
max(min_gold, round(start_gold · price_decay^n)). `main.gd` открывает карту торговли, когда
герой ближе `trade_reach` к жителю или после тапа по нему (герой идёт к жителю), закрывает,
когда герой отошёл; ✕ закрывает до тех пор, пока герой не отойдёт.

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

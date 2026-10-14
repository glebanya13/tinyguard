# Код-ревью Bimbleguard

Дата: 2026-10-14. Ветка ревью: `worktree-agent-a6252479bf4de43a9` (от `claude/ecstatic-noether-wkau2j`).
Охват: `scripts/`, `ui/`, `scenes/`, `tests/`, `tools/`, правила `firestore.rules` (по связности с клиентом).
Файлы, которые сейчас рефакторят другие (`enemy`, `tower`, `wave_manager`, `projectile`, `hero`, `online`, rtdb), не правились: по ним только пункты ниже.

## Результаты проверок (реальный вывод)

| Проверка | Результат |
|---|---|
| `python3 tools/validate_project.py` | `OK: structure, project settings, scenes and scripts look consistent.` Предупреждение: `PRIVACY_URL is empty/TODO` (нужно до релиза в стор). |
| `godot --headless --path . --import` | Без ошибок (в конце безвредное `cannot connect to daemon at tcp:5037` от adb). |
| `tests/run_all.sh /Applications/Godot.app/Contents/MacOS/Godot` | До правок: `== summary: 25 run, 0 not passed`. После правок: `== summary: 26 run, 0 not passed` (добавлен `test_endgame.gd`). |
| `gdlint scripts/*.gd tests/*.gd` | `Success: no problems found`. |
| `gdlint tools/*.gd` | До правок: `tools/measure_draw_calls.gd:113: Error: Max allowed line length (100) exceeded`. Исправлено. |
| `gdformat --line-length 100 --check scripts/*.gd tests/*.gd` | `58 files would be left unchanged`. В `tools/` два файла требовали форматирования — исправлено. |

Что видно в полном выводе тестов, но `run_all.sh` не ловит (см. M-T1): в конце каждого сценарного теста `WARNING: N ObjectDB instances were leaked at exit` (2–23 шт.) и `ERROR: N resources still in use at exit`; в `test_meta`/`test_online`/`test_accounts` намеренные `ERROR: ConfigFile parse error ...` / `Save ... is damaged` (негативные тесты, шум).

## Что исправлено (отдельные коммиты)

1. `590ed10` — **B1** последний утёкший враг давал 3 звезды / победу+поражение (см. ниже). Тест `tests/test_endgame.gd`, подключён в `run_all.sh`.
2. `b536e9c` — **m-P1** значения звёзд из облака зажимаются в 0..3 (`player_profile.gd`), проверка в `test_accounts.gd`.
3. `530d109` — gdformat/gdlint для `tools/`.

---

## BLOCKER

### B1. Утёкший последним враг: 3 звезды вместо 2 и/или «победа», затем «поражение» — ИСПРАВЛЕНО
- Где: `scripts/wave_manager.gd:149-152` (порядок подключений `reached_base`: сначала `_on_enemy_gone`, потом `enemy_reached_base.emit`) и `scripts/main.gd` (`_on_all_waves_cleared`, `_on_defeated`).
- Суть: `_on_enemy_gone` эмитит `all_waves_cleared` раньше, чем `main` успел снять жизни за этого же врага. Звёзды считались по устаревшим жизням; если утечка смертельная, засчитывалась победа (`LevelCatalog.complete`, открытие уровня, звёзды-перки), а затем `defeated` показывал второй экран.
- Воспроизведение (было): уровень 1, `current_wave = wave_count`, один слизень на конец пути. Результат: `lives 20 -> 19`, `stars saved: 3`, `_ended = true`. Скрипт и тест: `tests/test_endgame.gd`.
- Исправление (в `main.gd`, без правки `wave_manager`): сигнал подключён с `CONNECT_DEFERRED`; оба обработчика конца уровня игнорируют повторный вызов (`_ended`).
- Остаток: хорошо бы поменять порядок подключений в `wave_manager.gd` (эмитить «враг дошёл» до «волна зачищена») — пункт для владельца файла.

---

## MAJOR

### M1. `get_nodes_in_group()` в горячих путях (мобильная производительность)
Каждый вызов создаёт новый `Array`, а затем перебирает все узлы группы.
- `scripts/hero.gd:201` `get_focus_target()` вызывается **каждый кадр** из `main._process` (нестрого) и ещё раз из `hero._physics_process` при `auto_action`; перебирает все `Enemy` и **все деревья леса** (`WoodTree.GROUP`).
- `scripts/tower.gd:70` `find_nearest_enemy()` из `_process` каждой башни (раз в `retarget_interval`/`fire_interval`), `_nearest_unhit` — на каждый прыжок молнии.
- `scripts/projectile.gd` — взрыв пушки; `scripts/enemy.gd:182` `_heal_neighbours` O(N) на лекаря.
- `scripts/main.gd:430` `_auto_select_near_hero` (каждый кадр, пока герой идёт), `main.gd:712` `_guide_step` (ещё и дважды за обновление стрелки и в каждом `_refresh_card`), `tutorial.gd` `_nearest`.
- Как проверить: `tools/measure_draw_calls.gd` + профайлер на волне 20+ с 15 башнями на среднем Android.
- Предложение: единый реестр целей в `WaveManager`/`EnemyCrowd` (массив живых врагов без аллокаций; можно уже использовать `EnemyCrowd._kinds[*].members`), кэш цели героя (раз в 3–5 кадров), деревья — отдельный `Array[WoodTree]` в `Grove`.

### M2. Нет единой проверки «ошибок в выводе» в `run_all.sh` — ИСПРАВЛЕНО
- Теперь `run_all.sh` проваливает тест при `SCRIPT ERROR`/`Parse Error`/`ERROR:`/`WARNING:`; намеренные ошибки — в `tests/expected_errors.txt` (регулярки). Утечки при выходе (`ObjectDB instances were leaked`, `resources still in use`) идут предупреждением в summary: источник — проигрываемые `AudioStreamPlaybackWAV` сцены `main` при `quit()`, устранить из тестов не удалось.
- Исходное описание:
- `tests/run_all.sh`: тест считается пройденным, если в выводе есть `RESULT: PASS`. `SCRIPT ERROR` печатается, но не проваливает тест; строки `ERROR:` (в т.ч. `Resumed function ... after await, but class instance is gone`) и `WARNING:` не ищутся вообще. CLAUDE.md требует «без ошибок и предупреждений».
- Предложение: провалить тест при `SCRIPT ERROR`/`Parse Error` и ввести allowlist для известных шумов (`ConfigFile parse error`, `resources still in use`).

### M3. Числа баланса в коде (CLAUDE.md: «в .tres или @export»)
- `scripts/wave_plan.gd:18` таблица `MIX` (каждый N-й слот/смещение), `wave_plan.gd:81` `1 + floori(wave / 30.0)` боссов, `BOSS_GROWTH_EXPONENT` — вся форма волны в константах.
- `scripts/tower_data.gd:7` `SELL_REFUND := 0.7`, `tower.gd` (`amount *= 0.8` в `_shoot_chain`), `main.gd:260` радиусы колец `0.8/1.1/0.5`, `villagers.gd` ок (`@export`).
- Предложение: вынести `MIX`/боссов в `levels.json` или `.tres` (`balance_sim.py` читает тот же источник), `SELL_REFUND` и `chain_falloff` — `@export`.

### M4. `main.gd` — «бог-объект» (983 строки)
Строит уровень, карточку команд, магазин, кузницу, торговлю, подсказки, обработку конца игры, паузу. Тяжело тестировать (тесты зовут приватные `_on_all_waves_cleared`, `_on_command_pressed`, `_forge_open`).
- Предложение: вынести `CommandCard` (сборка `info` для HUD, `_forge_card/_trade_card/_refresh_card`) и `LevelBuilder` (`_build_level/_plant_trees`) в отдельные скрипты по одному пункту ROADMAP.

### M5. Облако доверяет клиенту значения звёзд (rules + client)
- `firestore.rules:84`: `validProgression` проверяет только размеры `stars/endless/perks`, значения не ограничены (звёзды 0..3, волны, уровни перков). Клиентский `from_cloud` не зажимал звёзды (исправлено, `b536e9c`); на стороне rules лимиты всё ещё стоит добавить (хотя бы `stars.* <= 3`). Это самообман игрока, на таблицу рекордов не влияет (она защищена `runs/`).
- `endless` в профиле и в таблице рекордов — разные данные; рекорд в `leaderboards` проверяется нижней границей времени.

### M6. Рекорд осады теряется офлайн — ИСПРАВЛЕНО (частично, по правилам)
- `Online.submit_record` хранит неотправленный рекорд в секции `record_queue` сохранения и повторяет отправку (задержка x2 от 5 с до 300 с, до 8 попыток подряд, и при каждом `start()`). Запись `runs/{uid}` нельзя сделать задним числом (`startedAt == request.time`), поэтому рекорд забега, который не стартовал онлайн, в таблицу не попадает — остаётся только локальный. Отказ правил (4xx) снимает рекорд с очереди; новый успешный `start_run` тоже (его `startedAt` заменил старый). Тесты: `tests/test_records.gd`.
- Исходное описание:
- `scripts/online.gd` `submit_record` (fire-and-forget): при `ensure_token` fail/сетевой ошибке повторов нет; локальный рекорд сохранён (`LevelCatalog.save_endless`), но в таблицу уже не уйдёт. `start_run` тоже fire-and-forget: при потере запроса рекорд волны N будет отклонён правилами (`(N-1)*15 s` от `runs/{uid}.startedAt`) без сообщения игроку (только «Не удалось отправить рекорд»).
- Предложение: хранить «неотправленный рекорд» в профиле и отправлять при ближайшей синхронизации; при отсутствии `startedAt` — повторять `start_run`.

---

## MINOR

### Корректность / жизненный цикл
- **m1 (ИСПРАВЛЕНО: «Назад» на итоге = «К карте», `tests/test_units.gd`). Android «Назад» на экране итога ничего не делал.** `main.gd:191` `_toggle_pause` при `_ended` сразу `return`, а `quit_on_go_back=false`: на экране победы/поражения только кнопки. Предложение: назад = «К карте».
- **m2. `_pressed` в `BuildManager`** (`build_manager.gd`, `_unhandled_input`): если палец нажат на карте и игра ушла в паузу (Назад/звонок), отпускание придёт на паузе и не будет обработано; после снятия паузы следующее отпускание без нажатия станет «тапом». Предложение: сбрасывать `_pressed` в `main._toggle_pause` (как `camera.reset_touches()`).
- **m3. `CameraFollow._touches`** учитывает только события, дошедшие до `_unhandled_input`; палец, отпущенный над HUD, остаётся в словаре → `is_pinch_gesture()` может залипнуть до следующего касания (смягчено `reset_touches()` на паузе/потере фокуса).
- **m4. `Hud._on_end_button_pressed`** (`hud.gd:486`) выключает `_continue_button`, но `_show_menu` включает только Restart/Map. Если `reload_current_scene` вернёт ошибку (`main.gd` `_on_restart_pressed`), меню паузы остаётся без «Продолжить». Предложение: включать все три кнопки в `_show_menu`.
- **m5. `Hud.show_end_screen`** добавляет звёзды в `_stars` без очистки: при двойном вызове (пока был B1) получалось 6 звёзд. Теперь недостижимо, но очистка дешёвая.
- **m6. `await` после смены сцены.** `account_panel._on_sync_pressed`/`_on_new_guest` и `email_auth_dialog.submit` продолжают работу после `await Online...`; если за это время карта перезагрузилась (`cloud_loaded` → `reload_current_scene`, `account_switched`), движок печатает «Resumed function ... after await, but class instance is gone». Предложение: после `await` проверять `is_inside_tree()`.
- **m7. `LevelCatalog.data()`** (`level_catalog.gd:125`): если основной файл отсутствует (`ERR_FILE_NOT_FOUND`), а `.bak` есть (сбой между `copy` и `rename` в `commit`), `.bak` не используется. Редкий случай, но потеря прогресса.
- **m8. `WalkGrid.block/unblock`**: клетки, общие для двух башен, принадлежат первой; продажа первой освободит клетки под второй (при расстоянии между площадками ≥ 2.5 м не достижимо, но неочевидный инвариант).
- **m9. `Enemy._pulse`** (`enemy.gd:192`): новый `Tween` на каждое попадание, предыдущий не убивается — два твина одновременно пишут `visual_scale`; на волнах с сотнями попаданий в секунду — лишние аллокации. Предложение: хранить и `kill()` предыдущий, либо считать squash в `EnemyCrowd` по таймеру.
- **m10. `OneShotFx._alive`** (статический счётчик): декремент через `tree_exiting`; при реparent узла счётчик «уплывёт». Сейчас не используется.
- **m11. `Villagers.spawn`** (`villagers.gd`): синхронный перебор решётки 19×19 × `_room` (24 вызова `is_open`, каждый — `curve.get_closest_point` по всем путям) на кадре старта уровня; `WalkGrid.build` — по одному `intersect_shape` на клетку 0.5 м (карта 100×100 м ≈ 40 000 запросов). Для «больших карт» из ROADMAP может дать заметный фриз при загрузке; разбить по кадрам (`await get_tree().physics_frame` пачками) или кэшировать в `.tres`.
- **m12. `AuthService`**: `link_email`, `sign_in_email`, `delete_account` меняют `_id_token/_refresh_token` без общего `_in_flight`; параллельный `ensure_token` может затереть токены. `Online` защищает `_email_busy`, но сам класс — нет. `_expires_at` считается по системным часам (перевод часов ломает «свежесть» токена).
- **m13. `HttpTransport.send`**: нет `body_size_limit`/`download_chunk_size`; ответ любого размера читается целиком (Firestore ответы малы, но для REST-клиента стоит ограничить).
- **m14. `WavePlan`**: `boss_every == 0` → деление на ноль в `is_boss_wave` (проверить в `validate_project.py`); `count/hp_mult` обязательные ключи без значений по умолчанию.

### Производительность (мелкое)
- **p1.** `tutorial.gd:151` `_process` ищет `$Root` каждый кадр (строковый путь) и перерисовывает `_pointer` каждый кадр; `_draw_pointer`/`_draw_arrow` создают `PackedVector2Array` и `duplicate()` каждый кадр. Нужен `@onready var _root`.
- **p2.** `nickname_screen._process` / `email_auth_dialog._process`: каждый кадр читают `DisplayServer`/`ScreenUtil` и вызывают `add_theme_constant_override`. Лучше по `size_changed` и сигналу клавиатуры (`DisplayServer.virtual_keyboard_get_height` — опрос, но достаточно раз в 0.2 с).
- **p3.** `level_select._process` двигает кнопки уровней каждый кадр, хотя камера неподвижна; достаточно при `size_changed`.
- **p4.** `EnemyCrowd._process`: `_kinds.values()` дважды за кадр (аллокация `Array`), `part["rest"]`/`part["anim"]` — поиски по `Dictionary` на каждую часть каждого врага; `mm.set_instance_transform` на каждый экземпляр. Предложение: параллельные типизированные массивы и запись в `multimesh.buffer` одним `PackedFloat32Array`.
- **p5.** `TowerModel._process` каждый кадр вращает башни, даже когда цель не менялась.
- **p6.** `Hud._fill_button` пересоздаёт детей `Cost` при каждом изменении хэша карточки (ресурсы меняются часто) — приемлемо благодаря `info.hash()`, но `child.free()` вместо `queue_free()` в цикле стоит заменить.

### Стиль CLAUDE.md
- Порядок в файле: нарушений не найдено (проверены `main`, `hud`, `tutorial`, `level_select`, `account_panel`); `gdlint` чистый.
- Статическая типизация: `var x =` без типа и `func` без `->` в `scripts/` и `tests/` не найдено.
- `get_parent()` в игровом коде: только `enemy_crowd._rest_of` (по дереву модели, не по игровому) и `online.gd:79` (проверка транспорта) — допустимо. Абсолютных `/root/...` нет; `tests/` и `tools/` используют `root.get_node("Online")` — допустимо для тестов.
- Autoload: единственный `Online` (`project.godot`). Соответствует правилу.
- Связь вверх/вниз: `AccountPanel` читает `Online.auth.uid` и `Online.account_type()` напрямую (обход фасада): добавить `Online.uid()`.
- В `session_store.gd:12` соль `tinyguard/session/v1/...` и `nickname_rules.gd:26` резерв `tinyguard` — остатки старого имени (по задумке: имя в резерве); менять соль нельзя без миграции сессий.

### Мёртвый код
- `WaveManager.is_wave_active`, `alive_count`; `Hero.is_attacking`; `EnemyCrowd.multimesh_count` (нет вызовов); `AuthService.link_with_idp` (заглушка «not_available», только упоминания в тесте/доках); `Online.set_player_name`/`clean_name` — наследие до `NicknameRules`, `clean_name` держится ради одного теста.

---

## Качество тестов — что не покрыто
- Конец уровня через настоящий сигнал `WaveManager`: до B1 тесты вызывали `main._on_all_waves_cleared()` напрямую (поэтому гонку не видели). Теперь есть `test_endgame.gd`.
- Нет тестов: `WavePlan` (состав волн, `MIX`, боссы, endless-рост), `Enemy` (броня, замедление, split, лекарь), `Projectile` (дуга, splash), `Hero` (веер удара, вихрь, застревание/replan), `TowerSlot/BuildManager` (продажа, возврат при ошибке `place_tower`), `GameState.repair`, `LevelCatalog.replace_with`/`.bak`-восстановление при отсутствии основного файла (m7).
- UI: нет автотестов `Hud.update_card` (кеш по `hash`), `LevelSelect` (казна, покупка перка, блокировка уровней), `NicknameScreen` (кроме правил), `VirtualJoystick`/`CameraFollow` (pinch, `reset_touches`), `AccountPanel` (кроме скрытия e-mail без Firebase).
- Жизненный цикл: нет тестов поворота/`size_changed` (safe area), `APPLICATION_PAUSED/FOCUS_OUT` на мобильном (`OS.has_feature("mobile")` в headless всегда `false`), смены сцены во время `await Online...`.
- Утечки: сценарные тесты завершаются `quit()` без освобождения сцены, поэтому `ObjectDB instances were leaked` нельзя отличить от реальной утечки узлов. Предложение: в конце теста `current_scene.queue_free()`, `await process_frame`, и только потом `quit()` — тогда ненулевая утечка станет сигналом (и проверять `Performance.get_monitor(OBJECT_ORPHAN_NODE_COUNT)` до выхода).
- Тесты ждут кадры фиксированным числом (`for i in 10: await process_frame`); тесты на таймерах зависят от `--fixed-fps 60` (в `run_all.sh` для `test_online/accounts` фикса нет — они не завязаны на кадры).

## Что проверено и в порядке
- Утечек сигналов на автолоад `Online` нет: подписчики (`level_select`, `account_panel`) — узлы сцены; соединения с освобождаемым объектом Godot снимает сам. Лямбды подключены к сигналам дочерних узлов.
- Твины/таймеры: `HUD` убивает предыдущие `_hint_tween/_banner_tween`; `WoodTree`, `OneShotFx`, `LightningFx`, `Hero` используют `create_timer(..., false)` (учитывают паузу) и привязаны к узлу.
- Пауза: `process_mode` у конечного экрана/туториала/карты (`ALWAYS`), `_exit_tree` сбрасывает `Engine.time_scale`, `_on_restart/_on_map` снимают `paused`.
- Потеря фокуса: `main`, `camera_follow`, `virtual_joystick` обрабатывают `APPLICATION_PAUSED/FOCUS_OUT`; кнопка «Назад» обрабатывается в `boot`, `main`, `level_select`, `nickname_screen`.
- Материалы на инстанс не создаются (общие `.tres`; единственная правка `_ring_material` — один общий материал кольца). `Grove` и `EnemyCrowd` сводят деревья/врагов в `MultiMesh`.

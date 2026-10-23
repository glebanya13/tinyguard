# AGENTS.md — Bimbleguard для ИИ-агентов (любая модель)

Короткая карта проекта. Полные правила — в `CLAUDE.md` (читать обязательно перед правками).
Если что-то здесь расходится с кодом, прав код; поправь этот файл.

## Что это

Bimbleguard (бывш. Tinyguard) — лёгкая 3D Tower Defense для Android, альбомная ориентация,
касания. **Godot 4.7.2, только GDScript**, рендерер Compatibility. Герой-рыцарь рубит деревья
(дерево = второй ресурс), ставит башни на площадки, враги идут по дорогам к замку.
Пакет `com.bimbleguard.app`. Игра полностью работает офлайн; сеть (Firebase REST) необязательна.

## Жёсткие запреты (из CLAUDE.md)

- Не C#, не GDExtension, не плагины. Новых autoload нельзя (есть один: `Online`).
- Нет внешних ассетов. Модели генерируются скриптами `assets/blender/build_*.py` (правь скрипт,
  пересобирай, `.glb` руками не трогай); звуки — `tools/gen_sounds.py`.
- Не мутировать общие материалы (`assets/materials/tg_palette.tres`, скины из `Cosmetics`):
  для подсветки/призрака делай свою копию материала.
- Статическая типизация везде, табы, строки ≤ 100 символов, стиль Godot.
- Без аналитики и рекламных SDK. Из Firebase SDK разрешён только Crashlytics.
- Не утверждай «работает», если не запускал. Не пушь и не коммить без просьбы владельца.

## Карта кода

| Что | Где |
|---|---|
| Точка входа боя | `scenes/main.tscn`, `scripts/main.gd` (оркестрация, ~1100 строк) |
| Детерминированная симуляция (30 Гц) | `scripts/sim.gd`, команды `scripts/game_commands.gd`, журнал `command_log.gd` |
| Волны | `wave_plan.gd` (что и сколько), `wave_manager.gd` (когда), данные `resources/levels.json` |
| Данные баланса | `resources/balance.json`, `towers/*.tres`, `enemies/*.tres`, `mercenary.tres`, `villager_trade.tres`, `castle_upgrades.json`, `economy.json` |
| Башни и стройка | `build_manager.gd`, `tower_placement_controller.gd` (призрак), `card_controller.gd` (карточки/кузница), `command_cards.gd` |
| Герой | `hero.gd`; камера `camera_follow.gd`, `game_camera.gd` |
| Экономика / дерево / жители | `economy.gd`, `villagers.gd`, `camp_structures.gd`, `mercenary_config.gd` |
| Уровни | `level_catalog.gd` (выбор, прогресс), `level_builder.gd` (сборка сцены) |
| Старт боя и продолжение | `battle_setup.gd`, `battle_checkpoint.gd`; фаза осмотра карты до кнопки «В бой» |
| Интерфейс | `hud.gd`, `level_select.gd`, `ui/hud.tscn`, `ui/theme.tres` |
| Сеть | `online.gd` (фасад) + `online_*`, `auth_service.gd`, `rtdb_client.gd`, кооператив `coop_*.gd` |
| Тексты | `translations/strings.csv` (12 языков, ключи вида `LEVEL_4_SUB`) |

Связь: вниз — вызовом методов, вверх — сигналами. Без `get_parent()` и `/root/...`.
Числа баланса — в `.tres`/`.json`, не в коде.

## Как проверять (делай перед любым «готово»)

```bash
GODOT=/Applications/Godot.app/Contents/MacOS/Godot
python3 tools/validate_project.py                      # структура и ссылки
$GODOT --headless --path . --import                    # импорт (перезаписывает translations/*.translation!)
tests/run_all.sh $GODOT                                # ~120 запусков, 10–15 минут
tests/run_all.sh $GODOT --only "battle_start|placement" # выборочно
python3 tools/balance_sim.py [--table] [--diff 2] [--chop 0.8] [--econ]   # баланс, без Godot
```

Стиль: `gdlint scripts/*.gd tests/*.gd`, `gdformat --line-length 100 --check <файлы>`
(`pip install gdtoolkit`). Новый тест: `tests/test_*.gd`, `extends SceneTree`, `check(cond, msg)`,
в конце `RESULT: PASS (0 failures)`; **обязательно добавь строку в `tests/run_all.sh`**, иначе его никто не запускает.

## Ловушки (уже кусались)

1. **Локализация.** Правь только `translations/strings.csv`, затем `--import` пересоберёт
   `*.translation`. Не правь `.translation` вручную. Не переводи «летуны» как «flyers/листовки».
2. **Детерминизм.** Любое изменение баланса/волн/правил меняет `state_hash`. После этого
   перепиши эталоны: `tests/test_old_journal.gd` (`GOLDEN`, снимай вывод `GOLDEN <ключ>: [...]`
   дважды — должен совпасть) и `LEGACY_HASH` в `tests/test_wood_economy.gd`.
3. **Тесты не должны зашивать числа баланса** — читай из `.tres`/`levels.json` (так упали
   `test_gameplay`, `test_encyclopedia`).
4. **Сохранения.** Тесты бегут с изолированным `HOME`; запуск теста мимо `run_all.sh` может
   затронуть реальные сохранения пользователя (`user://`).
5. **Worktree агентов** создаются от старого коммита: перед работой сверь базу с текущей веткой.
6. **Известный флак:** `test_villagers` («card opens again after walking away») — падал и до правок.
7. **Общие материалы:** призрак башни ранее красил общий скин — все башни становились
   зелёными/красными. Призрак использует собственные материалы.
8. `build/`, `android/`, `out/`, `*.keystore`, `firebase.cfg`, `google-services.json` не коммитятся.

## Релиз Android

Версия — `version/code` и `version/name` в **трёх** пресетах `export_presets.cfg` +
`config/version` в `project.godot`; `code` растёт на каждую выкладку. AAB (Gradle, подпись
ключом загрузки вне репозитория): см. `docs/ANDROID_BUILD.md`, команда
`godot --headless --path . --export-release "Android Play (AAB)" build/bimbleguard.aab`.

## Куда смотреть в документах

| Нужно | Файл |
|---|---|
| Правила и стек | `CLAUDE.md` |
| Механики, таблица уровней | `docs/GAME_DESIGN.md` |
| Экономика, баланс, ревизия по отзывам | `docs/ECONOMY_V2.md` (§0.2 — актуально) |
| Архитектура, симуляция, эффекты | `docs/TECHNICAL_DESIGN.md` |
| Свежий аудит (2026-10-23) | `docs/AUDIT_2026-10-23.md` |
| Прошлый аудит (21–22.10, 8 частей) | `docs/audit/` (бэклог — `08_actionable_backlog.md`) |
| Кооператив | `docs/MULTIPLAYER.md` |
| Firebase, аккаунты, безопасность | `docs/FIREBASE.md`, `ACCOUNTS.md`, `SECURITY_AUDIT.md` |
| Сборка Android, Play | `docs/ANDROID_BUILD.md`, `RELEASE_READINESS.md`, `STORE_LISTING.md` |
| Арт-бюджеты (врагу ≤ 2000 треугольников, башне ≤ 4000, герою ≤ 12000) | `docs/ART_GUIDE.md` |

Часть документов устарела (README, HANDOFF, ROADMAP — на 2026-10-15): сверяйся с кодом и
`docs/AUDIT_2026-10-23.md`.

## Как работать

Маленькие шаги, один пункт за раз; не добавляй систем «на будущее». Сначала прочитай
файлы, которые меняешь, и соседние тесты. Меняешь механику — обнови `docs/`. Коммиты —
conventional commits на английском.

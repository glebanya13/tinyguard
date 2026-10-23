# Bimbleguard

Небольшая оригинальная 3D Tower Defense для Android в low-poly стиле.
Движок — **Godot 4.7.2**, язык — **GDScript**, рендерер **Compatibility** (OpenGL ES 3).
Пакет `com.bimbleguard.app`. Версия **0.6.2** (код 9).

> Статус: закрытое тестирование. Автотесты (headless Godot) проходят; на реальном
> Android-устройстве и в живом Firebase проверка ещё не завершена. Актуальный список проблем —
> [`docs/AUDIT_2026-10-23.md`](docs/AUDIT_2026-10-23.md). Для ИИ-агентов — [`AGENTS.md`](AGENTS.md).

## Игра

Рыцарь защищает замок от волн слаймов-«чупакабр». Дерево — второй ресурс: его рубит рыцарь
(и нанятые лесорубы), золото дают убитые враги. Башни ставятся на площадки и вручную в выбранных
местах; их можно улучшать и продавать.

- **6 уровней** в 4 биомах, 10–30 волн, 4–6 дорог с разных сторон; боссы; «Игра на рекорд» (осада:
  бесконечные волны, каждая тяжелее) с онлайн-таблицей; три сложности.
- **4 башни:** лучник, пушка (сплеш), мороз (замедление), молния (цепная, игнорирует броню).
- **10 видов врагов:** быстрые, танки, щитовики, целители, делящиеся, летуны, големы, короли.
- **Рыцарь:** удар, «Вихрь», рубка деревьев; кузница (меч, ремонт замка), улучшение замка.
- **Жители и лагеря:** покупка и продажа дерева, лесорубы, наёмники (лимит 3, цена растёт).
- **Мета:** звёзды, «Королевская казна» с постоянными улучшениями, достижения, ежедневный вызов,
  календарь, косметика, энциклопедия (башни, бестиарий, деревня).
- **Онлайн (необязательно):** аккаунты, рекорды, облачное сохранение, кооператив на двоих
  (Firebase REST, `docs/FIREBASE.md`, `docs/MULTIPLAYER.md`). Без `firebase.cfg` игра полностью
  работает офлайн.
- **12 языков** (`translations/strings.csv`).

## Ход боя

1. Фаза осмотра: камера двигается пальцем (или WASD/мышью), рыцарь стоит, строить и рубить нельзя.
2. Кнопка **«В бой!»** запускает бой; первая волна приходит через 30 секунд (на экране идёт отсчёт),
   дальше волны идут сами каждые 30 секунд.
3. Кнопка **«Волна сейчас»** (когда поле чисто) вызывает следующую волну раньше срока и даёт бонус золота;
   в кооперативе и обучении её нет.
4. «Продолжить» на карте возвращает бой с последнего чекпоинта: позиция рыцаря, таймер и номер волны.

## Управление

| Действие | Клавиатура / мышь | Геймпад | Телефон |
|---|---|---|---|
| Идти | WASD / стрелки, клик по земле | левый стик | экранный джойстик, тап по земле |
| Удар / рубка | Пробел или J (стоя рядом — сам) | X | круглая кнопка (меч или дерево) |
| «Вихрь» (раз в 12 с) | Q или E | LB | кнопка над ударом |
| Камера | колесо мыши; в осмотре — перетаскивание | — | щипок; в осмотре — перетаскивание |
| Выбрать площадку | клик по ней или подойти | подойти | тап или подойти |
| Лучник / Пушка / Мороз / Молния | 1 или B / 2 или N / 3 или M / 4 или L | A | кнопки карты |
| Улучшить / продать (70 %) | U / X | Y | кнопки карты |
| Кузница | K | — | кнопка с молотом |
| ×2 / пауза | F / P | — / Start | кнопки в углу |

Цены, характеристики и роли башен — в `resources/towers/*.tres` и энциклопедии в игре
(лучник 15 з + 8 д, пушка 45 + 20, мороз 30 + 20, молния 45 + 25).

![Уровень 1](docs/screenshots/level_01.png)

## Структура репозитория

```
├── project.godot            # Compatibility, landscape, autoload Online
├── export_presets.cfg       # Android (APK), Android Play (AAB), Android Debug (Gradle)
├── scenes/ scripts/ ui/     # игра (main.tscn — точка входа боя; scripts/ — по скрипту на систему)
├── resources/               # данные: levels.json, balance.json, towers/ enemies/ perks/ *.tres
├── assets/                  # blender/ (скрипты, генерирующие все модели), models/, audio/, materials/
├── translations/            # strings.csv (источник) и собранные *.translation
├── tests/                   # headless-тесты, запуск: tests/run_all.sh
├── tools/                   # balance_sim.py, validate_project.py, gen_sounds.py, prepare_android_build.py …
├── firebase/                # правила Firestore/RTDB и их тесты
├── website/                 # сайт игры
└── docs/                    # дизайн, архитектура, аудиты, сборка, магазин
```

Модели и звуки генерируются скриптами (`assets/blender/build_*.py`, `tools/gen_sounds.py`):
правьте скрипт, а не готовый файл. Внешних ассетов нет (кроме иконок с атрибуцией, см. `docs/CREDITS.md`).

## Запуск и сборка

Нужны Godot **4.7.2** (стандартная сборка, не .NET) и export templates той же версии;
для Android ещё JDK 17 и Android SDK.

```bash
godot --headless --path . --import   # первый импорт (создаёт .godot/, регистрирует class_name)
godot --path .                       # запустить игру
```

Android: debug APK и релизный AAB для Google Play — `docs/ANDROID_BUILD.md`. Версию поднимайте
в трёх пресетах `export_presets.cfg` и в `config/version` (`project.godot`).

## Проверки

```bash
python3 tools/validate_project.py          # структура и ссылки
tests/run_all.sh <godot>                   # все headless-тесты (≈ 120 запусков)
gdlint scripts tests tools                 # стиль (pip install gdtoolkit)
gdformat --line-length 100 --check scripts tests tools
python3 tools/balance_sim.py --table       # баланс-симулятор (без Godot)
cd firebase/rules-tests && npm test        # правила Firebase
```

## Документы

| | |
|---|---|
| Правила проекта | [`CLAUDE.md`](CLAUDE.md), [`AGENTS.md`](AGENTS.md) |
| Механики и уровни | [`docs/GAME_DESIGN.md`](docs/GAME_DESIGN.md) |
| Экономика и баланс | [`docs/ECONOMY_V2.md`](docs/ECONOMY_V2.md) |
| Архитектура | [`docs/TECHNICAL_DESIGN.md`](docs/TECHNICAL_DESIGN.md) |
| Аудиты | [`docs/AUDIT_2026-10-23.md`](docs/AUDIT_2026-10-23.md), [`docs/audit/`](docs/audit/) |
| План и передача работы | [`docs/ROADMAP.md`](docs/ROADMAP.md), [`docs/HANDOFF.md`](docs/HANDOFF.md) |
| Онлайн, кооператив | [`docs/FIREBASE.md`](docs/FIREBASE.md), [`docs/MULTIPLAYER.md`](docs/MULTIPLAYER.md) |
| Android, Google Play | [`docs/ANDROID_BUILD.md`](docs/ANDROID_BUILD.md), [`docs/RELEASE_READINESS.md`](docs/RELEASE_READINESS.md) |
| Арт и интерфейс | [`docs/ART_GUIDE.md`](docs/ART_GUIDE.md), [`docs/UI_STYLE_GUIDE.md`](docs/UI_STYLE_GUIDE.md) |

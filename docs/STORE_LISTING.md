# Карточка в Google Play (RU + EN)

Черновик для владельца. Лимиты Play: название до 30 символов, краткое описание до 80, полное
до 4000. Название «Bimbleguard» рабочее (`GameInfo.TITLE`); проверьте уникальность и товарный
знак. Категория: Games -> Strategy. Контакт: `GameInfo.SUPPORT_EMAIL` (TODO), политика:
`GameInfo.PRIVACY_URL` (TODO).

## RU

**Название:** Bimbleguard: Башни и рыцарь

**Краткое описание:** Защити замок: ставь башни, веди рыцаря, отбей чупакабр. Без рекламы.

**Полное описание:**

Bimbleguard: лёгкая 3D-защита башнями в мультяшном стиле, сделанная для телефона.

Строй башни на площадках, собирай дерево и золото, веди рыцаря джойстиком и отбивай волны
чупакабр. Улучшай замок в кузнице, повышая жизни и броню от протечек. За каждый уровень можно
получить до трёх звёзд, а звёзды открывают постоянные улучшения в казне.

Что внутри:
• 6 уровней с растущей сложностью
• Рыцарь под твоим управлением: бегай, руби деревья, торгуй с жителями, бей вертушкой
• Улучшение замка: повышай прочность и броню цитадели
• Несколько видов башен и улучшения за звёзды
• Бесконечная осада: сколько волн выдержишь? Таблица рекордов игроков
• Необязательное облачное сохранение: привяжи почту и продолжай на другом телефоне
• Работает без интернета, ставит игру на паузу при звонке, звук можно выключить
• Без рекламы и без донатов

Онлайн-функции (рекорды, облачное сохранение) необязательны. Аккаунт и данные можно удалить в
«Профиле». Мы не собираем аналитику и не показываем рекламу.

**Ключевые слова (вплести в описание):** защита башнями, tower defense, стратегия, осада,
офлайн, без рекламы, 3D, low poly, рыцарь.

**Что нового (0.6.0):**
• Улучшение замка в кузнице: прокачка жизней и брони от прорыва врагов.
• Чупакабры вместо слаймов: обновлённый бестиарий и визуал врагов.
• Новый благородный облик рыцаря и переработанные скины.
• Единая система окон DialogFrame с поддержкой вырезов экрана и безопасных зон.
• Перк казны «Быстрые ноги» (+6/12/18 % к скорости рыцаря).

## EN

**Title:** Bimbleguard: Tower Defense & Knight

**Short description:** Defend the castle: build towers, lead your knight, repel chupacabras. No ads.

**Full description:**

Bimbleguard is a light, cartoon-style 3D tower defense made for phones.

Build towers on plots, gather wood and gold, steer your knight with a joystick and repel waves of
chupacabras. Upgrade your castle in the forge to bolster HP and leak armor. Every level awards up
to three stars, unlocking permanent perks in the Treasury.

Features:
• 6 distinct levels with rising difficulty
• A knight you control: run, chop trees, trade with villagers, unleash whirlwind attacks
• Castle upgrades: enhance durability and armor against leaks
• Several tower types and star-powered upgrades
• Endless Siege: how many waves can you hold? Player leaderboard
• Optional cloud save: link an e-mail and continue on another phone
• Works offline, pauses on calls, sound can be muted
• No ads, no in-app purchases

Online features (leaderboard, cloud save) are optional. You can delete your account and data
from the Profile screen. No analytics, no ads.

**Keywords (work into the text):** tower defense, strategy, siege, offline, no ads, 3D, low poly, knight.

**What's new (0.6.0):**
• Castle upgrades in the forge: increase HP and armor against leaking monsters.
• Chupacabras replace slimes: fresh enemy designs and visuals.
• Redesigned knight hero model and polished skins.
• Unified DialogFrame system with notch and cutout safe-area handling.
• New Treasury perk 'Swift feet' (+6/12/18 % knight movement speed).

Локализация: интерфейс игры полностью RU + EN (`translations/strings.csv`, язык по системной
локали, переключается в Настройках), поэтому EN-описание можно публиковать как основное для
не русскоязычных стран. Скриншоты обоих языков: `docs/screenshots/i18n_en_*.png` и
`docs/screenshots/i18n_ru_*.png` (`tools/shot_i18n.gd`); для карточки Play брать EN-набор
(карта, казна, настройки, бой с баннером волны, карточка башни).

## Графика (готова, `assets/store/`)

Требования Play сверены 2026-10-14 со страницей
<https://support.google.com/googleplay/android-developer/answer/9866151>: иконка 512x512, 32-bit PNG,
до 1024 КБ; feature graphic 1024x500, JPEG или 24-bit PNG без альфы; скриншоты JPEG или 24-bit PNG
без альфы, стороны 320-3840 px, длинная сторона не более чем вдвое длиннее короткой, до 8 шт. на тип
устройства; для игр в больших форматах рекомендуется не менее 3 скриншотов 1920x1080.

| Ресурс | Файл | Размер | Как получен |
|---|---|---|---|
| Иконка | `icon_512.png` | 512x512 RGBA, непрозрачная (~142 КБ) | `tools/render_store_art.gd`, та же композиция, что у иконки лаунчера, на квадрате без скруглений (углы скругляет Play) |
| Feature graphic | `feature_1024x500.png` | 1024x500 RGB, без альфы (~218 КБ) | `tools/render_store_art.gd`: замок, 4 башни, герой, чупакабры, название |
| Скриншоты 1-8 | `shot_01_map.png` ... `shot_08_treasury.png` | 1920x1080 RGB (0.25-1 МБ) | `tools/shot_store.gd`: карта, уровни 1/4/5/6 с башнями и волной, апгрейд башни, обучение, казна |

Снимки детерминированные (фиксированные уровни, башни, кадры), HUD в телефонной раскладке. Генерация
(нужно окно, не `--headless`; сначала `godot --headless --path . --import`):

```
godot --path . --rendering-driver opengl3 --fixed-fps 60 --resolution 1920x1080 --script res://tools/shot_store.gd
godot --path . --rendering-driver opengl3 --script res://tools/render_store_art.gd
```

`SHOT_ONLY=map,upgrade,profile` снимает выбранное (`profile`, панель профиля, только по запросу),
`SHOT_DIR` задаёт каталог. Для проверки адаптации запустите с `--resolution 2556x1179` или `2160x1080`
и `SHOT_DIR` вне проекта (в Play эти размеры не загружаются, 2556 > 1920 допустимо, но не нужно).
Тексты на снимках русские, как и интерфейс игры; подписей поверх кадров нет.
Скриншоты планшетов (7"/10") не снимались: при необходимости запустить `shot_store.gd` с
`--resolution 2560x1600` (16:10, Play просит 16:9 или 9:16 в диапазоне 1080-7680).

## Ответы Console

- Реклама: нет. Покупки: нет. Цена: бесплатно.
- Аудитория: 13+ (не детская, Families не участвует). IARC: мультяшное насилие против
  фэнтези-существ; взаимодействие пользователей: только ник в таблице рекордов.
- Data safety: `docs/DATA_SAFETY.md`. Политика: `PRIVACY_URL`. Удаление: `DELETION_URL`.

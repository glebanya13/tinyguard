# Карточка в Google Play (RU + EN)

Черновик для владельца. Лимиты Play: название до 30 символов, краткое описание до 80, полное
до 4000. Название «Bimbleguard» рабочее (`GameInfo.TITLE`); проверьте уникальность и товарный
знак. Категория: Games -> Strategy. Контакт: `GameInfo.SUPPORT_EMAIL` (TODO), политика:
`GameInfo.PRIVACY_URL` (TODO).

## RU

**Название:** Bimbleguard: Башни и герой

**Краткое описание:** Защити замок: ставь башни, веди героя, выстой в осаде. Без рекламы.

**Полное описание:**

Bimbleguard: лёгкая 3D-защита башнями в мультяшном стиле, сделанная для телефона.

Строй башни на площадках, собирай дерево и золото, веди героя джойстиком и отбивай волны
врагов. За каждый уровень можно получить до трёх звёзд, а звёзды открывают постоянные
улучшения.

Что внутри:
• 6 уровней с растущей сложностью
• Герой под твоим управлением: бегай, руби деревья, торгуй с жителями
• Несколько видов башен и улучшения за звёзды
• Бесконечная осада: сколько волн выдержишь? Таблица рекордов игроков
• Необязательное облачное сохранение: привяжи почту и продолжай на другом телефоне
• Работает без интернета, ставит игру на паузу при звонке, звук можно выключить
• Без рекламы и без донатов

Онлайн-функции (рекорды, облачное сохранение) необязательны. Аккаунт и данные можно удалить в
«Профиле». Мы не собираем аналитику и не показываем рекламу.

**Ключевые слова (вплести в описание):** защита башнями, tower defense, стратегия, осада,
офлайн, без рекламы, 3D, low poly.

**Что нового (0.4.0):** Первый релиз: 6 уровней, бесконечная осада с таблицей рекордов,
аккаунты и облачное сохранение, обучение, пауза при звонке, кнопка «Назад».

## EN

**Title:** Bimbleguard: Tower Defense

**Short description:** Defend the castle: build towers, lead your hero, survive the siege. No ads.

**Full description:**

Bimbleguard is a light, cartoon-style 3D tower defense made for phones.

Build towers on plots, gather wood and gold, steer your hero with a joystick and repel waves of
enemies. Every level awards up to three stars, and stars unlock permanent upgrades.

Features:
• 6 distinct levels with rising difficulty
• A hero you control: run, chop trees, trade with villagers
• Several tower types and star-powered upgrades
• Endless Siege: how many waves can you hold? Player leaderboard
• Optional cloud save: link an e-mail and continue on another phone
• Works offline, pauses on calls, sound can be muted
• No ads, no in-app purchases

Online features (leaderboard, cloud save) are optional. You can delete your account and data
from the Profile screen. No analytics, no ads.

**Keywords (work into the text):** tower defense, strategy, siege, offline, no ads, 3D, low poly.

**What's new (0.4.0):** First release: 6 levels, Endless Siege with leaderboard, accounts and
cloud save, tutorial, pause on calls, Android Back button support.

Локализация: интерфейс игры полностью RU + EN (`translations/strings.csv`, язык по системной
локали, переключается в Настройках), поэтому EN-описание можно публиковать как основное для
не русскоязычных стран. Скриншоты обоих языков: `docs/screenshots/i18n_en_*.png` и
`docs/screenshots/i18n_ru_*.png` (`tools/shot_i18n.gd`); для карточки Play брать EN-набор
(карта, казна, настройки, бой с баннером волны, карточка башни).

## Графика (TODO владельцу)

| Ресурс | Размер | Источник |
|---|---|---|
| Иконка | 512x512 PNG, 32-bit alpha, до 1 МБ | `tools/render_app_icon.gd` (сейчас `icon.png` 192x192) |
| Feature graphic | 1024x500 JPEG/PNG без альфы | из арта карты |
| Скриншоты телефона | ландшафт 16:9, например 1920x1080; 2-8 шт. | реальные снимки с устройства |

## Ответы Console

- Реклама: нет. Покупки: нет. Цена: бесплатно.
- Аудитория: 13+ (не детская, Families не участвует). IARC: мультяшное насилие против
  фэнтези-существ; взаимодействие пользователей: только ник в таблице рекордов.
- Data safety: `docs/DATA_SAFETY.md`. Политика: `PRIVACY_URL`. Удаление: `DELETION_URL`.

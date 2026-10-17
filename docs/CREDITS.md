# Credits / Лицензии сторонних материалов

Сторонние материалы: шрифты под SIL OFL 1.1 (лицензии рядом с файлами) и силуэты иконок с
game-icons.net под CC BY 3.0 (разрешены владельцем 2026-10-17 при обязательной атрибуции, см.
ниже). Атлас панелей и кнопок, остальные иконки и эмблемы биомов нарисованы собственными
скриптами. Раньше использовались наборы Kenney (CC0): с 2026-10-17 они не нужны, файлы и
скрипт сборки удалены.

## game-icons.net, Creative Commons Attribution 3.0 (CC BY 3.0)

- Источник: https://game-icons.net (архив https://game-icons.net/archives/000000/transparent/game-icons.net.svg.zip,
  скачан 2026-10-17 с официальной страницы). Лицензия: https://creativecommons.org/licenses/by/3.0/ ,
  текст архива: `tools/icon_src/LICENSE-game-icons.txt`.
- Что взято: только силуэты в `tools/icon_src/*.svg` (имя файла = `автор__название`). Силуэты
  перекрашены (градиент, блик, тень) и обработаны скриптом `tools/make_ui_icons.py`; готовые PNG в
  `ui/icons/`. Исходные файлы не менялись.
- Атрибуция (обязательна): **Icons made by Lorc, Delapouite and Carl Olsen. Available on https://game-icons.net**
  (изменены: перекрашены).
- Где показано: в игре «Настройки -> Авторы» (`scripts/settings_panel.gd`, строки `CREDITS_*`),
  на сайте страница «Terms of Use / Условия использования», раздел Credits / Авторы
  (`website/src/content/{en,ru}.ts`), здесь.

| Иконка (`ui/icons/`) | Силуэт | Автор |
|---|---|---|
| chest | locked-chest | Lorc |
| crown | crown | Lorc |
| gear | cog | Lorc |
| flag | flying-flag | Lorc |
| hourglass | hourglass | Lorc |
| hammer (кузница) | anvil-impact | Lorc |
| axe | wood-axe | Lorc |
| lock | padlock | Lorc |
| map | treasure-map | Lorc |
| compass | compass | Lorc |
| tower_archer | pocket-bow | Lorc |
| tower_cannon | cannon | Lorc |
| tower_frost | snowflake-1 | Lorc |
| tower_lightning | lightning-storm | Lorc |
| trophy | trophy-cup | Delapouite |
| sound_on / sound_off | speaker / speaker-off | Delapouite |
| wood | wood-pile | Delapouite |
| shop | shop | Delapouite |
| flame | flame | Carl Olsen |

Остальные иконки (монета, самоцвет, звезда, сердце, меч, щит, стрелки, облако, друзья и др.)
нарисованы `tools/make_ui_icons.py` без внешних источников.

## Rubik (шрифт), SIL Open Font License 1.1

- Авторы: The Rubik Project Authors, https://github.com/googlefonts/rubik
  (файл из https://github.com/google/fonts/tree/main/ofl/rubik, загружен 2026-10-17)
- Лицензия: OFL 1.1, `assets/fonts/rubik/OFL.txt`
- Файл: `assets/fonts/rubik/Rubik.ttf` (вариативный, вес 300-900), без изменений. В теме
  (`ui/theme.tres`) заголовки, кнопки и цифры HUD: вес 900 / 800 (`FontVariation`).
- Покрытие проверено `fontTools` (все А-Яа-яЁё, цифры, знаки `. , : ; ! ? - — … « » № × % + / ( )`):
  отсутствуют только стрелка U+2192, галочка U+2713 и звезда U+2605; в тексте их заменяют
  системные шрифты, значки рисуются картинками.
- Отброшены при выборе: Lilita One (нет кириллицы), Luckiest Guy (нет в репозитории шрифтов
  и нет кириллицы). Russo One, Unbounded, Montserrat Alternates, Marmelad, Philosopher,
  Yeseva One проверены (кириллица есть), но Rubik Black лучше читается с обводкой в 22-48 px.

## Nunito (шрифт), SIL Open Font License 1.1

- Авторы: The Nunito Project Authors, https://github.com/googlefonts/nunito
  (файл взят из https://github.com/google/fonts/tree/main/ofl/nunito)
- Лицензия: OFL 1.1, `assets/third_party/nunito/OFL.txt`
- Файл: `assets/fonts/Nunito.ttf` (вариативный, вес 800 задан в `ui/theme.tres`: основной текст), без изменений.
- Покрытие: латиница и кириллица (полностью). Нет стрелки U+2192 и галочки U+2713:
  движок берёт их из системного шрифта (на Android — Noto/Roboto).

## Собственные файлы

- `ui/theme_atlas.png` и `ui/theme.tres` - `tools/make_ui_atlas.py` (Pillow, детерминированно).
- `ui/icons/*.png` (включая `tower_*.png`, кроме портретов врагов) - `tools/make_ui_icons.py`;
  портреты врагов - рендер моделей (`tools/render_icons.gd`).
- `ui/biomes/*.png` - эмблемы биомов карточки уровня, `tools/make_biome_art.py`.
- `ui/app/backdrop.jpg` - размытый и затемнённый фрагмент `assets/brand/logo.png` (фон лобби и ввода ника).

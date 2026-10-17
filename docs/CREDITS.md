# Credits / Лицензии сторонних материалов

Сторонние материалы: только шрифты под SIL OFL 1.1. Лицензии лежат рядом с файлами.
Весь UI-арт (атлас панелей и кнопок, иконки, эмблемы биомов) нарисован собственными
скриптами и внешних картинок не содержит. Раньше использовались наборы Kenney (CC0): с
2026-10-17 они не нужны, файлы и скрипт сборки удалены.

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
- `ui/icons/*.png` (кроме порталов башен и врагов) - `tools/make_ui_icons.py`; `tower_*.png` -
  `tools/make_tower_icons.py`; портреты врагов - рендер моделей (`tools/render_icons.gd`).
- `ui/biomes/*.png` - эмблемы биомов карточки уровня, `tools/make_biome_art.py`.
- `ui/app/backdrop.jpg` - размытый и затемнённый фрагмент `assets/brand/logo.png` (фон лобби и ввода ника).

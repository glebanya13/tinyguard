# Credits / Лицензии сторонних материалов

Все материалы ниже распространяются на условиях CC0 / SIL OFL, атрибуция не требуется,
но указана добровольно. Внешние UI-ассеты разрешены владельцем проекта 2026-10-15.
Лицензии лежат рядом с материалами в `assets/third_party/<набор>/`.

Дата загрузки всех наборов: 2026-10-15, скачаны с официальных страниц; лицензия проверена
по файлу `License.txt` внутри архива.

## Kenney UI Pack (v2.0), CC0

- Автор: Kenney (www.kenney.nl), страница: https://kenney.nl/assets/ui-pack
- Лицензия: Creative Commons Zero (CC0 1.0), `assets/third_party/kenney_ui_pack/LICENSE.txt`
- Использованы (PNG `Double`, цвета Yellow, Blue, Green, Red, Grey): `button_rectangle_depth_gloss`,
  `button_rectangle_gloss`, `button_round_depth_gloss`, `button_round_gloss`, `Extra/icon_play_light`,
  `Extra/icon_repeat_light`.
- Что изменено: уменьшены вдвое, «жёсткое» двухцветное деление кнопки заменено вертикальным
  градиентом, вариант hover подсвечен, серый затемнён (disabled); всё собрано в один атлас
  `ui/theme_atlas.png`; значки play/restart перекрашены и получили обводку (`ui/icons/play.png`,
  `restart.png`). Скрипт: `tools/build_ui_atlas.py`.

## Kenney UI Pack - Adventure (v1.1), CC0

- Автор: Kenney, страница: https://kenney.nl/assets/ui-pack-adventure
- Лицензия: CC0 1.0, `assets/third_party/kenney_ui_pack_adventure/LICENSE.txt`
- Использован: `PNG/Double/panel_brown.png` (рамка 9-slice).
- Что изменено: перекрашен в тёмно-индиго панель с золотой рамкой (палитра логотипа), уменьшен
  вдвое, два оттенка (панель и «чип»); в атласе `ui/theme_atlas.png`.

## Kenney Game Icons, CC0

- Автор: Kenney Vleugels (www.kenney.nl), страница: https://kenney.nl/assets/game-icons
- Лицензия: CC0, `assets/third_party/kenney_game_icons/LICENSE.txt`
- Использованы (PNG `White/2x`): `pause`, `fastForward`, `audioOn`, `audioOff`, `gear`, `cross`.
- Что изменено: белые глифы увеличены, залиты градиентом, получили тёмную обводку и мягкую тень
  в стиле остальных иконок; `sound_off` дополнен красным крестом. Результат:
  `ui/icons/{pause,speed,sound_on,sound_off,gear,cancel}.png`.

## Nunito (шрифт), SIL Open Font License 1.1

- Авторы: The Nunito Project Authors, https://github.com/googlefonts/nunito
  (файл взят из https://github.com/google/fonts/tree/main/ofl/nunito)
- Лицензия: OFL 1.1, `assets/third_party/nunito/OFL.txt`
- Файл: `assets/fonts/Nunito.ttf` (вариативный, вес 700 задан в `ui/theme.tres`), без изменений.
- Покрытие: латиница и кириллица (полностью). Нет стрелки U+2192 и галочки U+2713:
  движок берёт их из системного шрифта (на Android — Noto/Roboto).

## Производные и собственные файлы

- `ui/icons/star_empty.png` - обесцвеченная копия `ui/icons/star.png` (собственная модель).
- `ui/app/backdrop.jpg` - размытый и затемнённый фрагмент `assets/brand/logo.png` (фон лобби и ввода ника).
- Остальные иконки в `ui/icons/` - рендер собственных моделей (`tools/render_icons.gd`).

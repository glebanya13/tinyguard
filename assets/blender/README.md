# Blender asset scripts

Все 3D-модели Bimbleguard генерируются Python-скриптами для Blender. **Источник
правды — скрипты**, а не `.glb`: правьте скрипт и пересобирайте.

| Скрипт | Что строит (`assets/models/`) |
|---|---|
| `build_hero.py` | `hero_knight.glb` — рыцарь, анимация `idle` |
| `build_tower.py` | `tower_archer.glb` (анимация `attack`), `arrow.glb` (кольцо площадки запекается в террейн) |
| `build_chupa.py` | `slime*.glb` (имена файлов прежние) — чупакабры: обычная, быстрая, громила, нетопырь, щитовик, двойняшка, чупачонок, шаман, король; анимация `idle` |
| `build_villager.py` | `villager.glb` — житель (покупает дерево), анимации `idle`, `walk`, `wave` |
| `build_castle.py` | `castle.glb`, `spawn_portal.glb` |
| `build_camp.py` | `camp_lumber.glb` — лагерь лесорубов (навес, поленница, колода с топором, знамя), один меш |
| `build_environment.py` | `tree_round`, `tree_pine`, `rock_a`, `rock_b`, `bush`, `flowers` |
| `build_terrain.py` | `level_01_terrain.glb` (земля, тропа, мелкий декор), `level_01_decor.glb` (деревья, кусты) |
| `tg_common.py` | палитра, примитивы, AO, анимации, экспорт, настройки импорта Godot |
| `build_all.py` | точка входа |

## Запуск

Linux / облако:

```bash
blender -b --factory-startup --python assets/blender/build_all.py              # все ассеты (~20 с)
blender -b --factory-startup --python assets/blender/build_all.py -- hero      # один набор
blender -b --factory-startup --python assets/blender/build_all.py -- hero --blend  # + .blend в assets/blender/out/
```

macOS (Blender из `/Applications`):

```bash
cd ~/путь/к/bimbleguard
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
  --python assets/blender/build_all.py
```

Имена наборов: `hero`, `tower`, `chupa`, `villager`, `castle`, `camp`, `environment`, `terrain`.
`--blend` сохраняет сцены для осмотра в `assets/blender/out/` (в `.gitignore`).

После сборки откройте проект в Godot: он переимпортирует изменённые `.glb`.

## Что делает пайплайн

1. Модель строится из примитивов, вращения профилей и деформаций; цвета — именованные
   «свотчи» из `PALETTE` в `tg_common.py`.
2. **AO** считается лучами по BVH всей модели (плюс вспомогательная земля) и
   записывается в цвет вершин (`COLOR_0`). Godot умножает на него альбедо.
3. Свотчи заменяются **одним материалом** `TG_Palette`: UV каждой грани указывает в
   центр её ячейки палитры (`assets/materials/tg_palette_albedo.png`,
   `tg_palette_orm.png`: G — roughness, B — metallic).
4. Анимации — ключи трансформаций частей, собранные в NLA-дорожки (`idle`, `attack`).
5. Экспорт GLB и запись `<model>.glb.import`: Godot подменяет материал модели на общий
   `assets/materials/tg_palette.tres` и не извлекает встроенные PNG.

## Совместимость и ограничения

- Реально проверено на **Blender 4.0.2** (Ubuntu). Для 4.1+ код переключается на
  `shade_smooth_by_angle`, для 4.2+ — на `export_vertex_color="ACTIVE"`; на этих
  версиях скрипты не запускались. Если что-то упадёт — пришлите трассировку.
- Сборка **не побайтово детерминирована**: при повторном запуске экспортёр glTF может
  записать вершины в другом порядке. Геометрия, цвета и счётчики совпадают; лишние
  изменения `.glb` в git можно откатить, если скрипт не менялся.
- Палитра расширяется добавлением строки в `PALETTE` (сетка 8×8, свободно 19 ячеек).

#!/usr/bin/env python3
"""Прототип расчёта к docs/CONTENT_V06.md: «чаща-щит» заставы (порядок величин, не баланс).

Модель: у заставы N деревьев чащи. Интенсивность спавна по заставе
  I(c) = max(FLOOR, 1 - SHIELD * c / N),  c = число срубленных деревьев.
Это множитель к числу врагов волны на этой стороне (в симуляции: целое число процентов).
Деревья отрастают через REGROW секунд (у обычного WoodTree regrow_time = 60 с; у чащи заставы
предлагается дольше). Герой рубит дерево за HERO_SEC секунд (подход + 4 удара).
Запуск: python3 tools/proto_outposts.py
"""

N = 24  # деревьев чащи на заставу
SHIELD = 0.60  # максимум, на сколько вырубка снижает поток
FLOOR = 0.40  # «вечный» минимум: застава не выключается полностью (вариант 1)
WOOD_PER_TREE = 12  # wood_per_hit = 3, hits = 4
HERO_SEC = 5.0  # подход + 4 удара, оценка
REGROW = {"обычное дерево": 60.0, "дерево чащи": 150.0}
WAVE_SEC = 30.0  # wave_duration в levels.json
BASE_ENEMIES = 12  # врагов волны на одной стороне, порядок величин


def floor_cuts() -> float:
    """Сколько деревьев надо срубить, чтобы поток дошёл до минимума."""
    return (1.0 - FLOOR) / SHIELD * N


def percent(cut: int) -> int:
    """Поток в целых процентах (так хранится в симуляции)."""
    return round(max(FLOOR, 1.0 - SHIELD * cut / N) * 100)


def main() -> None:
    print("Срублено -> поток заставы (%%), врагов на волну (из %d)" % BASE_ENEMIES)
    for c in (0, 4, 8, 12, 16, 20, 24):
        print("  %2d/%d  %3d%%  %4.1f" % (c, N, percent(c), BASE_ENEMIES * percent(c) / 100))
    cuts = floor_cuts()
    print(
        "\nГерой сводит поток к минимуму: %d деревьев x %.0f с = %.0f с (%.1f волны), дерева: %d"
        % (cuts, HERO_SEC, cuts * HERO_SEC, cuts * HERO_SEC / WAVE_SEC, cuts * WOOD_PER_TREE)
    )
    print("\nУдержание «выруби и забудь» на минимуме при отрастании:")
    for name, regrow in REGROW.items():
        per_min = cuts * 60.0 / regrow
        share = per_min * HERO_SEC / 60.0 * 100
        print(
            "  %-15s %3.0f с: %4.1f деревьев/мин = %2.0f с героя в минуту (%.0f%% времени), +%.0f дерева/мин"
            % (name, regrow, per_min, per_min * HERO_SEC, share, per_min * WOOD_PER_TREE)
        )
    print(
        "\nВывод: при отрастании 150 с удержание минимума стоит ~%d%% времени героя"
        " (одна сторона), выгода: волна на этой стороне на %d%% легче. Не «забудь», но и не обязаловка."
        % (round(cuts * 60 / 150 * HERO_SEC / 60 * 100), round((1 - FLOOR) * 100))
    )


if __name__ == "__main__":
    main()

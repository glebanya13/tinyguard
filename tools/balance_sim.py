#!/usr/bin/env python3
"""Rough balance check: plays every level of resources/levels.json with a
greedy player and prints lives left after each boss wave and at the end.

Model: enemies walk the level path (wave plan as in scripts/wave_plan.gd),
towers hit instantly (nearest enemy in range, splash and slow as in
tower/projectile code), gold from kills, wood at a steady chopping rate. The
hero guards the path near the castle with his sword (as an extra "tower"). The player builds on the slots that cover most of the
path, mixing archer / cannon / frost, and upgrades when every slot is taken.
It is an estimate: real players also fight with the hero and call waves early.

Usage: python3 tools/balance_sim.py [level_id ...]
"""
from __future__ import annotations

import json
import math
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DT = 0.05
WOOD_PER_SECOND = 0.5
HERO = {"damage_levels": [14.0], "range_levels": [1.4], "interval_levels": [0.5],
        "splash_levels": [0.0], "slow_levels": [1.0]}
HERO_AT = 0.85  # fraction of the path where the hero stands  # the hero chops a tree (12 wood) in ~2.5 s, plus walking
BOSS_GROWTH_EXPONENT = 0.75  # scripts/wave_plan.gd
INTERVAL_DECAY = 0.97


def tres(path: str) -> dict:
    out = {}
    for key, value in re.findall(r"^(\w+) = (.+)$", (ROOT / path).read_text(), re.M):
        nums = re.findall(r"-?\d+\.?\d*", value)
        if value.startswith("Array"):
            out[key] = [float(n) for n in nums]
        elif nums and not value.startswith(("ExtResource", '"')):
            out[key] = float(nums[0])
    return out


TOWERS = {k: tres(f"resources/towers/{k}.tres") for k in ("archer", "cannon", "frost")}
ENEMIES = {k: tres(f"resources/enemies/{k}.tres") for k in ("slime", "slime_fast", "slime_tank", "slime_king")}
BUILD_ORDER = ["archer", "archer", "cannon", "frost", "archer", "cannon", "archer", "frost", "cannon"]


def wave_spawns(w: dict, n: int) -> list:
    hp = w["hp_mult"] * w["hp_growth"] ** (n - 1)
    count = round(w["count_base"] + w["count_step"] * (n - 1))
    out = []
    for i in range(count):
        kind = "slime"
        if n >= w["tank_from"] and i % 4 == 3:
            kind = "slime_tank"
        elif n >= w["fast_from"] and i % 3 == 1:
            kind = "slime_fast"
        out.append((kind, hp))
    if n % w["boss_every"] == 0 or (w["boss_last"] and n == w["count"]):
        out += [("slime_king", hp ** BOSS_GROWTH_EXPONENT)] * (1 + n // 30)
    return out


class Path2D:
    def __init__(self, pts):
        self.pts = [tuple(p) for p in pts]
        self.cum = [0.0]
        for a, b in zip(self.pts, self.pts[1:]):
            self.cum.append(self.cum[-1] + math.dist(a, b))
        self.length = self.cum[-1]

    def at(self, d: float):
        for i in range(len(self.pts) - 1):
            if d <= self.cum[i + 1]:
                t = (d - self.cum[i]) / max(self.cum[i + 1] - self.cum[i], 1e-6)
                (ax, az), (bx, bz) = self.pts[i], self.pts[i + 1]
                return ax + (bx - ax) * t, az + (bz - az) * t
        return self.pts[-1]

    def coverage(self, x, z, r) -> float:
        return sum(0.25 for k in range(int(self.length / 0.25))
                   if math.dist(self.at(k * 0.25), (x, z)) <= r)


def play(lv: dict, verbose: bool = True) -> int:
    w = lv["waves"]
    path = Path2D(lv["path"])
    slots = sorted(lv["slots"], key=lambda s: -path.coverage(s[0], s[1], 3.2))
    gold, wood, lives = lv["start"]["gold"], lv["start"]["wood"], lv["start"]["lives"]
    towers = []  # dicts: kind, level, x, z, cd
    hx, hz = path.at(path.length * HERO_AT)
    hero = {"kind": "hero", "level": 0, "x": hx + 0.8, "z": hz, "cd": 0.0}
    t = 0.0
    report = []

    def shop():
        nonlocal gold, wood
        changed = True
        while changed:
            changed = False
            if len(towers) < len(slots):
                kind = BUILD_ORDER[len(towers) % len(BUILD_ORDER)]
                d = TOWERS[kind]
                if gold >= d["cost_gold"] and wood >= d["cost_wood"]:
                    gold -= d["cost_gold"]
                    wood -= d["cost_wood"]
                    x, z = slots[len(towers)]
                    towers.append({"kind": kind, "level": 0, "x": x, "z": z, "cd": 0.0})
                    changed = True
                continue
            for tw in sorted(towers, key=lambda tw: tw["level"]):
                d = TOWERS[tw["kind"]]
                if tw["level"] < 2:
                    g, wd = d["upgrade_gold"][tw["level"]], d["upgrade_wood"][tw["level"]]
                    if gold >= g and wood >= wd:
                        gold -= g
                        wood -= wd
                        tw["level"] += 1
                        changed = True
                        break

    def run(seconds, enemies, queue, interval):
        nonlocal gold, wood, lives, t
        spawn_cd = 0.0
        elapsed = 0.0
        while elapsed < seconds or (seconds < 0 and (enemies or queue)):
            elapsed += DT
            t += DT
            wood += WOOD_PER_SECOND * DT
            shop()
            spawn_cd -= DT
            if queue and spawn_cd <= 0.0:
                kind, mult = queue.pop(0)
                e = ENEMIES[kind]
                enemies.append({"kind": kind, "hp": e["health"] * mult, "d": 0.0, "slow": 1.0, "slow_t": 0.0})
                spawn_cd = interval
            for en in enemies:
                en["slow_t"] -= DT
                if en["slow_t"] <= 0:
                    en["slow"] = 1.0
                en["d"] += ENEMIES[en["kind"]]["speed"] * en["slow"] * DT
                en["pos"] = path.at(en["d"])
            for en in [en for en in enemies if en["d"] >= path.length]:
                lives -= int(ENEMIES[en["kind"]]["base_damage"])
                enemies.remove(en)
            for tw in towers + [hero]:
                tw["cd"] -= DT
                if tw["cd"] > 0:
                    continue
                d, lvl = (HERO if tw["kind"] == "hero" else TOWERS[tw["kind"]]), tw["level"]
                in_range = [en for en in enemies if math.dist(en["pos"], (tw["x"], tw["z"])) <= d["range_levels"][lvl]]
                if not in_range:
                    continue
                target = min(in_range, key=lambda en: math.dist(en["pos"], (tw["x"], tw["z"])))
                splash = d["splash_levels"][lvl]
                hit = [en for en in enemies if math.dist(en["pos"], target["pos"]) <= splash] if splash else [target]
                for en in hit:
                    en["hp"] -= d["damage_levels"][lvl]
                    if d["slow_levels"][lvl] < 1.0:
                        en["slow"] = min(en["slow"], d["slow_levels"][lvl])
                        en["slow_t"] = d.get("slow_duration", 1.6)
                tw["cd"] = d["interval_levels"][lvl]
            for en in [en for en in enemies if en["hp"] <= 0]:
                gold += int(ENEMIES[en["kind"]]["reward"])
                enemies.remove(en)
            if lives <= 0:
                return

    run(w["first_delay"], [], [], 1.0)
    for n in range(1, int(w["count"]) + 1):
        interval = max(w["interval_min"], w["interval"] * INTERVAL_DECAY ** (n - 1))
        run(-1, [], wave_spawns(w, n), interval)
        if lives <= 0:
            report.append(f"проигрыш на волне {n}")
            break
        if n % w["boss_every"] == 0 or n == w["count"]:
            levels = sum(tw["level"] + 1 for tw in towers)
            report.append(f"волна {n}: жизни {lives}, башен {len(towers)} (сумма уровней {levels})")
        run(w["between"], [], [], 1.0)
    if verbose:
        print(f"{lv['id']}. {lv['name']}: " + "; ".join(report))
    return max(lives, 0)


def main() -> None:
    levels = json.loads((ROOT / "resources" / "levels.json").read_text(encoding="utf-8"))["levels"]
    only = {int(a) for a in sys.argv[1:]}
    for lv in levels:
        if not only or lv["id"] in only:
            play(lv)


if __name__ == "__main__":
    main()

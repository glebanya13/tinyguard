#!/usr/bin/env python3
"""Rough balance check: plays every level of resources/levels.json with a
greedy player and prints lives left after each boss wave and at the end.

Model: enemies walk the level paths (wave plan as in scripts/wave_plan.gd: lane
patterns, scouts, bosses, elites; flyers cross on a straight line to the castle),
towers hit instantly (target by priority as in scripts/tower.gd, splash, slow
and the frost + lightning bonus as in tower/projectile code), gold from kills,
wood at a steady chopping rate. The hero guards the castle road (where the
paths have joined) with his sword (as an extra "tower"). The player builds in
a fixed tower order and upgrades when every slot is taken. Three ways to pick
slots are played: "balanced" (round-robin over the paths, the sensible one),
"greedy" (most path covered first) and "turtle" (everything next to the
castle: must not be better than balanced, else choosing does not matter).
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
DT = 0.1
# Perk "Меткие стрелки" etc. are not counted: a fresh player.
TOWER_BONUS = 1.0
WOOD_PER_SECOND = 1.5  # the hero chops 3 wood a swing between fights
HERO = {"damage_levels": [14.0], "range_levels": [1.4], "interval_levels": [0.5],
        "splash_levels": [0.0], "slow_levels": [1.0]}
HERO_FROM_CASTLE = 3.0  # metres before the castle gate (on path 0) where the hero stands
BOSS_GROWTH_EXPONENT = 0.75  # scripts/wave_plan.gd
INTERVAL_DECAY = 0.97


def tres(path: str) -> dict:
    out = {}
    for key, value in re.findall(r"^(\w+) = (.+)$", (ROOT / path).read_text(), re.M):
        nums = re.findall(r"-?\d+\.?\d*", value)
        if value in ("true", "false"):
            out[key] = value == "true"
        elif value.startswith('&"'):
            out[key] = value[2:-1]
        elif value.startswith("Array"):
            out[key] = [float(n) for n in nums]
        elif nums and not value.startswith(("ExtResource", '"')):
            out[key] = float(nums[0])
    return out


TOWERS = {k: tres(f"resources/towers/{k}.tres") for k in ("archer", "cannon", "frost", "lightning")}
ENEMIES = {k: tres(f"resources/enemies/{k}.tres")
           for k in ("slime", "slime_fast", "slime_tank", "slime_king", "slime_bat", "slime_shield",
                     "slime_splitter", "slime_mini", "slime_healer", "stone_golem")}
# scripts/wave_plan.gd MIX, same order: [level key, enemy, every Nth, offset]
MIX = [("golem_from", "stone_golem", 9, 8), ("tank_from", "slime_tank", 4, 3), ("shield_from", "slime_shield", 6, 5),
       ("healer_from", "slime_healer", 8, 4), ("splitter_from", "slime_splitter", 7, 6), ("bat_from", "slime_bat", 5, 2),
       ("fast_from", "slime_fast", 3, 1)]
BUILD_ORDER = ["archer", "archer", "cannon", "frost", "lightning", "archer", "cannon", "lightning", "frost",
               "archer", "cannon", "lightning"]
NEVER = 100000
STRATEGIES = ("balanced", "greedy", "turtle")


def deal(dealt: dict, kind: str, weights: list, wave: int) -> int:
    """scripts/wave_plan.gd _deal(): largest weight / (dealt + 1), search starts at `wave`."""
    counts = dealt.setdefault(kind, [0] * len(weights))
    best, best_score = -1, -1.0
    for step in range(len(weights)):
        k = (wave + step) % len(weights)
        score = weights[k] / (counts[k] + 1.0)
        if score > best_score:
            best, best_score = k, score
    counts[best] += 1
    return best


def wave_spawns(w: dict, n: int) -> list:
    """[(kind, hp, lane, extra)] in spawn order; extra = {"elite": (reward x, scale)} or {}."""
    hp = w["hp_mult"] * w["hp_growth"] ** (n - 1)
    count = round(w["count_base"] + w["count_step"] * (n - 1))
    lanes = w.get("lanes", {})
    patterns = lanes.get("patterns", [])
    weights = patterns[(n - 1) % len(patterns)] if patterns else []
    dealt: dict = {}
    out = []
    for i in range(count):
        kind = "slime"
        for key, enemy, every, offset in MIX:
            if n >= w.get(key, NEVER) and i % every == offset:
                kind = enemy
                break
        lane = None
        if weights:
            use = weights
            if kind == "slime_fast":
                use = [1 if k in lanes["scout_paths"] else 0 for k in range(len(weights))]
            lane = deal(dealt, kind, use, n)
        out.append((kind, hp, lane, {}))
    elite = w.get("elite")
    if elite and n >= elite["from"] and (n - elite["from"]) % elite["every"] == 0:
        elites = 1 + int((n - elite["from"]) // elite["step"])
        for e in range(elites):
            lane = deal(dealt, elite["kind"], weights, n + e) if weights else None
            idx = round(len(out) * (e + 1.0) / (elites + 1.0))
            out.insert(idx, (elite["kind"], hp * elite["hp"], lane, {"elite": elite["reward"]}))
    if n % w["boss_every"] == 0 or (w["boss_last"] and n == w["count"]):
        for i in range(1 + n // 30):
            lane = lanes["boss_paths"][(n + i) % len(lanes["boss_paths"])] if weights else None
            out.append(("slime_king", hp ** BOSS_GROWTH_EXPONENT, lane, {}))
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


def routes(lv: dict) -> list:
    """Full enemy routes as in LevelCatalog.routes(): a path that ends on an
    earlier one continues along it to the castle."""
    out = []
    for pts in lv["paths"]:
        route = [tuple(p) for p in pts]
        if out:
            end = route[-1]
            for prev in out:
                hit = [i for i, (a, b) in enumerate(zip(prev, prev[1:]))
                       if min(a[0], b[0]) - 0.01 <= end[0] <= max(a[0], b[0]) + 0.01
                       and min(a[1], b[1]) - 0.01 <= end[1] <= max(a[1], b[1]) + 0.01]
                if hit:
                    route += prev[hit[0] + 1:]
                    break
        out.append(route)
    return out


def play(lv: dict, verbose: bool = True) -> int:
    w = lv["waves"]
    paths = [Path2D(r) for r in routes(lv)]
    drawn = [Path2D(pts) for pts in lv["paths"]]  # every metre of road once
    slots = sorted(lv["slots"], key=lambda s: -sum(p.coverage(s[0], s[1], 3.2) for p in drawn))
    gold, wood, lives = lv["start"]["gold"], lv["start"]["wood"], lv["start"]["lives"]
    towers = []  # dicts: kind, level, x, z, cd
    hx, hz = paths[0].at(paths[0].length - HERO_FROM_CASTLE)
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

    spawned = {}  # kind -> enemies of that kind so far: picks the next path

    def add_enemy(enemies, kind, mult, d=0.0, route=None):
        if route is None:
            route = spawned.get(kind, 0) % len(paths)
            spawned[kind] = spawned.get(kind, 0) + 1
        e = ENEMIES[kind]
        enemies.append({"kind": kind, "hp": e["health"] * mult, "max": e["health"] * mult, "mult": mult, "d": d,
                        "slow": 1.0, "slow_t": 0.0, "heal_t": 0.0, "pos": paths[route].at(d), "route": route})

    # Waves on a fixed clock (scripts/wave_manager.gd): one every wave_duration s,
    # enemies spread over spawn_window s; waves overlap.
    enemies, spawners = [], []
    leaks = {}  # kind -> lives taken
    duration, window = w.get("wave_duration", 30), w.get("spawn_window", 24)
    next_wave_at, wave = w["first_delay"], 0
    while True:
        t += DT
        wood += WOOD_PER_SECOND * DT
        shop()
        if wave < w["count"] and t >= next_wave_at:
            wave += 1
            queue = wave_spawns(w, wave)
            spawners.append({"queue": queue, "interval": window / max(len(queue), 1), "left": 0.0})
            next_wave_at = t + duration
            if wave % w["boss_every"] == 0 or wave == w["count"]:
                levels = sum(tw["level"] + 1 for tw in towers)
                report.append(f"волна {wave}: жизни {lives}, башен {len(towers)} (ур. {levels}), врагов {len(enemies)}")
        for sp in list(spawners):
            sp["left"] -= DT
            if sp["left"] <= 0:
                add_enemy(enemies, *sp["queue"].pop(0))
                sp["left"] += sp["interval"]
                if not sp["queue"]:
                    spawners.remove(sp)
        for en in enemies:
            e = ENEMIES[en["kind"]]
            en["slow_t"] -= DT
            if en["slow_t"] <= 0:
                en["slow"] = 1.0
            en["d"] += e["speed"] * en["slow"] * DT
            en["pos"] = paths[en["route"]].at(en["d"])
            if e.get("heal_fraction", 0):
                en["heal_t"] -= DT
                if en["heal_t"] <= 0:
                    en["heal_t"] = e.get("heal_interval", 1.0)
                    for o in enemies:
                        if o is not en and math.dist(o["pos"], en["pos"]) <= e.get("heal_radius", 1.8):
                            o["hp"] = min(o["max"], o["hp"] + o["max"] * e["heal_fraction"])
        for en in [en for en in enemies if en["d"] >= paths[en["route"]].length]:
            lives -= int(ENEMIES[en["kind"]]["base_damage"])
            leaks[en["kind"]] = leaks.get(en["kind"], 0) + int(ENEMIES[en["kind"]]["base_damage"])
            enemies.remove(en)
        if lives <= 0:
            report.append(f"проигрыш на волне {wave}")
            break
        for tw in towers + [hero]:
            tw["cd"] -= DT
            if tw["cd"] > 0:
                continue
            d, lvl = (HERO if tw["kind"] == "hero" else TOWERS[tw["kind"]]), tw["level"]
            air = d.get("hits_air", True)
            rng = d["range_levels"][lvl]
            in_range = [en for en in enemies if math.dist(en["pos"], (tw["x"], tw["z"])) <= rng
                        and (air or not ENEMIES[en["kind"]].get("flying", False))]
            if not in_range:
                tw["cd"] = 0.15
                continue
            target = min(in_range, key=lambda en: math.dist(en["pos"], (tw["x"], tw["z"])))
            splash = d["splash_levels"][lvl]
            chain = int(d.get("chain_levels", [0, 0, 0])[lvl])
            if splash:
                hit = [en for en in enemies if math.dist(en["pos"], target["pos"]) <= splash
                       and not ENEMIES[en["kind"]].get("flying", False)]
            elif chain:
                hit = [target]
                while len(hit) <= chain:
                    rest = [en for en in enemies if en not in hit
                            and math.dist(en["pos"], hit[-1]["pos"]) <= d.get("chain_range", 2.2)]
                    if not rest:
                        break
                    hit.append(min(rest, key=lambda en: math.dist(en["pos"], hit[-1]["pos"])))
            else:
                hit = [target]
            for k, en in enumerate(hit):
                e = ENEMIES[en["kind"]]
                dmg = d["damage_levels"][lvl] * (0.8 ** k if chain else 1.0) * (1.0 if tw["kind"] == "hero" else TOWER_BONUS)
                if d.get("damage_kind") == "arrow":
                    dmg *= e.get("arrow_damage_mult", 1.0)
                if e.get("armor", 0):
                    dmg = max(dmg - e["armor"], 1.0)
                en["hp"] -= dmg
                if d["slow_levels"][lvl] < 1.0:
                    en["slow"] = min(en["slow"], d["slow_levels"][lvl])
                    en["slow_t"] = d.get("slow_duration", 1.6)
            tw["cd"] = d["interval_levels"][lvl]
        for en in [en for en in enemies if en["hp"] <= 0]:
            e = ENEMIES[en["kind"]]
            gold += int(e["reward"])
            enemies.remove(en)
            if e.get("split_count"):
                for k in range(int(e["split_count"])):
                    add_enemy(enemies, "slime_mini", en["mult"], max(en["d"] - 0.35 * k, 0.0), en["route"])
        if wave >= w["count"] and not spawners and not enemies:
            break
    if verbose:
        lost = ", ".join(f"{k} {v}" for k, v in sorted(leaks.items(), key=lambda kv: -kv[1]))
        print(f"{lv['id']}. {lv['name']} ({len(paths)} пути): " + "; ".join(report)
              + f" | итог: жизни {max(lives, 0)}/{lv['start']['lives']}" + (f" | прорвались: {lost}" if lost else ""))
    return max(lives, 0)


def main() -> None:
    levels = json.loads((ROOT / "resources" / "levels.json").read_text(encoding="utf-8"))["levels"]
    only = {int(a) for a in sys.argv[1:]}
    for lv in levels:
        if not only or lv["id"] in only:
            play(lv)


if __name__ == "__main__":
    main()

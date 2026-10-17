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
"greedy" (most path covered first) and "turtle" (only the 40% of slots
nearest to the castle, everything else into upgrades: must not beat balanced). A fourth,
"skilled" player plays like balanced and also fights with the hero (whirlwind, strongest target,
forge, wall repair): he must do better than balanced.
It is an estimate: real players also call waves early; the simulation is cliff-edged (a tiny change
of hp_growth can turn a win on the last wave into a defeat), so tune one number at a time.

Difficulty (--diff 0|1|2: Normal / Hard / Nightmare, multipliers from "difficulty" in
resources/balance.json) and the Record Run (--record: free mode, every wave harder, rules from
"record" in the same file; the result is the wave the castle falls on) are played as well.

Usage: python3 tools/balance_sim.py [--diff N] [--record] [--table] [--sanity] [--no-wood-economy] [--no-castle] [level_id ...]
  --no-wood-economy  the campaign without buying wood and lumberjacks (the numbers from before
                     docs/ECONOMY_V2.md stage 1)
  --no-castle  the players do not upgrade the castle (the numbers from before the feature)
  --table  one line per level: result of every strategy (lives left / wave lost on)
  --sanity the "afk" (no tower at all) and "one" (a single tower) players: both must lose
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
# Sword per forge level (scripts/hero.gd: sword_damage_levels, sword_upgrade_*); only the "skilled" player forges.
SWORD_DAMAGE = [14.0, 22.0, 32.0, 45.0]
SWORD_GOLD = [40, 90, 160]
SWORD_WOOD = [30, 60, 100]
HERO = {"damage_levels": SWORD_DAMAGE, "range_levels": [1.4] * 4, "interval_levels": [0.5] * 4,
        "splash_levels": [0.0] * 4, "slow_levels": [1.0] * 4}
WHIRL_RADIUS, WHIRL_MULT, WHIRL_COOLDOWN = 2.2, 1.6, 12.0  # scripts/hero.gd
REPAIR_LIVES, REPAIR_WOOD = 2, 25  # scripts/game_state.gd
# The villagers' wood economy (resources/villager_trade.tres, docs/ECONOMY_V2.md stage 1): on in
# the campaign only, off in the Record Run and the daily challenge. `--no-wood-economy` plays
# the campaign without it (the numbers from before the feature).
# A human is not a machine: the skilled hero spends this share of the time actually fighting.
SKILLED_HERO_UPTIME = 0.85
BIG_HP = 150.0  # the skilled player switches towers to "strongest" when something this tough is in range
HERO_SPEED = 3.2  # m/s, scripts/hero.gd
HERO_FROM_CASTLE = 3.0  # metres before the castle gate where the hero stands on the approach in use
GATE_REACH = 1.5  # a path ending this close (taxicab) to the castle centre ends at a castle gate
_BALANCE = json.loads((ROOT / "resources/balance.json").read_text())  # same file as the game
_RULES = _BALANCE["waves"]
DIFFS = _BALANCE["difficulty"]
REC = _BALANCE["record"]
RECORD_WAVE_LIMIT = 70  # the simulation stops here ("nobody gets further")
BOSS_GROWTH_EXPONENT = _RULES["boss_growth_exponent"]
BOSS_PER_WAVES = _RULES["boss_per_waves"]
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


_TRADE = tres("resources/villager_trade.tres")
LOT_WOOD = int(_TRADE["wood_per_lot"])
BUY_START, BUY_GROWTH, BUY_MAX_LOTS = _TRADE["buy_start_gold"], _TRADE["buy_growth"], int(_TRADE["buy_max_lots"])
HIRE_GOLD, HIRE_MAX = int(_TRADE["hire_gold"]), int(_TRADE["hire_max"])
HIRE_WOOD_PER_SECOND = _TRADE["hire_wood_per_minute"] / 60.0
GOLD_RESERVE = 70  # gold a player keeps (about two towers) before he spends any on wood or a hire
WOOD_ECONOMY = "--no-wood-economy" not in sys.argv
# Castle upgrades (resources/castle_upgrades.json, scripts/castle_upgrades.gd): the "balanced" and "skilled"
# players buy them, in every mode. `--no-castle` plays without (the numbers from before the feature).
CASTLE = json.loads((ROOT / "resources/castle_upgrades.json").read_text())["levels"]
CASTLE_ON = "--no-castle" not in sys.argv


TOWERS = {k: tres(f"resources/towers/{k}.tres") for k in ("archer", "cannon", "frost", "lightning")}
ENEMIES = {k: tres(f"resources/enemies/{k}.tres")
           for k in ("slime", "slime_fast", "slime_tank", "slime_king", "slime_bat", "slime_shield",
                     "slime_splitter", "slime_mini", "slime_healer", "stone_golem")}
# [level key, enemy, every Nth, offset] from resources/balance.json
MIX = [tuple(row) for row in _RULES["mix"]]
BUILD_ORDER = ["archer", "archer", "cannon", "frost", "lightning", "archer", "cannon", "lightning", "frost",
               "archer", "cannon", "lightning"]
NEVER = 100000
# The balanced player keeps this many anti-air towers within this radius of the castle.
AIR_GUARD_TOWERS = 3
AIR_GUARD_RADIUS = 9.0
STRATEGIES = ("balanced", "greedy", "turtle", "skilled")
# Strategies that read the banner (lane plan), keep the castle ring for flyers and place towers by lane.
SMART = ("balanced", "skilled")
# Sanity checks (--sanity): nobody may win by doing nothing or with a single tower.
SANITY = {"afk": 0, "one": 1}


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


def buy_price(bought: int) -> int:
    return max(1, rnd(BUY_START * BUY_GROWTH ** bought))


def rnd(x: float) -> int:
    """roundi() of GDScript: halves go away from zero."""
    return int(math.floor(x + 0.5))


def surprise_of(n: int):
    for s in REC["surprises"]:
        if n >= s["from"] and (n - s["from"]) % s["every"] == 0:
            return s
    return None


def boss_wave(w: dict, n: int, record: bool) -> bool:
    if record:
        rows = [r for r in REC["boss"]["schedule"] if n >= r[0]]
        return bool(rows) and (n - rows[-1][0]) % rows[-1][1] == 0
    return n % w["boss_every"] == 0 or (w["boss_last"] and n == w["count"])


def hp_factor(w: dict, n: int, record: bool, hp_scale: float) -> float:
    if record:
        return hp_scale * REC["hp_start"] * min(REC["hp_growth"] ** (n - 1), REC["hp_cap"])
    return hp_scale * w["hp_mult"] * w["hp_growth"] ** (n - 1)


def wave_spawns(w: dict, n: int, record: bool = False, hp_scale: float = 1.0, count_scale: float = 1.0) -> list:
    """[(kind, hp, lane, extra)] in spawn order; extra = {"elite": (reward x, scale)} or {}."""
    hp = hp_factor(w, n, record, hp_scale)
    surprise = surprise_of(n) if record else None
    base = w["count_base"] + w["count_step"] * (n - 1)
    if record:
        base = w["count_base"] * REC["count_growth"] ** (n - 1)
        if surprise:
            base *= surprise["count"]
        base = min(base, REC["count_cap"])
    count = max(rnd(base * count_scale), 1)
    lanes = w.get("lanes", {})
    patterns = lanes.get("patterns", [])
    weights = patterns[(n - 1) % len(patterns)] if patterns else []
    if surprise and weights:
        weights = [1] * len(weights)
    dealt: dict = {}
    out = []
    late = record and n >= REC["late_from"]
    for i in range(count):
        kind = "slime"
        ehp = hp
        if surprise:
            kind, ehp = surprise["kind"], hp * surprise["hp"]
        elif record:
            for first, enemy, every, offset, every_late in REC["mix"]:
                e = every_late if late else every
                if n >= first and i % e == offset % e:
                    kind = enemy
                    break
        else:
            for key, enemy, every, offset in MIX:
                if n >= w.get(key, NEVER) and i % every == offset:
                    kind = enemy
                    break
        lane = None
        if weights:
            use = weights
            if kind == "slime_fast" and not surprise:
                use = [1 if k in lanes["scout_paths"] else 0 for k in range(len(weights))]
            lane = deal(dealt, kind, use, n)
        out.append((kind, ehp, lane, {}))
    elite = REC["elite"] if record else w.get("elite")
    if elite and n >= elite["from"] and (n - elite["from"]) % elite["every"] == 0:
        elites = 1 + int((n - elite["from"]) // elite["step"])
        for e in range(elites):
            lane = deal(dealt, elite["kind"], weights, n + e) if weights else None
            idx = rnd(len(out) * (e + 1.0) / (elites + 1.0))
            out.insert(idx, (elite["kind"], hp * elite["hp"], lane, {"elite": elite["reward"]}))
    if boss_wave(w, n, record):
        if record:
            count_b = 1 + n // REC["boss"]["per_waves"]
            bhp = hp ** REC["boss"]["hp_exponent"] * REC["boss"]["hp_mult"]
        else:
            count_b = 1 + n // BOSS_PER_WAVES
            bhp = hp ** BOSS_GROWTH_EXPONENT * w.get("boss_hp_mult", 1.0)
        for i in range(count_b):
            lane = lanes["boss_paths"][(n + i) % len(lanes["boss_paths"])] if weights else None
            out.append(("slime_king", bhp, lane, {}))
    return out


def window_for(w: dict, n: int, record: bool) -> float:
    window, duration = w.get("spawn_window", 24), w.get("wave_duration", 30)
    if not record:
        return window
    r = REC["window_ramp"]
    t = min(max((n - r["from"]) / (r["to"] - r["from"]), 0.0), 1.0)
    return window + (duration - window) * t


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
    """Full enemy routes as in LevelCatalog.routes(): a path that does not end at a castle
    gate ends on an earlier one and continues along it to the castle."""
    out = []
    cx, cz = lv["castle"]
    for pts in lv["paths"]:
        route = [tuple(p) for p in pts]
        if abs(route[-1][0] - cx) + abs(route[-1][1] - cz) > GATE_REACH:
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


def order_slots(lv: dict, drawn: list, strategy: str) -> list:
    cover = lambda s, p: p.coverage(s[0], s[1], 3.2)
    if strategy == "turtle":
        return sorted(lv["slots"], key=lambda s: math.dist(s, lv["castle"]))
    if strategy == "greedy":
        return sorted(lv["slots"], key=lambda s: -sum(cover(s, p) for p in drawn))
    # balanced / skilled: the best slot of every path in turn (a slot counts for the path it covers most)
    rest = list(lv["slots"])
    out = []
    while rest:
        for p in drawn:
            if rest:
                best = max(rest, key=lambda s: cover(s, p))
                rest.remove(best)
                out.append(best)
    return out


def play(lv: dict, verbose: bool = True, strategy: str = "balanced", diff: int = 0, record: bool = False) -> int:
    """Lives left after the campaign level; in the record run (`record`) the wave the castle fell on."""
    w = lv["waves"]
    skilled = strategy == "skilled"
    d = DIFFS[diff]
    hp_scale, count_scale = d["hp"], d["count"]
    reward_mult = d["reward"] * (REC["reward_mult"] if record else 1.0) * w.get("reward_mult", 1.0)
    paths = [Path2D(r) for r in routes(lv)]
    drawn = [Path2D(pts) for pts in lv["paths"]]  # every metre of road once
    # flyers: straight line from the portal to the gate their route ends at
    air_routes = [Path2D([p.pts[0], p.pts[-1]]) for p in paths]
    slots = order_slots(lv, drawn, strategy)
    gold, wood, lives = lv["start"]["gold"], lv["start"]["wood"], max(rnd(lv["start"]["lives"] * d["lives"]), 1)
    lives_start = lives
    lives_cap = lives  # repair ceiling: grows with castle upgrades
    castle = 0  # castle upgrades bought
    economy = WOOD_ECONOMY and not record
    hired = bought = 0  # lumberjacks hired / lots of wood bought
    towers = []  # dicts: kind, level, x, z, cd
    hx, hz = lv["hero"]
    hero = {"kind": "hero", "level": 0, "x": hx, "z": hz, "cd": 0.0, "whirl": 0.0}

    hero_goal = [hx, hz]

    def steer_hero(enemies: list) -> None:
        """The player keeps the hero on the approach of the enemy closest to the castle (walking
        round the castle takes time: HERO_SPEED, 30% longer than the straight line)."""
        walkers = [en for en in enemies if not ENEMIES[en["kind"]].get("flying", False)]
        if walkers:
            # the skilled hero goes where it hurts: a heavy hitter counts as being closer
            bite = (lambda en: 3.0 * (ENEMIES[en["kind"]]["base_damage"] - 1)) if skilled else (lambda en: 0.0)
            en = min(walkers, key=lambda en: en["route"].length - en["d"] - bite(en))
            x, z = en["route"].at(en["route"].length - HERO_FROM_CASTLE)
            hero_goal[0], hero_goal[1] = x + 0.8, z
        gx, gz = hero_goal
        dist = math.dist((hero["x"], hero["z"]), (gx, gz))
        step = HERO_SPEED * DT / (1.15 if skilled else 1.3)
        if dist <= step:
            hero["x"], hero["z"] = gx, gz
        elif dist > 0:
            hero["x"] += (gx - hero["x"]) / dist * step
            hero["z"] += (gz - hero["z"]) / dist * step
    t = 0.0
    report = []

    lanes_cfg = w.get("lanes", {}).get("patterns", [])
    free_slots = list(slots)
    leaked_on = {}  # path -> enemies that got through on it
    # "turtle" never builds beyond the 40% of slots nearest to the castle: the rest goes into upgrades.
    slot_cap = SANITY.get(strategy, math.ceil(0.4 * len(slots)) if strategy == "turtle" else len(slots))
    cover_table = {tuple(sl): [p.coverage(sl[0], sl[1], 3.2) for p in drawn] for sl in slots}

    def air_guard() -> bool:
        """Flyers cross the map in a straight line: balanced keeps archers near the castle."""
        if strategy not in SMART or wave + 2 < (REC["mix"][5][0] if record else w.get("bat_from", NEVER)):
            return False
        near = [tw for tw in towers if math.dist((tw["x"], tw["z"]), lv["castle"]) < AIR_GUARD_RADIUS
                and TOWERS[tw["kind"]].get("hits_air", True)]
        return len(near) < AIR_GUARD_TOWERS

    def pick_slot():
        """The player reads the banner: the next tower goes where the coming waves walk."""
        if strategy not in SMART or not lanes_cfg:
            return free_slots[0]
        if air_guard():
            return min(free_slots, key=lambda sl: math.dist(sl, lv["castle"]))
        reserved = sorted(free_slots, key=lambda sl: math.dist(sl, lv["castle"]))[:AIR_GUARD_TOWERS]
        if ("bat_from" in w or record) and len(free_slots) > AIR_GUARD_TOWERS:
            pool = [sl for sl in free_slots if sl not in reserved]  # kept for the flyers
        else:
            pool = free_slots
        want = [0.0] * len(drawn)
        for n in (wave, wave + 1):
            pat = lanes_cfg[max(n - 1, 0) % len(lanes_cfg)]
            want = [a + b / max(sum(pat), 1) for a, b in zip(want, pat)]
        # ... and where enemies have already got through
        want = [a + 0.5 * leaked_on.get(k, 0) for k, a in enumerate(want)]
        return max(pool, key=lambda sl: sum(wl * c for wl, c in zip(want, cover_table[tuple(sl)])))

    def top_up(need_gold: int, need_wood: int) -> bool:
        """An item is short of wood. A sensible player spends only the gold left over after the
        item and a reserve: first a lumberjack (the cheaper wood in the long run), then lots of
        wood. True: the wood is there now."""
        nonlocal gold, wood, bought, hired
        if not economy:
            return False
        if hired < HIRE_MAX and gold - need_gold >= HIRE_GOLD + GOLD_RESERVE:
            gold -= HIRE_GOLD
            hired += 1
        lots = math.ceil((need_wood - wood) / LOT_WOOD)
        lots = min(lots, BUY_MAX_LOTS - bought)
        cost = sum(buy_price(bought + i) for i in range(lots))
        if lots <= 0 or gold - need_gold < cost + GOLD_RESERVE:
            return False
        gold -= cost
        wood += lots * LOT_WOOD
        bought += lots
        return wood >= need_wood

    def castle_due() -> bool:
        """A sensible player strengthens the castle once the field is built and the towers are one
        upgrade ahead of it (castle 1-2: towers level 2, castle 3-4: towers level 3)."""
        if not CASTLE_ON or strategy not in SMART or castle >= len(CASTLE) or not towers:
            return False
        if len(towers) < slot_cap or min(tw["level"] for tw in towers) < min(castle // 2 + 1, 2):
            return False
        return gold >= CASTLE[castle]["gold"] and wood >= CASTLE[castle]["wood"]

    def shop():
        nonlocal gold, wood, lives, lives_cap, castle
        changed = True
        while changed:
            changed = False
            if castle_due():
                gold -= CASTLE[castle]["gold"]
                wood -= CASTLE[castle]["wood"]
                lives += CASTLE[castle]["lives"]
                lives_cap += CASTLE[castle]["lives"]
                castle += 1
                changed = True
                continue
            if skilled:
                # wall repair at the forge when lives are lost and there is wood to spare
                if lives_cap - lives >= REPAIR_LIVES and wood >= REPAIR_WOOD + 30 and lives > 0:
                    wood -= REPAIR_WOOD
                    lives = min(lives + REPAIR_LIVES, lives_cap)
                    changed = True
                    continue
                lvl = hero["level"]
                if lvl < 3 and len(towers) >= len(slots) and min(tw["level"] for tw in towers) >= min(lvl + 1, 2):
                    if gold >= SWORD_GOLD[lvl] and wood >= SWORD_WOOD[lvl]:
                        gold -= SWORD_GOLD[lvl]
                        wood -= SWORD_WOOD[lvl]
                        hero["level"] += 1
                        changed = True
                        continue
            if len(towers) < slot_cap:
                kind = BUILD_ORDER[len(towers) % len(BUILD_ORDER)]
                if air_guard():
                    kind = "archer"
                d = TOWERS[kind]
                if gold >= d["cost_gold"] and (wood >= d["cost_wood"] or top_up(d["cost_gold"], d["cost_wood"])):
                    gold -= d["cost_gold"]
                    wood -= d["cost_wood"]
                    x, z = pick_slot()
                    free_slots.remove([x, z] if [x, z] in free_slots else (x, z))
                    towers.append({"kind": kind, "level": 0, "x": x, "z": z, "cd": 0.0})
                    changed = True
                continue
            for tw in sorted(towers, key=lambda tw: tw["level"]):
                d = TOWERS[tw["kind"]]
                if tw["level"] < 2:
                    g, wd = d["upgrade_gold"][tw["level"]], d["upgrade_wood"][tw["level"]]
                    if gold >= g and (wood >= wd or top_up(g, wd)):
                        gold -= g
                        wood -= wd
                        tw["level"] += 1
                        changed = True
                        break

    spawned = {}  # kind -> enemies of that kind so far: picks the next path

    def add_enemy(enemies, kind, mult, lane=None, extra=None, d=0.0, route=None):
        e = ENEMIES[kind]
        if route is None:
            if lane is None:
                lane = spawned.get(kind, 0) % len(paths)
                spawned[kind] = spawned.get(kind, 0) + 1
            route = air_routes[lane] if e.get("flying") else paths[lane]
            lane_id = lane
        else:
            lane_id = None
        rmult = (extra or {}).get("elite", 1.0)
        enemies.append({"kind": kind, "hp": e["health"] * mult, "max": e["health"] * mult, "mult": mult, "d": d,
                        "slow": 1.0, "slow_t": 0.0, "heal_t": 0.0, "route": route, "rmult": rmult, "lane": lane_id,
                        "pos": route.at(d)})

    # Waves on a fixed clock (scripts/wave_manager.gd): one every wave_duration s,
    # enemies spread over spawn_window s; waves overlap.
    enemies, spawners = [], []
    leaks = {}  # kind -> lives taken
    duration, window = w.get("wave_duration", 30), w.get("spawn_window", 24)
    next_wave_at, wave = w["first_delay"], 0
    while True:
        t += DT
        wood += (WOOD_PER_SECOND + hired * HIRE_WOOD_PER_SECOND) * DT
        shop()
        steer_hero(enemies)
        if (record or wave < w["count"]) and t >= next_wave_at:
            wave += 1
            queue = wave_spawns(w, wave, record, hp_scale, count_scale)
            spawners.append({"queue": queue, "interval": window_for(w, wave, record) / max(len(queue), 1), "left": 0.0})
            next_wave_at = t + duration
            if not record and (wave % w["boss_every"] == 0 or wave == w["count"]):
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
            en["pos"] = en["route"].at(en["d"])
            if e.get("heal_fraction", 0):
                en["heal_t"] -= DT
                if en["heal_t"] <= 0:
                    en["heal_t"] = e.get("heal_interval", 1.0)
                    for o in enemies:
                        if o is not en and math.dist(o["pos"], en["pos"]) <= e.get("heal_radius", 1.8):
                            o["hp"] = min(o["max"], o["hp"] + o["max"] * e["heal_fraction"])
        for en in [en for en in enemies if en["d"] >= en["route"].length]:
            hit = max(1, int(ENEMIES[en["kind"]]["base_damage"]) - (CASTLE[castle - 1]["armor"] if castle else 0))
            lives -= hit
            if en["lane"] is not None:
                leaked_on[en["lane"]] = leaked_on.get(en["lane"], 0) + 1
            leaks[en["kind"]] = leaks.get(en["kind"], 0) + hit
            enemies.remove(en)
        if lives <= 0:
            report.append(f"проигрыш на волне {wave}")
            break
        if record and wave > RECORD_WAVE_LIMIT:
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
            prio = 3 if tw["kind"] == "hero" else int(d.get("default_priority", 0))
            if skilled and tw["kind"] == "hero" and any(en["max"] >= BIG_HP for en in in_range):
                prio = 2  # the skilled hero swings at the toughest one in reach
            goal = lambda en: en["route"].length - en["d"]
            key = {0: goal, 1: lambda en: -goal(en), 2: lambda en: -en["hp"],
                   3: lambda en: math.dist(en["pos"], (tw["x"], tw["z"]))}[prio]
            target = min(in_range, key=key)
            splash = d["splash_levels"][lvl]
            chain = int(d.get("chain_levels", [0, 0, 0, 0])[lvl])
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
                if chain and en["slow"] < 1.0:
                    dmg *= d.get("chilled_bonus", 1.0)
                if d.get("damage_kind") == "arrow":
                    dmg *= e.get("arrow_damage_mult", 1.0)
                if e.get("armor", 0):
                    dmg = max(dmg - e["armor"], 1.0)
                en["hp"] -= dmg
                if d["slow_levels"][lvl] < 1.0:
                    en["slow"] = min(en["slow"], d["slow_levels"][lvl])
                    en["slow_t"] = d.get("slow_duration", 1.6)
            tw["cd"] = d["interval_levels"][lvl] / (SKILLED_HERO_UPTIME if skilled and tw["kind"] == "hero" else 1.0)
        if skilled:
            hero["whirl"] -= DT
            if hero["whirl"] <= 0:
                around = [en for en in enemies if math.dist(en["pos"], (hero["x"], hero["z"])) <= WHIRL_RADIUS]
                if len(around) >= 3 or any(en["max"] >= BIG_HP for en in around):
                    dmg = HERO["damage_levels"][hero["level"]] * WHIRL_MULT
                    for en in around:
                        e = ENEMIES[en["kind"]]
                        en["hp"] -= max(dmg - e.get("armor", 0), 1.0)
                    hero["whirl"] = WHIRL_COOLDOWN / SKILLED_HERO_UPTIME
                else:
                    hero["whirl"] = 0.2
        for en in [en for en in enemies if en["hp"] <= 0]:
            e = ENEMIES[en["kind"]]
            gold += rnd(rnd(e["reward"] * en["rmult"]) * reward_mult)  # roundi() twice, as in wave_manager.gd
            enemies.remove(en)
            if e.get("split_count"):
                for k in range(int(e["split_count"])):
                    add_enemy(enemies, "slime_mini", en["mult"], None, None, max(en["d"] - 0.35 * k, 0.0), en["route"])
        if not record and wave >= w["count"] and not spawners and not enemies:
            break
    play.last_wave = wave  # the wave the battle ended on (for tuning scripts)
    if record:
        reached = wave if lives <= 0 else RECORD_WAVE_LIMIT
        if verbose:
            print(f"{lv['id']}. [{strategy}] игра на рекорд: волна {reached}, башен {len(towers)}")
        return reached
    if verbose:
        lost = ", ".join(f"{k} {v}" for k, v in sorted(leaks.items(), key=lambda kv: -kv[1]))
        print(f"{lv['id']}. {lv['name']} ({len(paths)} пути): " + "; ".join(report)
              + f" | итог: жизни {max(lives, 0)}/{lives_start}" + (f", замок {castle}/{len(CASTLE)}" if castle else "") + (f" | прорвались: {lost}" if lost else ""))
    return max(lives, 0)


def main() -> None:
    levels = json.loads((ROOT / "resources" / "levels.json").read_text(encoding="utf-8"))["levels"]
    args = sys.argv[1:]
    diff = int(args[args.index("--diff") + 1]) if "--diff" in args else 0
    record = "--record" in args
    table = "--table" in args or "--sanity" in args
    strategies = tuple(SANITY) if "--sanity" in args else STRATEGIES
    only = {int(a) for a in args if a.isdigit() and args[args.index(a) - 1] != "--diff"}
    for lv in levels:
        if only and lv["id"] not in only:
            continue
        results = {}
        for strategy in strategies:
            if not table:
                print(f"[{strategy}]", end=" ")
            results[strategy] = play(lv, not table, strategy, diff, record)
        start = max(rnd(lv["start"]["lives"] * DIFFS[diff]["lives"]), 1)
        if table:
            if record:
                print(f"{lv['id']}: " + "  ".join(f"{k} волна {v}" for k, v in results.items()))
            else:
                print(f"{lv['id']}: " + "  ".join(
                    f"{k} {v}/{start}" + (" ПРОИГРЫШ" if v <= 0 else "") for k, v in results.items()))
        elif not record and "skilled" in results and results["skilled"] + max(1, start // 10) < results["balanced"]:
            print(f"   !! уровень {lv['id']}: «умелый» бот хуже обычного")
        elif not record and "turtle" in results and results["turtle"] > results["balanced"] + max(2, start // 5):
            print(f"   !! уровень {lv['id']}: «черепаха» у замка лучше расстановки по дорогам")


if __name__ == "__main__":
    main()

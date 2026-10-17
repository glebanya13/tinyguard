#!/usr/bin/env python3
"""Prototype of the wood economy v2 (docs/ECONOMY_V2.md). NOT the game balance and not
connected to the game: it only picks orders of magnitude for peasants, sawmills, houses and
the wood shop of the villager. Every number below is a parameter to argue about.

Model (one second per step, level 1 scale: 16 waves of 30 s, the first after 30 s):
  * wood supply: the hero chops (HERO_WOOD_PER_S, the same constant as tools/balance_sim.py,
    scaled by how often he is busy fighting), peasants work at sawmills (auto-assigned),
    a grove has a finite stock that grows back slowly;
  * wood demand: the build order of tools/balance_sim.py reduced to "spend wood as soon as the
    gold allows" is NOT simulated here; instead the script reports wood income and the share of
    the wood bill of a full build (all slots built and upgraded) that each strategy pays.

Run:  python3 tools/proto_economy_v2.py
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

WAVES = 16
WAVE_S = 30
FIRST_DELAY_S = 30
TOTAL_S = FIRST_DELAY_S + WAVES * WAVE_S  # 510 s

HERO_WOOD_PER_S = 1.5  # balance_sim.py: 3 wood a swing, between fights
SLOTS = 16  # level 1

# ---- parameters of the new mechanic (proposals) ----
START_PEASANTS = 2
WORKER_S_PER_WOOD = 8.0  # one worker brings 7.5 wood/min
SAWMILL_SLOTS = 2  # workers per sawmill
SAWMILL_COST = (30, 20)  # gold, wood
HOUSE_PEASANTS = 2
HOUSE_COST = (20, 15)
MAX_SAWMILLS = 4
MAX_HOUSES = 3
BUILD_FIRST_S = 45  # gold is not modelled: the first building not before this second,
BUILD_GAP_S = 25  # and then one building per this many seconds (a stand-in for gold)
GROVE_STOCK = 160  # wood in one grove (a sawmill is tied to a grove)
GROVE_REGROW_PER_MIN = 4.0  # grove regrowth, wood/min
HIRE_COST = (25, 0)  # variant B2: "hire a woodcutter" at the villager (no buildings)
HIRE_MAX = 2
HIRE_S_PER_WOOD = 12.0  # a hired woodcutter is slower: 5 wood/min

# ---- wood shop at the villager (variant A) ----
LOT = 10  # wood per lot, like VillagerTrade.wood_per_lot
SELL_START, SELL_DECAY, SELL_MIN = 6.0, 0.93, 2  # resources/villager_trade.tres
BUY_START, BUY_GROW, BUY_MAX_LOTS = 14.0, 1.08, 6


def tower_wood_bill() -> dict:
    """Wood of one tower (build + both upgrades) from resources/towers/*.tres."""
    bill: dict = {}
    for path in sorted((ROOT / "resources" / "towers").glob("*.tres")):
        text = path.read_text(encoding="utf-8")
        cost = int(re.search(r"cost_wood = (\d+)", text).group(1))
        ups = [int(v) for v in re.search(r"upgrade_wood = Array\[int\]\(\[([^\]]*)\]\)", text).group(1).split(",")]
        bill[path.stem] = cost + sum(ups)
    return bill


@dataclass
class Result:
    name: str
    wood_by_wave: list = field(default_factory=list)
    hero: float = 0.0
    workers: float = 0.0
    spent_on_buildings: float = 0.0
    first_sawmill_s: int = -1
    sawmills: int = 0
    stock_left: float = 0.0


def simulate(name: str, hero_share: float, mode: str, build_at_wood: float = 0.0) -> Result:
    """mode: 'none' | 'hire' | 'sawmills'. hero_share: share of time the hero chops (0..1)."""
    r = Result(name)
    wood = 60.0  # the start wood of every level
    peasants = START_PEASANTS
    sawmills = 0
    houses = 0
    hired = 0
    stock = [GROVE_STOCK] * MAX_SAWMILLS  # a grove per sawmill
    next_build = BUILD_FIRST_S
    for t in range(TOTAL_S):
        # building decisions: house when peasants are all employed, sawmill when workers wait
        if mode == "sawmills" and t >= next_build:
            idle = peasants - sawmills * SAWMILL_SLOTS
            if idle >= SAWMILL_SLOTS and sawmills < MAX_SAWMILLS and wood >= SAWMILL_COST[1] + build_at_wood:
                wood -= SAWMILL_COST[1]
                r.spent_on_buildings += SAWMILL_COST[1]
                sawmills += 1
                next_build = t + BUILD_GAP_S
                if r.first_sawmill_s < 0:
                    r.first_sawmill_s = t
            elif idle < SAWMILL_SLOTS and houses < MAX_HOUSES and sawmills < MAX_SAWMILLS and wood >= HOUSE_COST[1] + build_at_wood:
                wood -= HOUSE_COST[1]
                r.spent_on_buildings += HOUSE_COST[1]
                houses += 1
                peasants += HOUSE_PEASANTS
                next_build = t + BUILD_GAP_S
        if mode == "hire" and hired < HIRE_MAX and t >= 20:
            hired += 1
        gain_hero = HERO_WOOD_PER_S * hero_share
        gain_workers = 0.0
        if mode == "sawmills":
            for i in range(sawmills):
                if stock[i] > 0:
                    got = min(stock[i], SAWMILL_SLOTS / WORKER_S_PER_WOOD)
                    stock[i] -= got
                    gain_workers += got
                stock[i] = min(GROVE_STOCK, stock[i] + GROVE_REGROW_PER_MIN / 60.0)
        elif mode == "hire":
            gain_workers = hired / HIRE_S_PER_WOOD
        wood += gain_hero + gain_workers
        r.hero += gain_hero
        r.workers += gain_workers
        if t >= FIRST_DELAY_S and (t - FIRST_DELAY_S) % WAVE_S == WAVE_S - 1:
            r.wood_by_wave.append(round(wood))
    r.sawmills = sawmills
    r.stock_left = sum(stock[:sawmills])
    return r


def main() -> None:
    bill = tower_wood_bill()
    avg = sum(bill.values()) / len(bill)
    full = avg * SLOTS + 190 + 25 * 4  # all slots built+upgraded, sword (30+60+100), 4 repairs
    print("== Wood bill (resources/towers/*.tres: build + two upgrades) ==")
    for k, v in bill.items():
        print(f"  {k:10s} {v:4d} wood")
    print(f"  average {avg:.0f}; level of {SLOTS} slots fully built {avg * SLOTS:.0f}; "
          f"with the sword and 4 repairs about {full:.0f} wood\n")

    print(f"== Wood income over a level ({TOTAL_S} s, {WAVES} waves); start wood 60 ==")
    rows = [
        simulate("now: hero only, busy 100% chopping (bot model)", 1.0, "none"),
        simulate("now: hero chops 50% of the time (realistic)", 0.5, "none"),
        simulate("hero 50% + 2 hired woodcutters (stage 1)", 0.5, "hire"),
        simulate("hero 50% + sawmills (houses as needed)", 0.5, "sawmills"),
        simulate("hero 25% + sawmills (hero busy fighting)", 0.25, "sawmills"),
        simulate("AFK: no hero + sawmills", 0.0, "sawmills"),
    ]
    print(f"  {'strategy':52s} {'hero':>5s} {'work':>5s} {'total':>6s} {'share of bill':>13s} {'1st mill':>9s} {'mills':>5s}")
    for r in rows:
        total = 60 + r.hero + r.workers - r.spent_on_buildings
        print(f"  {r.name:52s} {r.hero:5.0f} {r.workers:5.0f} {total:6.0f} {total / full:12.0%} "
              f"{('%ds' % r.first_sawmill_s) if r.first_sawmill_s >= 0 else '-':>9s} {r.sawmills:5d}")
    sm = rows[3]
    share = sm.workers / (sm.workers + sm.hero)
    print(f"\n  worker share of the wood income (hero 50% + sawmills): {share:.0%}")
    print(f"  wood by wave (hero 50% + sawmills): {sm.wood_by_wave} (if nothing was spent)")

    print("\n== Peasants, sawmills and houses: payback (wood only) ==")
    per_worker = 60.0 / WORKER_S_PER_WOOD
    print(f"  worker {per_worker:.1f} wood/min; sawmill with {SAWMILL_SLOTS} workers {per_worker * SAWMILL_SLOTS:.1f}/min")
    print(f"  sawmill {SAWMILL_COST} pays back in {SAWMILL_COST[1] / (per_worker * SAWMILL_SLOTS / 60):.0f} s of wood")
    pair = SAWMILL_COST[1] + HOUSE_COST[1]
    print(f"  house {HOUSE_COST} + sawmill for its {HOUSE_PEASANTS} new peasants: {pair} wood, "
          f"back in {pair / (per_worker * HOUSE_PEASANTS / 60):.0f} s")
    print(f"  sustainable output of one grove: {GROVE_REGROW_PER_MIN:.0f}/min regrowth + {GROVE_STOCK} stock;"
          f" {SAWMILL_SLOTS} workers take {per_worker * SAWMILL_SLOTS:.0f}/min: stock lasts "
          f"{GROVE_STOCK / (per_worker * SAWMILL_SLOTS - GROVE_REGROW_PER_MIN):.1f} min, then drops to {GROVE_REGROW_PER_MIN:.0f}/min")
    print(f"  hired woodcutter ({HIRE_COST[0]} gold): {60 / HIRE_S_PER_WOOD:.1f} wood/min, {HIRE_COST[0] / (60 / HIRE_S_PER_WOOD):.1f} gold per wood/min")

    print("\n== Wood shop: sell (now) vs buy (proposal), gold per lot of 10 wood ==")
    print(f"  {'lot #':>5s} {'sell for':>9s} {'buy for':>8s} {'round trip loss':>16s}")
    worst = 1e9
    for n in range(0, 6):
        sell = max(SELL_MIN, round(SELL_START * SELL_DECAY ** n))
        buy = round(BUY_START * BUY_GROW ** n)
        loss = buy - sell
        worst = min(worst, loss)
        print(f"  {n + 1:5d} {sell:9d} {buy:8d} {loss:12d} gold")
    # Arbitrage: independent counters, so the best case for the player is the cheapest buy
    # against the dearest sale.
    best_sell, cheapest_buy = round(SELL_START), round(BUY_START)
    print(f"  best round trip (first lots on both sides): buy {cheapest_buy}, sell {best_sell}: "
          f"the player always loses at least {cheapest_buy - best_sell} gold per lot (no arbitrage)")
    spend = sum(round(BUY_START * BUY_GROW ** n) for n in range(BUY_MAX_LOTS))
    print(f"  the limit of {BUY_MAX_LOTS} lots = {BUY_MAX_LOTS * LOT} wood costs {spend} gold per level "
          f"({spend / (BUY_MAX_LOTS * LOT):.2f} gold per wood); an archer costs 15 gold + 10 wood")


if __name__ == "__main__":
    main()

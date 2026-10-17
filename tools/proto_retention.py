#!/usr/bin/env python3
"""Prototype for docs/RETENTION_V2.md: orders of magnitude only, NOT the game balance and
not connected to the game. Reads resources/economy.json and resources/shop.json and answers:

  1. how many gems per day a player earns today (streak + quests + daily challenge + repeat
     wins) and what a new "free chest with a timer" and a 28-day calendar would add;
  2. how much a "camp" (offline accumulation with a cap of N hours) pays per day for players
     who open the game 1, 2 or 4 times a day (the cap decides the sweet spot);
  3. how many days the shop catalog and a talent tree (a second, SOFT currency "coins")
     take, so gems do not inflate.

Every number marked (proposal) is a parameter to argue about, not a decision.

Run:  python3 tools/proto_retention.py
"""
from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ECON = json.loads((ROOT / "resources" / "economy.json").read_text(encoding="utf-8"))
SHOP = json.loads((ROOT / "resources" / "shop.json").read_text(encoding="utf-8"))

CATALOG = sum(int(i["price"]) for i in SHOP["items"])

# ---- what the game pays today (resources/economy.json; the model of tests/test_economy_balance.gd) ----
STREAK_WEEK = sum(ECON["streak"]["rewards"])  # 220 per 7 days of a full streak
QUESTS_DAY = sum(ECON["quests"]["rewards"])  # 65 if all three are done
DAILY_CHALLENGE = ECON["daily_challenge"]["base"] + 10  # 25 + about 10 for ~20 waves
REPEAT_WIN_CAP = ECON["repeat_win"]["daily_cap"]  # 40

# ---- proposals ----
CHEST_GEMS = (6, 8, 10, 14, 20)  # a free chest every CHEST_HOURS (proposal), mean ~11.6
CHEST_HOURS = 4.0
CHEST_SLOTS = 1
CALENDAR_28 = {7: 100, 14: 150, 21: 150, 28: 250}  # extra to the weekly streak gift (proposal)
CAMP_COINS_PER_H = (6, 9, 13, 18, 24)  # soft coins per hour by camp level 1..5 (proposal)
CAMP_CAP_H = (4, 6, 8, 10, 12)  # cap of the camp by level (proposal)
TALENT_TREE_COINS = 12000  # whole tree in coins (proposal, to be balanced with campaign)
COINS_PER_BATTLE = 40  # coins for a won battle in the campaign (proposal)


@dataclass
class Profile:
    name: str
    days_per_week: float  # days with at least one visit
    visits_per_day: int  # opens of the game on such a day
    does_quests: float  # share of quest gems collected
    does_daily: float  # chance of the daily challenge on a visit day
    battles_per_day: float  # won campaign battles per visit day


PROFILES = [
    Profile("casual", 3.0, 1, 0.3, 0.2, 1.0),
    Profile("regular", 5.5, 2, 0.7, 0.6, 2.0),
    Profile("active", 7.0, 3, 1.0, 0.9, 3.0),
]


def streak_per_visit_day(p: Profile) -> float:
    """Mean streak gems per visit day. A streak survives only with ~daily visits and one
    forgiven day per week, so casual players rarely climb above days 1-2 of the cycle."""
    full = STREAK_WEEK / 7
    if p.days_per_week >= 6.5:
        return full
    if p.days_per_week >= 5:
        return full * 0.55
    return sum(ECON["streak"]["rewards"][:2]) / 2  # always restarts


def today_gems(p: Profile) -> float:
    per_visit = (
        streak_per_visit_day(p)
        + QUESTS_DAY * p.does_quests
        + DAILY_CHALLENGE * p.does_daily
        + min(REPEAT_WIN_CAP, 8 * max(0.0, p.battles_per_day - 1))
    )
    return per_visit * p.days_per_week / 7


def chest_gems_per_visit_day(p: Profile) -> float:
    """A chest fills in CHEST_HOURS and waits (does not fill more). Opened per visit."""
    mean = sum(CHEST_GEMS) / len(CHEST_GEMS)
    return mean * min(p.visits_per_day, 24 / CHEST_HOURS) * CHEST_SLOTS


def calendar_per_day(p: Profile) -> float:
    """Calendar days count visit days, not consecutive ones (no loss on a missed day)."""
    extra = sum(CALENDAR_28.values()) / 28  # one lap = 28 visit days
    return extra * p.days_per_week / 7


def camp_coins_per_visit_day(p: Profile, level: int) -> float:
    rate = CAMP_COINS_PER_H[level - 1]
    cap = CAMP_CAP_H[level - 1]
    # visits are spread over ~16 waking hours; the gap between visits is capped by `cap`
    gap_h = 16 / p.visits_per_day
    first = 8.0  # first visit of the day after the night, at most `cap` hours of earnings
    hours = min(cap, first) + (p.visits_per_day - 1) * min(cap, gap_h)
    return rate * hours


def report() -> None:
    print(f"Catalog: {len(SHOP['items'])} items, {CATALOG} gems")
    print(f"Weekly streak gifts: {STREAK_WEEK}, quests/day: {QUESTS_DAY}\n")
    print("A. Gems per day (mean over the week)")
    print(f"{'profile':9} {'today':>7} {'+chest':>8} {'+calendar':>10} {'total':>7} {'catalog, days':>14}")
    for p in PROFILES:
        t = today_gems(p)
        c = chest_gems_per_visit_day(p) * p.days_per_week / 7
        k = calendar_per_day(p)
        tot = t + c + k
        print(f"{p.name:9} {t:7.0f} {c:8.0f} {k:10.0f} {tot:7.0f} {CATALOG / tot:14.0f}")
    print("\nB. Camp (offline accumulation of SOFT coins, per visit day) by level and visits per day")
    print(f"{'level':5} {'cap, h':>7} {'coins/h':>8} " + " ".join(f"{v} visit/day".rjust(12) for v in (1, 2, 4)))
    for lvl in range(1, 6):
        cells = []
        for v in (1, 2, 4):
            q = Profile("x", 7, v, 0, 0, 0)
            cells.append(f"{camp_coins_per_visit_day(q, lvl):12.0f}")
        print(f"{lvl:5} {CAMP_CAP_H[lvl-1]:7} {CAMP_COINS_PER_H[lvl-1]:8} " + " ".join(cells))
    print("\nC. Days to finish a talent tree of", TALENT_TREE_COINS, "coins (camp level 3 + battles)")
    for p in PROFILES:
        per_visit_day = camp_coins_per_visit_day(p, 3) + COINS_PER_BATTLE * p.battles_per_day
        per_day = per_visit_day * p.days_per_week / 7
        print(f"{p.name:9} {per_day:6.0f} coins/day -> {TALENT_TREE_COINS / per_day:5.0f} days")
    print("\nD. Share of the first week (D1..D7) gems in a 7-day calendar for a new player")
    first_week = sum(ECON["streak"]["rewards"]) + 3 * 40 + QUESTS_DAY * 3
    print(f"   streak 220 + ~3 first wins (stars) ~120 + 3 quest days ~195 = ~{first_week} gems "
          f"= {first_week / CATALOG:.0%} of the catalog")


if __name__ == "__main__":
    report()

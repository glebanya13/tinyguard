#!/usr/bin/env python3
"""Places the tower slots, the hero's start spot and the choppable trees of every level of
resources/levels.json from its paths and castle (deterministic; run it again after the
roads change):  python3 tools/place_slots.py [level ids]

Only the "hero", "slots" and "trees" lines of the file are rewritten.

Slots: three along each of the four approaches to the castle (beside the road, alternating
sides, in a pinwheel so that neighbouring approaches do not crowd the corners next to the
castle), the rest one by one where the most road is still out of reach of every slot.
"""
from __future__ import annotations

import json
import math
import random
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LEVELS = ROOT / "resources" / "levels.json"

CASTLE_PATHS = 4
# Slots per level (balance: more slots = more towers); at least 2-3 beside every approach.
SLOT_COUNT = {1: 16, 2: 17, 3: 18, 4: 18, 5: 18, 6: 18}
TREE_COUNT = 20
SLOT_ROAD = 2.3  # distance of an approach slot from its road
ROAD_CLEAR = 1.6  # nearest road to any slot / tree / hero (validator: 1.3 / 1.2 / 0.8)
SLOT_GAP = 3.2
REACH = 3.6  # shortest tower range (3.9) minus the validator's margin
CASTLE_CLEAR = 3.0  # Chebyshev distance of slots and trees from the castle centre
MARGIN_X, MARGIN_Z = 21.0, 13.8


def seg_dist(p, a, b) -> float:
    dx, dz = b[0] - a[0], b[1] - a[1]
    l2 = dx * dx + dz * dz
    k = max(0.0, min(1.0, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dz) / l2)) if l2 else 0.0
    return math.hypot(a[0] + dx * k - p[0], a[1] + dz * k - p[1])


class Level:
    def __init__(self, lv: dict) -> None:
        self.id = int(lv["id"])
        self.castle = tuple(lv["castle"])
        self.paths = [[tuple(p) for p in pts] for pts in lv["paths"]]
        self.segs = [(a, b) for pts in self.paths for a, b in zip(pts, pts[1:])]
        self.portals = [pts[0] for pts in self.paths]
        # Samples of every road, to see which parts a slot can reach.
        self.samples: list = []
        for a, b in self.segs:
            n = max(1, int(math.dist(a, b) / 0.5))
            self.samples += [(a[0] + (b[0] - a[0]) * i / n, a[1] + (b[1] - a[1]) * i / n) for i in range(n)]
        self.slots: list = []
        self.hero: tuple = (0.0, 0.0)
        self.trees: list = []

    def road(self, p) -> float:
        return min(seg_dist(p, a, b) for a, b in self.segs)

    def inside(self, p) -> bool:
        return abs(p[0]) <= MARGIN_X and abs(p[1]) <= MARGIN_Z

    def away_from_castle(self, p) -> bool:
        return max(abs(p[0] - self.castle[0]), abs(p[1] - self.castle[1])) >= CASTLE_CLEAR

    def free(self, p, gap: float, others: list) -> bool:
        return all(math.dist(p, o) >= gap for o in others)

    def slot_ok(self, p) -> bool:
        return (
            self.inside(p)
            and self.away_from_castle(p)
            and self.road(p) >= ROAD_CLEAR
            and all(math.dist(p, q) >= 3.0 for q in self.portals)
            and self.free(p, SLOT_GAP, self.slots)
            and self.free(p, 2.4, [self.hero])
        )

    def place_hero(self) -> None:
        """The free spot next to the castle nearest to its front (the corner towards the camera)."""
        cx, cz = self.castle
        best, best_d = None, 1e9
        for i in range(-12, 13):
            for j in range(-12, 13):
                p = (cx + i * 0.5, cz + j * 0.5)
                if (
                    self.inside(p)
                    and self.away_from_castle(p)
                    and self.road(p) >= 2.2
                    and self.free(p, 2.2, self.slots)
                    and (d := math.dist(p, (cx + 3.3, cz + 3.3))) < best_d
                ):
                    best, best_d = p, d
        if best is None:
            raise SystemExit(f"level {self.id}: no room for the hero next to the castle")
        self.hero = best

    def approach_slots(self) -> None:
        cx, cz = self.castle
        for k in range(CASTLE_PATHS):
            pts = self.paths[k]
            ux, uz = pts[-2][0] - pts[-1][0], pts[-2][1] - pts[-1][1]
            length = abs(ux) + abs(uz)
            ux, uz = (1 if ux > 0 else -1, 0) if abs(ux) > abs(uz) else (0, 1 if uz > 0 else -1)
            nx, nz = -uz, ux  # turning left of the way out: every approach leans the same way
            got = 0
            for i, along in enumerate((3.6, 6.8, 10.0)):
                if along > length - 0.6:
                    break
                for swing in (0, 1, -1, 2, -2, 3, -3):
                    s = along + 0.5 * swing
                    for side in ((1, -1, 1)[i], -(1, -1, 1)[i]):
                        for lat in (SLOT_ROAD, SLOT_ROAD + 0.4, SLOT_ROAD - 0.3, SLOT_ROAD + 0.8):
                            p = (cx + ux * s + nx * side * lat, cz + uz * s + nz * side * lat)
                            if self.slot_ok(p):
                                self.slots.append(snap(p))
                                got += 1
                                break
                        else:
                            continue
                        break
                    else:
                        continue
                    break
            if got < 2:
                raise SystemExit(f"level {self.id}: only {got} slots beside the approach of path {k}")

    def fill_slots(self, total: int) -> None:
        def covered(sample) -> bool:
            return any(math.dist(sample, s) <= REACH for s in self.slots)

        while len(self.slots) < total:
            open_samples = [s for s in self.samples if not covered(s)]
            best, best_score = None, -1.0
            x = -MARGIN_X
            while x <= MARGIN_X:
                z = -MARGIN_Z
                while z <= MARGIN_Z:
                    p = (x, z)
                    road = self.road(p)
                    if 1.9 <= road <= 3.0 and self.slot_ok(p):
                        score = sum(1 for s in open_samples if math.dist(p, s) <= REACH) - 0.01 * road
                        if score > best_score:
                            best, best_score = p, score
                    z += 0.5
                x += 0.5
            if best is None:
                raise SystemExit(f"level {self.id}: cannot place slot {len(self.slots) + 1}")
            self.slots.append(snap(best))

    def place_trees(self) -> None:
        rng = random.Random(77 + self.id)
        tries = 0
        while len(self.trees) < TREE_COUNT and tries < 20000:
            tries += 1
            p = snap((rng.uniform(-20.5, 20.5), rng.uniform(-13.8, 13.8)))
            if (
                self.road(p) >= 2.0
                and self.away_from_castle(p)
                and self.free(p, 2.0, self.slots)
                and self.free(p, 2.4, [self.hero])
                and self.free(p, 3.0, self.portals)
                and self.free(p, 3.0, self.trees)
            ):
                self.trees.append(p)
        if len(self.trees) < TREE_COUNT:
            raise SystemExit(f"level {self.id}: only {len(self.trees)} trees fit")

    def run(self) -> None:
        self.hero = (1e3, 1e3)  # none yet: the approach slots come first
        self.approach_slots()
        self.place_hero()
        self.fill_slots(SLOT_COUNT[self.id])
        self.place_trees()


def snap(p) -> tuple:
    return (round(p[0] * 2) / 2, round(p[1] * 2) / 2)


def fmt(points: list) -> str:
    return "[" + ", ".join(f"[{x:.1f}, {z:.1f}]" for x, z in points) + "]"


def rewrite(text: str, level: Level) -> str:
    start = re.search(rf'"id": {level.id},', text).start()
    nxt = re.search(r'\n    \{\n      "id":', text[start:])
    end = start + nxt.start() if nxt else len(text)
    block = text[start:end]
    for key, value in (("hero", fmt([level.hero])[1:-1]), ("slots", fmt(level.slots)), ("trees", fmt(level.trees))):
        block, n = re.subn(rf'("{key}": ).*?(,?)$', lambda m: m.group(1) + value + m.group(2), block, count=1, flags=re.M)
        if n != 1:
            raise SystemExit(f'level {level.id}: no "{key}" line')
    return text[:start] + block + text[end:]


def main() -> None:
    text = LEVELS.read_text(encoding="utf-8")
    only = {int(a) for a in sys.argv[1:]}
    for lv in json.loads(text)["levels"]:
        if only and lv["id"] not in only:
            continue
        level = Level(lv)
        level.run()
        text = rewrite(text, level)
        print(f"level {level.id}: {len(level.slots)} slots, {len(level.trees)} trees, hero {level.hero}")
    LEVELS.write_text(text, encoding="utf-8")


if __name__ == "__main__":
    main()

"""A maintain bot must finish one turret before walking to another."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
MAINTAIN = (ROOT / "scripts" / "maintain.lua").read_text(encoding="utf-8")


def decide_next_job(locked, jobs):
    if locked:
        for job in jobs:
            if job["id"] == locked and job["need"] > 0:
                return job["id"]
    nearest = None
    for job in jobs:
        if job["need"] > 0 and (nearest is None or job["dist"] < nearest["dist"]):
            nearest = job
    return nearest["id"] if nearest else None


class TurretSwapLogicTest(unittest.TestCase):
    def test_keeps_locked_turret_even_if_other_is_nearer(self):
        jobs = [
            {"id": "A", "need": 20, "dist": 12},
            {"id": "B", "need": 20, "dist": 3},
        ]
        self.assertEqual(decide_next_job("A", jobs), "A")

    def test_switches_only_when_locked_is_full(self):
        jobs = [
            {"id": "A", "need": 0, "dist": 2},
            {"id": "B", "need": 20, "dist": 8},
        ]
        self.assertEqual(decide_next_job("A", jobs), "B")


class TurretSwapSourceTest(unittest.TestCase):
    def test_tick_ammo_does_not_clear_lock_after_partial_insert(self):
        tick = MAINTAIN[MAINTAIN.index("local function tick_ammo") : MAINTAIN.index("local function insert_fuel")]
        success = tick[tick.index("if inserted > 0 then") : tick.index("state.ammo_done")]
        self.assertNotIn("state.current_turret = nil", success)

    def test_collect_keeps_locked_turret_even_when_above_min(self):
        collect = MAINTAIN[MAINTAIN.index("function maintain.collect_ammo_jobs") : MAINTAIN.index("function maintain.collect_fuel_jobs")]
        self.assertIn("state.current_turret", collect)
        self.assertIn("ammo_needs_refill(total, wanted, rule, locked)", collect)


if __name__ == "__main__":
    unittest.main()

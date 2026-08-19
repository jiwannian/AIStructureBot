"""Full turrets must not keep pulling maintain bots off coal or each other."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
MAINTAIN = (ROOT / "scripts" / "maintain.lua").read_text(encoding="utf-8")


class FullTurretIdleTest(unittest.TestCase):
    def test_collect_requires_room_below_cap(self):
        collect = MAINTAIN[
            MAINTAIN.index("function maintain.collect_ammo_jobs") : MAINTAIN.index("function maintain.collect_fuel_jobs")
        ]
        self.assertIn("ammo_needs_refill", collect)
        self.assertIn("total or 0) >= cap", MAINTAIN[MAINTAIN.index("local function ammo_needs_refill") : MAINTAIN.index("function maintain.collect_ammo_jobs")])
        self.assertNotIn("count <= rule.min or (locked and count < cap)", collect)

    def test_collect_uses_total_ammo(self):
        collect = MAINTAIN[
            MAINTAIN.index("function maintain.collect_ammo_jobs") : MAINTAIN.index("function maintain.collect_fuel_jobs")
        ]
        self.assertIn("turret_ammo_total", collect)

    def test_empty_job_uses_total_ammo(self):
        empty = MAINTAIN[
            MAINTAIN.index("function maintain.empty_ammo_job") : MAINTAIN.index("function maintain.urgent_fuel_job")
        ]
        self.assertIn("turret_ammo_total", empty)

    def test_failed_insert_does_not_keep_lock(self):
        tick = MAINTAIN[MAINTAIN.index("local function tick_ammo") : MAINTAIN.index("local function insert_fuel")]
        self.assertIn("state.current_turret = nil", tick)
        self.assertLess(tick.index("if inserted > 0 then"), tick.rindex("state.current_turret = nil"))

    def test_idle_clears_destination(self):
        tick = MAINTAIN[MAINTAIN.index("function maintain.tick") :]
        self.assertIn("stop_spider", tick)
        self.assertIn("autopilot_destination = nil", tick)


if __name__ == "__main__":
    unittest.main()

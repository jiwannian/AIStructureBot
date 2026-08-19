"""Empty furnaces must be mined for and refilled, not just walked toward."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
MAINTAIN = (ROOT / "scripts" / "maintain.lua").read_text(encoding="utf-8")
ZH = (ROOT / "locale" / "zh-CN" / "locale.cfg").read_text(encoding="utf-8")


class EmptyFurnaceRefillTest(unittest.TestCase):
    def test_tick_fuel_mines_when_standing_on_ore(self):
        tick = MAINTAIN[MAINTAIN.index("local function tick_fuel") : MAINTAIN.index("local function tick_repair")]
        self.assertIn("craft.mine_enough", tick)
        self.assertLess(
            tick.index("if give > 0 then"),
            tick.index("craft.mine_enough"),
        )
        self.assertLess(
            tick.index("craft.mine_enough"),
            tick.index("if follow_locked"),
        )

    def test_fuel_rule_ignores_machines_without_fuel_inventory(self):
        helper = MAINTAIN[
            MAINTAIN.index("local function fuel_rule_for") : MAINTAIN.index("function maintain.collect_fuel_jobs")
        ]
        self.assertIn("machine_fuel_inventory", helper)
        self.assertIn("return nil", helper)

    def test_collect_skips_missing_fuel_inventory(self):
        collect = MAINTAIN[
            MAINTAIN.index("function maintain.collect_fuel_jobs") : MAINTAIN.index("function maintain.urgent_fuel_job")
        ]
        self.assertIn("if not inv then", collect)

    def test_empty_furnace_is_urgent_beyond_nearby_radius(self):
        urgent = MAINTAIN[
            MAINTAIN.index("function maintain.urgent_fuel_job") : MAINTAIN.index("local REPAIR_TYPES")
        ]
        self.assertIn("empty or (dist <= URGENT_FUEL_RADIUS and have > 0)", urgent)
        self.assertNotIn("dist <= URGENT_FUEL_RADIUS and (have > 0 or empty)", urgent)

    def test_ammo_yields_to_empty_furnace_while_mining(self):
        tick = MAINTAIN[MAINTAIN.index("local function tick_ammo") : MAINTAIN.index("local function insert_fuel")]
        yield_at = tick.rindex("maintain.urgent_fuel_job")
        follow_at = tick.index("if follow_locked")
        self.assertLess(yield_at, follow_at)

    def test_fuel_does_not_follow_unrelated_ore(self):
        tick = MAINTAIN[MAINTAIN.index("local function tick_fuel") : MAINTAIN.index("local function tick_repair")]
        self.assertIn('locked_name ~= job.fuel', tick)


if __name__ == "__main__":
    unittest.main()

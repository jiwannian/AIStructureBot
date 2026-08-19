"""Maintain bots must mine coal when the trunk has none."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
MAINTAIN = (ROOT / "scripts" / "maintain.lua").read_text(encoding="utf-8")


class MineCoalTest(unittest.TestCase):
    def test_urgent_fuel_includes_empty_trunk(self):
        urgent = MAINTAIN[MAINTAIN.index("function maintain.urgent_fuel_job") : MAINTAIN.index("local REPAIR_TYPES")]
        self.assertIn("empty or (dist <= URGENT_FUEL_RADIUS and have > 0)", urgent)

    def test_tick_fuel_goes_mine_when_empty(self):
        tick = MAINTAIN[MAINTAIN.index("local function tick_fuel") : MAINTAIN.index("local function tick_repair")]
        self.assertIn("craft.mine_enough", tick)
        self.assertIn("state.mine_target = ore", tick)
        self.assertLess(tick.index("if give > 0 then"), tick.index("craft.mine_enough"))

    def test_mine_coal_name_is_used(self):
        self.assertIn('craft.find_nearest_resource(player.surface, from, item_name)', MAINTAIN)
        self.assertIn("state.mine_target", MAINTAIN)


if __name__ == "__main__":
    unittest.main()

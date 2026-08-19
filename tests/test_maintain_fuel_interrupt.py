"""Nearby empty furnaces can interrupt ammo work."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
MAINTAIN = (ROOT / "scripts" / "maintain.lua").read_text(encoding="utf-8")


class FuelInterruptTest(unittest.TestCase):
    def test_urgent_fuel_helper_exists(self):
        self.assertIn("function maintain.urgent_fuel_job", MAINTAIN)
        self.assertIn("URGENT_FUEL_RADIUS", MAINTAIN)

    def test_tick_checks_urgent_fuel_before_continuing_ammo(self):
        main = MAINTAIN[MAINTAIN.index("function maintain.tick") :]
        empty = main.index("empty_ammo_job")
        urgent = main.index("maintain.urgent_fuel_job")
        ammo = main.rindex("tick_ammo")
        self.assertLess(empty, urgent)
        self.assertLess(urgent, ammo)
        self.assertIn("tick_fuel", main)

    def test_ammo_walk_can_yield_to_nearby_fuel(self):
        tick = MAINTAIN[MAINTAIN.index("local function tick_ammo") : MAINTAIN.index("local function insert_fuel")]
        self.assertIn("maintain.urgent_fuel_job", tick)


if __name__ == "__main__":
    unittest.main()

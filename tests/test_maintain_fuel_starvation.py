"""Ammo must not block coal refill when the bot cannot insert more ammo."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
MAINTAIN = (ROOT / "scripts" / "maintain.lua").read_text(encoding="utf-8")


class FuelStarvationTest(unittest.TestCase):
    def test_failed_ammo_insert_does_not_keep_busy(self):
        tick = MAINTAIN[MAINTAIN.index("local function tick_ammo") : MAINTAIN.index("local function insert_fuel")]
        self.assertIn("if inserted > 0 then", tick)
        self.assertIn("state.current_turret = nil", tick)
        self.assertLess(
            tick.index("if inserted > 0 then"),
            tick.rindex("state.current_turret = nil"),
        )

    def test_main_tick_tries_fuel_after_idle_ammo(self):
        main = MAINTAIN[MAINTAIN.index("function maintain.tick") :]
        ammo = main.index("if tick_ammo")
        fuel = main.rindex("if tick_fuel")
        self.assertLess(ammo, fuel)
        self.assertIn("tick_fuel", main)

    def test_ammo_without_stock_falls_through(self):
        tick = MAINTAIN[MAINTAIN.index("local function tick_ammo") : MAINTAIN.index("local function insert_fuel")]
        self.assertIn("return false", tick)
        self.assertLess(
            tick.rindex("if give > 0 then"),
            tick.rindex("return false"),
        )


if __name__ == "__main__":
    unittest.main()

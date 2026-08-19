"""Maintain mode can refill coal in boilers and stone furnaces."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
MAINTAIN = (ROOT / "scripts" / "maintain.lua").read_text(encoding="utf-8")
GUI = (ROOT / "scripts" / "gui.lua").read_text(encoding="utf-8")
ZH = (ROOT / "locale" / "zh-CN" / "locale.cfg").read_text(encoding="utf-8")
EN = (ROOT / "locale" / "en" / "locale.cfg").read_text(encoding="utf-8")


class MaintainFuelContractTest(unittest.TestCase):
    def test_fuel_machine_api_exists(self):
        self.assertIn("function maintain.fuel_machine_names()", MAINTAIN)
        self.assertIn("function maintain.default_fuel_rule", MAINTAIN)
        self.assertIn("function maintain.collect_fuel_jobs", MAINTAIN)
        self.assertIn("function maintain.update_fuel_rule", MAINTAIN)

    def test_coal_is_default_fuel(self):
        self.assertIn('fuel = "coal"', MAINTAIN)
        self.assertIn("stone-furnace", MAINTAIN)
        self.assertIn("boiler", MAINTAIN)

    def test_tick_refills_fuel_before_repair(self):
        tick = MAINTAIN[MAINTAIN.index("function maintain.tick") :]
        self.assertIn("tick_fuel", tick)
        self.assertIn("tick_ammo", tick)
        self.assertLess(tick.index("tick_fuel"), tick.index("tick_repair"))

    def test_gui_shows_fuel_rules(self):
        self.assertIn("maintain.fuel_machine_names", GUI)
        self.assertIn("ai_mt_fuel", GUI)
        self.assertIn("maintain-fuel-min", GUI)

    def test_locale_has_fuel_lines(self):
        for text in (ZH, EN):
            self.assertIn("maintain-fuel-enable=", text)
            self.assertIn("maintain-fuel-min=", text)
            self.assertIn("maintain-fuel-max=", text)
            self.assertIn("maintain-fuel-plan=", text)


if __name__ == "__main__":
    unittest.main()

"""Ammo at the min threshold must refill, and empty ammo must mine on arrival."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
MAINTAIN = (ROOT / "scripts" / "maintain.lua").read_text(encoding="utf-8")
ZH = (ROOT / "locale" / "zh-CN" / "locale.cfg").read_text(encoding="utf-8")
EN = (ROOT / "locale" / "en" / "locale.cfg").read_text(encoding="utf-8")


class AmmoThresholdSourceTest(unittest.TestCase):
    def test_collect_uses_at_most_min(self):
        collect = MAINTAIN[
            MAINTAIN.index("function maintain.collect_ammo_jobs") : MAINTAIN.index("function maintain.collect_fuel_jobs")
        ]
        self.assertIn("ammo_needs_refill", collect)
        self.assertNotIn("count < rule.min or (locked and count < cap)", collect)
        self.assertNotIn("if count < rule.min then", collect)

    def test_locale_says_at_or_below(self):
        self.assertIn("低于或等于", ZH)
        self.assertIn("at or below", EN)


class AmmoMineOnArrivalTest(unittest.TestCase):
    def test_tick_ammo_fulfills_before_follow_locked(self):
        tick = MAINTAIN[MAINTAIN.index("local function tick_ammo") : MAINTAIN.index("local function insert_fuel")]
        self.assertIn("craft_into_bot", tick)
        self.assertLess(tick.index("craft_into_bot"), tick.index("if follow_locked"))

    def test_tick_ammo_clears_unrelated_ore(self):
        tick = MAINTAIN[MAINTAIN.index("local function tick_ammo") : MAINTAIN.index("local function insert_fuel")]
        self.assertIn("locked_name ~= job.ammo", tick)


if __name__ == "__main__":
    unittest.main()

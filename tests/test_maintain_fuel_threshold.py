"""Fuel at the min threshold must still be refilled up to max."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
MAINTAIN = (ROOT / "scripts" / "maintain.lua").read_text(encoding="utf-8")
ZH = (ROOT / "locale" / "zh-CN" / "locale.cfg").read_text(encoding="utf-8")


def needs_fuel(count, minimum, maximum, locked=False):
    cap = max(minimum, maximum)
    return count <= minimum or (locked and count < cap)


class FuelThresholdLogicTest(unittest.TestCase):
    def test_count_equal_to_min_needs_refill(self):
        self.assertTrue(needs_fuel(5, 5, 50))

    def test_count_above_min_does_not_need_refill(self):
        self.assertFalse(needs_fuel(6, 5, 50))

    def test_locked_machine_keeps_filling_to_max(self):
        self.assertTrue(needs_fuel(20, 5, 50, locked=True))


class FuelThresholdSourceTest(unittest.TestCase):
    def test_collect_uses_at_most_min(self):
        collect = MAINTAIN[MAINTAIN.index("function maintain.collect_fuel_jobs") :]
        self.assertIn("count < cap and (count <= rule.min or locked)", collect)
        self.assertNotIn("count < rule.min or (locked and count < cap)", collect.split("function maintain.urgent_fuel_job")[0])

    def test_unknown_furnace_uses_type_fallback(self):
        helper = MAINTAIN[MAINTAIN.index("local function fuel_rule_for") : MAINTAIN.index("function maintain.collect_fuel_jobs")]
        self.assertIn('machine.type == "furnace"', helper)
        self.assertIn('rules["steel-furnace"]', helper)

    def test_locale_says_at_or_below(self):
        self.assertIn("低于或等于", ZH)


if __name__ == "__main__":
    unittest.main()

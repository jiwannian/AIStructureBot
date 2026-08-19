"""Wrong ammo at or below the min must be destroyed, then the chosen ammo inserted."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
MAINTAIN = (ROOT / "scripts" / "maintain.lua").read_text(encoding="utf-8")
ZH = (ROOT / "locale" / "zh-CN" / "locale.cfg").read_text(encoding="utf-8")


class ReplaceWrongAmmoTest(unittest.TestCase):
    def test_clear_helper_destroys_other_ammo(self):
        helper = MAINTAIN[
            MAINTAIN.index("local function clear_foreign_ammo") : MAINTAIN.index("local function tick_ammo")
        ]
        self.assertIn("stack.clear", helper)
        self.assertIn("stack.name ~= wanted", helper)
        self.assertNotIn("give_to_bot", helper)
        self.assertNotIn("bot.insert", helper)

    def test_tick_clears_before_insert(self):
        tick = MAINTAIN[MAINTAIN.index("local function tick_ammo") : MAINTAIN.index("local function insert_fuel")]
        self.assertLess(tick.index("clear_foreign_ammo"), tick.index("insert_ammo"))

    def test_collect_flags_wrong_ammo_at_min(self):
        helper = MAINTAIN[
            MAINTAIN.index("local function ammo_needs_refill") : MAINTAIN.index("function maintain.collect_ammo_jobs")
        ]
        self.assertIn("other", helper)
        self.assertIn("wanted", helper)

    def test_locale_mentions_replace(self):
        self.assertIn("maintain-ammo-replace=", ZH)


if __name__ == "__main__":
    unittest.main()

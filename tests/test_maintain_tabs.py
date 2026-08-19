"""Maintain menu is split into repair / ammo / fuel sub-tabs."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
GUI = (ROOT / "scripts" / "gui.lua").read_text(encoding="utf-8")
ZH = (ROOT / "locale" / "zh-CN" / "locale.cfg").read_text(encoding="utf-8")
EN = (ROOT / "locale" / "en" / "locale.cfg").read_text(encoding="utf-8")


class MaintainTabsTest(unittest.TestCase):
    def test_open_creates_subtabs(self):
        self.assertIn('name = "ai_bot_mt_tabs"', GUI)
        self.assertIn('name = "ai_bot_mt_repair"', GUI)
        self.assertIn('name = "ai_bot_mt_ammo"', GUI)
        self.assertIn('name = "ai_bot_mt_fuel"', GUI)
        self.assertIn("tab-maintain-repair", GUI)
        self.assertIn("tab-maintain-ammo", GUI)
        self.assertIn("tab-maintain-fuel", GUI)

    def test_rebuild_fills_separate_panes(self):
        rebuild = GUI[GUI.index("local function rebuild_maintain_box") : GUI.index("local function add_count_table")]
        self.assertIn("ai_bot_mt_repair", rebuild)
        self.assertIn("ai_bot_mt_ammo", rebuild)
        self.assertIn("ai_bot_mt_fuel", rebuild)
        self.assertNotIn("if #names == 0 and #fuel_names == 0 then", rebuild)

    def test_locale_has_subtab_names(self):
        for text in (ZH, EN):
            self.assertIn("tab-maintain-repair=", text)
            self.assertIn("tab-maintain-ammo=", text)
            self.assertIn("tab-maintain-fuel=", text)


if __name__ == "__main__":
    unittest.main()

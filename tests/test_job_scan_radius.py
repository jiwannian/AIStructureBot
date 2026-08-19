"""Ghost and maintain job scans are player-centered and text-box adjustable."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
SETTINGS = (ROOT / "settings.lua").read_text(encoding="utf-8")
UTIL = (ROOT / "scripts" / "util.lua").read_text(encoding="utf-8")
MAINTAIN = (ROOT / "scripts" / "maintain.lua").read_text(encoding="utf-8")
PLAN = (ROOT / "scripts" / "plan.lua").read_text(encoding="utf-8")
GUI = (ROOT / "scripts" / "gui.lua").read_text(encoding="utf-8")
CONTROL = (ROOT / "control.lua").read_text(encoding="utf-8")
ZH = (ROOT / "locale" / "zh-CN" / "locale.cfg").read_text(encoding="utf-8")
EN = (ROOT / "locale" / "en" / "locale.cfg").read_text(encoding="utf-8")


class JobScanRadiusTest(unittest.TestCase):
    def test_setting_exists(self):
        self.assertIn('name = "ai-bot-job-radius"', SETTINGS)
        block = SETTINGS[SETTINGS.index("ai-bot-job-radius") :]
        self.assertIn("default_value = 256", block)
        self.assertIn("minimum_value = 32", block)

    def test_util_reads_job_radius(self):
        self.assertIn("function util.job_radius", UTIL)
        self.assertIn("function util.player_origin", UTIL)
        self.assertIn("ai-bot-job-radius", UTIL)

    def test_ammo_scan_uses_player_origin_and_radius(self):
        collect = MAINTAIN[
            MAINTAIN.index("function maintain.collect_ammo_jobs") : MAINTAIN.index("function maintain.collect_fuel_jobs")
        ]
        self.assertIn("maintain.cached_entities", collect)
        self.assertIn("origin", collect)
        self.assertIn("radius", collect)
        self.assertNotIn("position = bot.position", collect)
        self.assertNotIn("AMMO_SCAN_RADIUS", collect)

    def test_fuel_scan_uses_player_origin_and_radius(self):
        collect = MAINTAIN[
            MAINTAIN.index("function maintain.collect_fuel_jobs") : MAINTAIN.index("function maintain.empty_ammo_job")
        ]
        self.assertIn("maintain.cached_entities", collect)
        self.assertIn("origin", collect)
        self.assertIn("radius", collect)
        self.assertNotIn("position = bot.position", collect)
        self.assertNotIn("FUEL_SCAN_RADIUS", collect)

    def test_repair_scan_uses_passed_radius(self):
        collect = MAINTAIN[
            MAINTAIN.index("function maintain.collect_repair_jobs") : MAINTAIN.index("local function bot_item_count")
        ]
        self.assertIn("maintain.cached_entities", collect)
        self.assertIn("radius", collect)

    def test_tick_passes_player_centered_scan(self):
        tick = MAINTAIN[MAINTAIN.index("function maintain.tick") :]
        self.assertIn("util.player_origin", tick)
        self.assertIn("util.job_radius", tick)
        self.assertIn("empty_ammo_job(bot, state, teammates, scan_from, scan_radius)", tick)
        self.assertIn("urgent_fuel_job(bot, state, teammates, scan_from, scan_radius)", tick)

    def test_ghost_assign_uses_job_radius(self):
        assign = PLAN[PLAN.index("function plan.assign_nearby") :]
        self.assertIn("util.job_radius", assign)

    def test_gui_has_job_radius_text_box(self):
        self.assertIn("ai_bot_set_job", GUI)
        self.assertIn('{"ai-bot.settings-job"}', GUI)
        add_slider = GUI[GUI.index("local function add_slider") : GUI.index('add_slider("ai_bot_set_job"')]
        self.assertIn("textfield", add_slider)
        apply = GUI[GUI.index("function gui.apply_settings") :]
        self.assertIn("ai-bot-job-radius", apply)

    def test_settings_text_box_saves_on_confirm(self):
        self.assertIn("on_gui_confirmed", CONTROL)
        confirmed = CONTROL[CONTROL.index("on_gui_confirmed") :]
        self.assertIn("ai_bot_set_", confirmed)
        self.assertIn("gui.apply_settings", confirmed)

    def test_locale_has_job_radius(self):
        for text in (ZH, EN):
            self.assertIn("ai-bot-job-radius=", text)
            self.assertIn("settings-job=", text)


if __name__ == "__main__":
    unittest.main()

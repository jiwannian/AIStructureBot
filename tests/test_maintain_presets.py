"""Maintain menu values must survive restart and not be reset to defaults."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
MAINTAIN = (ROOT / "scripts" / "maintain.lua").read_text(encoding="utf-8")
GUI = (ROOT / "scripts" / "gui.lua").read_text(encoding="utf-8")
CONTROL = (ROOT / "control.lua").read_text(encoding="utf-8")


class MaintainPresetPersistTest(unittest.TestCase):
    def test_player_presets_api_exists(self):
        self.assertIn("function maintain.player_presets", MAINTAIN)
        self.assertIn("function maintain.ensure_rules(unit_number, player)", MAINTAIN)
        self.assertIn("store.maintain", MAINTAIN)

    def test_ensure_does_not_replace_existing_min_max(self):
        ensure = MAINTAIN[
            MAINTAIN.index("function maintain.ensure_rules") : MAINTAIN.index("function maintain.update_rule")
        ]
        self.assertNotIn("state.rules[name] = maintain.default_rule(name)", ensure)
        self.assertIn("merge_ammo_rule", ensure)
        self.assertIn("player_presets", ensure)
        self.assertIn("if not presets.rules[name]", ensure)
        self.assertIn("if not presets.fuel_rules[name]", ensure)

    def test_merge_keeps_saved_min_max_and_ammo(self):
        merge = MAINTAIN[
            MAINTAIN.index("local function merge_ammo_rule") : MAINTAIN.index("local function merge_fuel_rule")
        ]
        self.assertIn("if existing.min ~= nil", merge)
        self.assertIn("if existing.max ~= nil", merge)
        self.assertIn("if existing.ammo then", merge)
        fuel = MAINTAIN[
            MAINTAIN.index("local function merge_fuel_rule") : MAINTAIN.index("function maintain.set_mode")
        ]
        self.assertIn("if existing.min ~= nil", fuel)
        self.assertIn("if existing.max ~= nil", fuel)
        self.assertIn("if existing.fuel then", fuel)

    def test_update_writes_player_presets(self):
        update = MAINTAIN[
            MAINTAIN.index("function maintain.update_rule") : MAINTAIN.index("function maintain.update_fuel_rule")
        ]
        self.assertIn("player_presets", update)
        self.assertIn("presets.rules[turret_name] = copy_rule(rule)", update)
        fuel = MAINTAIN[
            MAINTAIN.index("function maintain.update_fuel_rule") : MAINTAIN.index("local function search_origin")
        ]
        self.assertIn("player_presets", fuel)
        self.assertIn("presets.fuel_rules[machine_name] = copy_rule(rule)", fuel)

    def test_settings_save_without_confirm_button(self):
        self.assertIn("gui.apply_settings", CONTROL)
        self.assertIn("on_gui_value_changed", CONTROL)
        self.assertIn("ai_bot_set_", CONTROL)
        self.assertIn("on_gui_checked_state_changed", CONTROL)
        self.assertIn("ai_bot_set_force", CONTROL)

    def test_apply_settings_writes_all_menu_values(self):
        apply = GUI[GUI.index("function gui.apply_settings") :]
        for name in (
            "ai-bot-search-radius",
            "ai-bot-job-radius",
            "ai-bot-warn-threshold",
            "ai-bot-reserve-stock",
            "ai-bot-work-range",
            "ai-bot-wait-timeout",
            "ai-bot-force-build",
            "ai-bot-take-from-network",
            "ai-bot-take-from-player",
        ):
            self.assertIn(name, apply)

    def test_gui_rebuild_and_edits_use_player(self):
        self.assertIn("maintain.ensure_rules(bot.unit_number, player)", GUI)
        self.assertIn("maintain.update_rule(bot.unit_number, nil, \"repair\", value, player)", GUI)
        self.assertIn("maintain.update_fuel_rule(bot.unit_number, tags.ai_mt_fuel, field, rule_value, player)", GUI)
        self.assertIn("maintain.update_rule(bot.unit_number, tags.ai_mt_turret, tags.ai_mt_field, value, player)", GUI)


if __name__ == "__main__":
    unittest.main()

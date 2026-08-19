"""Empty gun turrets must be collected even when Factorio 2.0 uses a category map."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
MAINTAIN = (ROOT / "scripts" / "maintain.lua").read_text(encoding="utf-8")


class EmptyTurretCategoryTest(unittest.TestCase):
    def test_reads_singular_ammo_category(self):
        helper = MAINTAIN[
            MAINTAIN.index("local function turret_categories") : MAINTAIN.index("function maintain.compatible_ammo")
        ]
        self.assertIn("params.ammo_category", helper)

    def test_reads_category_map_keys(self):
        helper = MAINTAIN[
            MAINTAIN.index("local function turret_categories") : MAINTAIN.index("function maintain.compatible_ammo")
        ]
        self.assertIn("for key, value in pairs", helper)
        self.assertIn("type(key) == \"string\"", helper)

    def test_unknown_turret_uses_type_fallback(self):
        self.assertIn("local function ammo_rule_for", MAINTAIN)
        helper = MAINTAIN[
            MAINTAIN.index("local function ammo_rule_for") : MAINTAIN.index("function maintain.collect_ammo_jobs")
        ]
        self.assertIn('machine.type == "ammo-turret"' if False else 'turret.type == "ammo-turret"', helper)
        self.assertIn('rules["gun-turret"]', helper)

    def test_collect_uses_ammo_rule_for(self):
        collect = MAINTAIN[
            MAINTAIN.index("function maintain.collect_ammo_jobs") : MAINTAIN.index("function maintain.collect_fuel_jobs")
        ]
        self.assertIn("ammo_rule_for", collect)

    def test_ensure_rules_repairs_missing_ammo(self):
        ensure = MAINTAIN[
            MAINTAIN.index("function maintain.ensure_rules") : MAINTAIN.index("function maintain.update_rule")
        ]
        self.assertIn("if not rule.ammo then", ensure)

    def test_empty_turret_beats_distant_empty_furnace(self):
        tick = MAINTAIN[MAINTAIN.index("function maintain.tick") :]
        self.assertIn("empty_turret", tick)
        self.assertLess(tick.index("empty_turret"), tick.index("urgent_fuel"))


if __name__ == "__main__":
    unittest.main()

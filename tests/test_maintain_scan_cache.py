"""Maintain job scans must be cached so walking does not hitch every few steps."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
MAINTAIN = (ROOT / "scripts" / "maintain.lua").read_text(encoding="utf-8")
AI = (ROOT / "scripts" / "ai.lua").read_text(encoding="utf-8")


class MaintainScanCacheTest(unittest.TestCase):
    def test_entity_scans_go_through_cache(self):
        self.assertIn("function maintain.cached_entities", MAINTAIN)
        ammo = MAINTAIN[
            MAINTAIN.index("function maintain.collect_ammo_jobs") : MAINTAIN.index("function maintain.collect_fuel_jobs")
        ]
        self.assertIn("maintain.cached_entities", ammo)
        self.assertNotIn("find_entities_filtered", ammo)
        fuel = MAINTAIN[
            MAINTAIN.index("function maintain.collect_fuel_jobs") : MAINTAIN.index("function maintain.empty_ammo_job")
        ]
        self.assertIn("maintain.cached_entities", fuel)
        self.assertNotIn("find_entities_filtered", fuel)

    def test_cache_snaps_origin_and_lives_across_ticks(self):
        helper = MAINTAIN[
            MAINTAIN.index("function maintain.cached_entities") : MAINTAIN.index("function maintain.collect_ammo_jobs")
        ]
        self.assertIn("storage.maintain_scan", helper)
        self.assertIn("SCAN_SNAP", helper)
        self.assertIn("SCAN_CACHE_TICKS", helper)
        self.assertGreaterEqual(
            int(__import__("re").search(r"SCAN_CACHE_TICKS = (\d+)", MAINTAIN).group(1)),
            60,
        )

    def test_repair_scan_is_not_repeated_in_one_call(self):
        collect = MAINTAIN[
            MAINTAIN.index("function maintain.collect_repair_jobs") : MAINTAIN.index("local function bot_item_count")
        ]
        self.assertEqual(collect.count("maintain.cached_entities"), 1)
        self.assertNotIn("find_entities_filtered", collect)

    def test_list_bots_reuses_fleet_cache(self):
        list_fn = MAINTAIN[
            MAINTAIN.index("function maintain.list_bots") : MAINTAIN.index("function maintain.list_mode_bots")
        ]
        self.assertIn("inventory.list_force_bots", list_fn)
        self.assertNotIn("find_entities_filtered", list_fn)

    def test_tick_player_lists_bots_once(self):
        tick = AI[AI.index("function ai.tick_player") :]
        self.assertLessEqual(tick.count("maintain.list_mode_bots"), 1)
        self.assertIn("maintain.list_bots", tick)


if __name__ == "__main__":
    unittest.main()

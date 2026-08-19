"""Dispatch tick must not rescan the map once per bot."""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
AI = (ROOT / "scripts" / "ai.lua").read_text(encoding="utf-8")
INV = (ROOT / "scripts" / "inventory.lua").read_text(encoding="utf-8")
CRAFT = (ROOT / "scripts" / "craft.lua").read_text(encoding="utf-8")
BUILDER = (ROOT / "scripts" / "builder.lua").read_text(encoding="utf-8")


class DispatchHotPathTest(unittest.TestCase):
    def test_process_job_does_not_refresh_every_bot(self):
        process = AI[AI.index("local function process_job") : AI.index("function ai.tick_player")]
        self.assertNotIn("builder.refresh_job_ghosts(player, job)", process)
        self.assertNotIn("builder.refresh_marked(player, job)", process)

    def test_tick_player_refreshes_once(self):
        tick = AI[AI.index("function ai.tick_player") :]
        self.assertEqual(tick.count("builder.refresh_job_ghosts(player, job)"), 1)
        self.assertEqual(tick.count("builder.refresh_marked(player, job)"), 1)
        refresh = tick.index("builder.refresh_job_ghosts(player, job)")
        workers = tick.index("for _, worker in ipairs(build_bots)")
        self.assertLess(refresh, workers)

    def test_fleet_list_is_cached(self):
        self.assertIn("function inventory.list_force_bots", INV)
        list_fn = INV[INV.index("function inventory.list_force_bots") : INV.index("function inventory.scan_available")]
        self.assertIn("storage.fleet_cache", list_fn)
        self.assertIn("cache.tick == game.tick", list_fn)

    def test_scan_available_is_cached(self):
        scan = INV[INV.index("function inventory.scan_available") :]
        self.assertIn("storage.scan_cache", scan)

    def test_ore_search_uses_limit(self):
        find = CRAFT[CRAFT.index("function craft.find_nearest_resource") : CRAFT.index("function craft.mine_resource")]
        self.assertIn("limit = 1", find)
        self.assertNotIn("radii = {80, 320, 1280, 4096}", find)

    def test_tree_search_uses_limit(self):
        find = CRAFT[CRAFT.index("function craft.find_nearest_tree") : CRAFT.index("function craft.search_origin")]
        self.assertIn("limit = 1", find)
        self.assertNotIn("radius = 2048", find)

    def test_revive_uses_cached_have_map(self):
        revive = BUILDER[BUILDER.index("function builder.revive_batch") :]
        self.assertIn("util.get_count(have_map", revive)
        self.assertNotIn("inventory.count_fleet_item(player, item_name)", revive)

    def test_build_runs_after_maintain_same_tick(self):
        tick = AI[AI.index("function ai.tick_player") :]
        build_loop = tick.index("for _, worker in ipairs(build_bots)")
        maintain_loop = tick.index("maintain.tick")
        self.assertLess(build_loop, maintain_loop)
        self.assertIn('store.last_status = "build"', tick)


if __name__ == "__main__":
    unittest.main()

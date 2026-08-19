"""Planning drag-place, underground pairing, and shared bot stock."""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
GUI = (ROOT / "scripts" / "gui.lua").read_text(encoding="utf-8")
PLAN = (ROOT / "scripts" / "plan.lua").read_text(encoding="utf-8")
INV = (ROOT / "scripts" / "inventory.lua").read_text(encoding="utf-8")
BUILDER = (ROOT / "scripts" / "builder.lua").read_text(encoding="utf-8")
CRAFT = (ROOT / "scripts" / "craft.lua").read_text(encoding="utf-8")
AI = (ROOT / "scripts" / "ai.lua").read_text(encoding="utf-8")
CONTROL = (ROOT / "control.lua").read_text(encoding="utf-8")


class DragPlaceTest(unittest.TestCase):
    def test_planner_puts_a_stack_not_one_item(self):
        self.assertIn("local PLAN_STACK = 100", GUI)
        self.assertIn("cursor.set_stack({name = item_name, count = count})", GUI)
        self.assertNotIn("set_stack({name = item_name, count = 1})", GUI)

    def test_restore_waits_until_cursor_empty_not_next_tick(self):
        self.assertIn("function gui.schedule_plan_restore", GUI)
        self.assertNotRegex(
            GUI,
            r"store\.plan_restore_tick = game\.tick \+ 1",
        )
        self.assertIn("store.plan_hold", GUI)

    def test_same_tile_ghost_is_not_duplicated(self):
        self.assertIn("function plan.existing_plan_ghost", PLAN)
        convert = PLAN[PLAN.index("function plan.convert_built_to_ghost") :]
        self.assertIn("plan.existing_plan_ghost", convert)
        self.assertIn("entity.destroy", convert)


class UndergroundPairTest(unittest.TestCase):
    def test_pair_types_wait_for_idle(self):
        self.assertIn('["pipe-to-ground"] = true', PLAN)
        self.assertIn('["underground-belt"] = true', PLAN)
        self.assertGreaterEqual(
            int(re.search(r"PAIR_IDLE_TICKS = (\d+)", PLAN).group(1)),
            20,
        )

    def test_pair_queue_converts_batch_after_idle(self):
        flush = PLAN[PLAN.index("function plan.flush_pair_queue") :]
        self.assertIn("PAIR_IDLE_TICKS", flush)
        self.assertIn("plan.convert_built_to_ghost", flush)

    def test_underground_ghost_keeps_belt_type(self):
        convert = PLAN[PLAN.index("function plan.convert_built_to_ghost") :]
        self.assertIn("belt_to_ground_type", convert)
        self.assertIn("type = info.belt_type", convert)


class SharedStockTest(unittest.TestCase):
    def test_scan_includes_all_force_bots(self):
        self.assertIn("function inventory.list_force_bots", INV)
        self.assertIn("function inventory.scan_available", INV)
        scan = INV[INV.index("function inventory.scan_available") :]
        self.assertIn("inventory.list_force_bots", scan)

    def test_collect_and_remove_use_fleet(self):
        self.assertIn("function inventory.try_remove_from_fleet", INV)
        collect = INV[INV.index("function inventory.collect_items") :]
        self.assertIn("inventory.list_force_bots", collect)
        self.assertIn("inventory.try_remove_from_fleet", BUILDER)
        self.assertIn("inventory.scan_available", BUILDER)

    def test_craft_and_build_see_other_bots(self):
        self.assertIn("inventory.count_fleet_item", CRAFT)
        self.assertIn("inventory.try_remove_from_fleet", CRAFT)
        self.assertIn("inventory.scan_available", AI)


if __name__ == "__main__":
    unittest.main()

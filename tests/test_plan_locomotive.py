"""Planning ghosts must keep locomotive orientation, not reset to north."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
PLAN = (ROOT / "scripts" / "plan.lua").read_text(encoding="utf-8")


class LocomotiveGhostOrientationTest(unittest.TestCase):
    def test_convert_does_not_pass_orientation_to_create(self):
        convert = PLAN[PLAN.index("function plan.convert_built_to_ghost") :]
        create = convert[convert.index("surface.create_entity") : convert.index("if ghost and ghost.valid")]
        self.assertNotIn("orientation = info.orientation", create)

    def test_convert_sets_ghost_direction_after_create(self):
        convert = PLAN[PLAN.index("function plan.convert_built_to_ghost") :]
        self.assertIn("ghost.direction = facing", convert)
        self.assertIn("from_orientation", convert)

    def test_pre_build_facing_is_remembered(self):
        self.assertIn("function plan.remember_build", PLAN)
        self.assertIn("plan_build", PLAN)

    def test_same_tile_ghost_is_replaced(self):
        convert = PLAN[PLAN.index("function plan.convert_built_to_ghost") :]
        self.assertIn("existing.destroy", convert)


if __name__ == "__main__":
    unittest.main()

"""Maintain bots must lock a target and refill ammo they already hold."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
MAINTAIN = (ROOT / "scripts" / "maintain.lua").read_text(encoding="utf-8")
BUILDER = (ROOT / "scripts" / "builder.lua").read_text(encoding="utf-8")


class MaintainOscillationTest(unittest.TestCase):
    def test_ammo_inserts_before_mining(self):
        tick = MAINTAIN[MAINTAIN.index("local function tick_ammo") : MAINTAIN.index("local function insert_fuel")]
        have = tick.index("bot_item_count")
        mine = tick.index("craft_into_bot")
        self.assertLess(have, mine)

    def test_ammo_locks_current_turret(self):
        self.assertIn("state.current_turret", MAINTAIN)
        tick = MAINTAIN[MAINTAIN.index("local function tick_ammo") : MAINTAIN.index("local function insert_fuel")]
        self.assertIn("state.current_turret", tick)

    def test_follow_locked_mines_when_close(self):
        follow = MAINTAIN[MAINTAIN.index("local function follow_locked") : MAINTAIN.index("local function sort_jobs_by_distance")]
        self.assertNotIn("state.mine_target = nil", follow.split("if util.distance")[0])

    def test_move_bot_does_not_stop_same_dest(self):
        move = BUILDER[BUILDER.index("function builder.move_bot") : BUILDER.index("function builder.bot_in_range")]
        self.assertNotIn("stop_spider", move)
        self.assertIn("util.distance(current, dest)", move)


if __name__ == "__main__":
    unittest.main()

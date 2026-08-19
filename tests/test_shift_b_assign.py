"""Shift+B must always print and still enqueue a build job while maintain bots work."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
PLAN = (ROOT / "scripts" / "plan.lua").read_text(encoding="utf-8")
ZH = (ROOT / "locale" / "zh-CN" / "locale.cfg").read_text(encoding="utf-8")


class ShiftBAssignTest(unittest.TestCase):
    def test_toggle_always_prints(self):
        toggle = PLAN[PLAN.index("function plan.toggle_assign") : PLAN.index("function plan.assign_nearby")]
        self.assertNotIn("plan.nudge_assign(player)\n    return", toggle)
        self.assertIn("plan.assign_nearby", toggle)

    def test_assign_enqueues_without_build_bots(self):
        assign = PLAN[PLAN.index("function plan.assign_nearby") :]
        no_builder = assign.index('player.print({"ai-bot.no-build-bot"})')
        insert = assign.index("table.insert(store.queue, job)")
        self.assertLess(insert, no_builder)

    def test_nudge_prints(self):
        nudge = PLAN[PLAN.index("function plan.nudge_assign") : PLAN.index("function plan.toggle_assign")]
        self.assertIn('"ai-bot.job-nudged"', nudge)

    def test_locale_has_nudge_line(self):
        self.assertIn("job-nudged=", ZH)


if __name__ == "__main__":
    unittest.main()

"""Planning mode right-click must remove a ghost even with an item in hand."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
PLAN = (ROOT / "scripts" / "plan.lua").read_text(encoding="utf-8")
CONTROL = (ROOT / "control.lua").read_text(encoding="utf-8")
DATA = (ROOT / "data.lua").read_text(encoding="utf-8")
ZH = (ROOT / "locale" / "zh-CN" / "locale.cfg").read_text(encoding="utf-8")


class PlanCancelGhostTest(unittest.TestCase):
    def test_cancel_helper_exists(self):
        self.assertIn("function plan.cancel_selected_ghost", PLAN)
        self.assertIn("selected.destroy", PLAN)

    def test_control_listens_for_mine(self):
        self.assertIn("ai-bot-plan-mine", CONTROL)
        self.assertIn("plan.cancel_selected_ghost", CONTROL)

    def test_custom_input_uses_mine(self):
        self.assertIn('name = "ai-bot-plan-mine"', DATA)
        self.assertIn('linked_game_control = "mine"', DATA)
        self.assertIn('consuming = "game-only"', DATA)

    def test_locale_mentions_right_click(self):
        self.assertIn("planner-hint", ZH)
        self.assertIn("右键", ZH)


if __name__ == "__main__":
    unittest.main()

"""Regression: red-marked buildings must be mined before a plan job finishes.

A Shift+B job with 0 ghosts and N deconstruction marks used to hit the
"planning ghosts are gone, finish" branch and never call deconstruct.
"""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
AI_LUA = (ROOT / "scripts" / "ai.lua").read_text(encoding="utf-8")
BUILDER_LUA = (ROOT / "scripts" / "builder.lua").read_text(encoding="utf-8")
PLAN_LUA = (ROOT / "scripts" / "plan.lua").read_text(encoding="utf-8")


def job_has_work(job):
    """Python mirror of builder.job_has_work."""
    for ghost in job.get("ghosts") or []:
        if ghost.get("valid", True):
            return True
    for entity in job.get("marked") or []:
        if entity.get("valid", True):
            return True
    return False


def decide_after_refresh(job):
    """Mirror of the process_job gate after ghosts/marks are refreshed."""
    if job_has_work(job):
        if job.get("marked"):
            return "deconstruct"
        return "build"
    if job.get("export"):
        return "place"
    return "finish"


class DeconstructJobDecisionTest(unittest.TestCase):
    def test_deconstruct_only_job_is_not_finished(self):
        job = {
            "ghosts": [],
            "marked": [{"valid": True, "name": "transport-belt"}],
            "export": None,
            "placed": False,
        }
        self.assertTrue(job_has_work(job))
        self.assertEqual(decide_after_refresh(job), "deconstruct")

    def test_empty_plan_job_finishes(self):
        job = {"ghosts": [], "marked": [], "export": None, "placed": False}
        self.assertFalse(job_has_work(job))
        self.assertEqual(decide_after_refresh(job), "finish")

    def test_invalid_marks_do_not_count(self):
        job = {
            "ghosts": [],
            "marked": [{"valid": False}],
            "export": None,
        }
        self.assertFalse(job_has_work(job))
        self.assertEqual(decide_after_refresh(job), "finish")

    def test_ghosts_still_build(self):
        job = {
            "ghosts": [{"valid": True}],
            "marked": [],
            "export": None,
        }
        self.assertEqual(decide_after_refresh(job), "build")

    def test_export_without_work_tries_place(self):
        job = {"ghosts": [], "marked": [], "export": "bp"}
        self.assertEqual(decide_after_refresh(job), "place")


class SourceContractTest(unittest.TestCase):
    def test_builder_exposes_job_has_work(self):
        self.assertIn("function builder.job_has_work(job)", BUILDER_LUA)

    def test_process_job_refreshes_marks_before_empty_finish(self):
        start = AI_LUA.index("function process_job")
        body = AI_LUA[start:]
        refresh = body.index("builder.refresh_marked")
        has_work = body.index("builder.job_has_work")
        finish = body.index('finish_job(player, store, job, "done")')
        self.assertLess(refresh, has_work)
        self.assertLess(has_work, finish)

    def test_old_empty_ghost_shortcut_is_gone(self):
        self.assertNotIn("规划任务幽灵已被建完或被其他机器人建掉，直接收尾", AI_LUA)

    def test_nearest_work_includes_marked(self):
        self.assertIn("function builder.nearest_work_position", BUILDER_LUA)
        self.assertIn("builder.nearest_work_position", AI_LUA)

    def test_plan_job_keeps_marked_list(self):
        self.assertIn("marked = marked", PLAN_LUA)


if __name__ == "__main__":
    unittest.main()

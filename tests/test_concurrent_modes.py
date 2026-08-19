"""Maintain and build bots must share the same tick."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
AI = (ROOT / "scripts" / "ai.lua").read_text(encoding="utf-8")
MAINTAIN = (ROOT / "scripts" / "maintain.lua").read_text(encoding="utf-8")


class ConcurrentModesTest(unittest.TestCase):
    def test_tick_does_not_return_after_maintain(self):
        tick = AI[AI.index("function ai.tick_player") :]
        build_loop = tick.index("for _, worker in ipairs(build_bots)")
        maintain_loop = tick.index("maintain.tick")
        self.assertLess(build_loop, maintain_loop)
        after_maintain = tick[maintain_loop:]
        self.assertNotIn("return", after_maintain.split("function ai.on_tick", 1)[0])

    def test_active_job_keeps_build_status(self):
        tick = AI[AI.index("function ai.tick_player") :]
        self.assertIn('store.last_status = "build"', tick)
        self.assertLess(
            tick.index('store.last_status = "build"'),
            tick.index("maintain.tick"),
        )

    def test_repair_scan_is_bounded(self):
        collect = MAINTAIN[MAINTAIN.index("function maintain.collect_repair_jobs") :]
        self.assertNotIn("radius = 4096", collect)
        self.assertIn("maintain.cached_entities", collect)
        self.assertIn("DEFAULT_JOB_RADIUS", MAINTAIN)

    def test_ammo_scan_is_bounded(self):
        collect = MAINTAIN[MAINTAIN.index("function maintain.collect_ammo_jobs") :]
        self.assertIn("maintain.cached_entities", collect)
        self.assertNotIn("radius = 4096", collect)


if __name__ == "__main__":
    unittest.main()

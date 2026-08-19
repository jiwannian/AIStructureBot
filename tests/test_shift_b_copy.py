"""Shift+B copy must say nudge, not stop."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
ZH = (ROOT / "locale" / "zh-CN" / "locale.cfg").read_text(encoding="utf-8")
README = (ROOT / "README.md").read_text(encoding="utf-8")


class ShiftBCopyTest(unittest.TestCase):
    def test_locale_says_nudge_not_stop(self):
        self.assertIn("派工 / 催工", ZH)
        self.assertIn("停止请点菜单「停止派工」", ZH)
        self.assertNotIn("再按一次是停止", ZH)

    def test_readme_says_nudge_not_stop(self):
        self.assertIn("再按一次 `Shift+B` 是催工", README)
        self.assertIn("停止请点菜单「停止派工」", README)
        self.assertNotIn("再按一次 `Shift+B` 停止", README)


if __name__ == "__main__":
    unittest.main()

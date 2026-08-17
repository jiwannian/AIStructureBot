"""Blueprint library: website categories stay, planner entry stamps freely."""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
DATA = (ROOT / "scripts" / "library_data.lua").read_text(encoding="utf-8")
LIB = (ROOT / "scripts" / "library.lua").read_text(encoding="utf-8")
GUI = (ROOT / "scripts" / "gui.lua").read_text(encoding="utf-8")
CONTROL = (ROOT / "control.lua").read_text(encoding="utf-8")
ZH = (ROOT / "locale" / "zh-CN" / "locale.cfg").read_text(encoding="utf-8")

EXPECTED_CATEGORIES = [
    "蓝图簿",
    "超市模块",
    "生产模块",
    "科研模块",
    "其他模块",
    "物流模块",
    "石墙结构",
]

EXPECTED_COUNTS = {
    "蓝图簿": 1,
    "超市模块": 2,
    "生产模块": 20,
    "科研模块": 4,
    "其他模块": 1,
    "物流模块": 1,
    "石墙结构": 6,
}

EXPECTED_NAMES = [
    "蓝图簿",
    "模块::超市",
    "超市扩展::绿瓶",
    "速度插件1工厂",
    "节能插件1工厂",
    "产能插件1工厂",
    "速度插件1工厂2",
    "节能插件1工厂2",
    "产能插件1工厂2",
    "速度插件2工厂",
    "节能插件2工厂",
    "产能插件2工厂",
    "模块::电路板工厂",
    "模块::集成电路工厂",
    "模块::处理器工厂",
    "模块::石油气工厂",
    "模块::硫酸工厂",
    "模块::塑料工厂",
    "模块::电池工厂",
    "模块::钢材工厂",
    "模块::铁板工厂",
    "模块::铜板工厂",
    "模块::石砖工厂",
    "模块::绿瓶工厂",
    "模块::蓝瓶工厂",
    "模块::紫瓶工厂",
    "模块::黄瓶工厂",
    "模块::机器人工厂",
    "物流::总线3x4+8",
    "结构::石墙(内侧)",
    "结构::石墙(外侧1)",
    "结构::石墙(外侧2)",
    "结构::半格石墙(内侧)",
    "结构::半格石墙(外侧1)",
    "结构::半格石墙(外侧2)",
]


def parse_library_data(text):
    cats = re.findall(r'category = "([^"]+)"', text)
    names = re.findall(r'name = "([^"]+)"', text)
    exports = re.findall(r"export = \[\[(0eN[0-9A-Za-z+/=]+)\]\]", text)
    return list(zip(cats, names, exports))


class LibraryDataTest(unittest.TestCase):
    def setUp(self):
        self.rows = parse_library_data(DATA)

    def test_imports_all_site_blueprints(self):
        self.assertEqual(len(self.rows), 35)
        self.assertEqual([row[1] for row in self.rows], EXPECTED_NAMES)

    def test_keeps_website_category_order(self):
        cats = []
        for cat, _, _ in self.rows:
            if cat not in cats:
                cats.append(cat)
        self.assertEqual(cats, EXPECTED_CATEGORIES)
        counts = {}
        for cat, _, _ in self.rows:
            counts[cat] = counts.get(cat, 0) + 1
        self.assertEqual(counts, EXPECTED_COUNTS)

    def test_exports_look_like_factorio_strings(self):
        for _, name, export in self.rows:
            self.assertTrue(export.startswith("0eN"), name)
            self.assertGreater(len(export), 200, name)


class LibraryUiContractTest(unittest.TestCase):
    def test_planner_entry_still_uses_old_button(self):
        self.assertIn('name = "ai_bot_lineplan"', GUI)
        self.assertIn("ai-bot.lineplan-open", GUI)
        self.assertIn("lineplan-open=蓝图库", ZH)

    def test_library_module_exposes_catalog(self):
        self.assertIn("function library.categories()", LIB)
        self.assertIn("function library.entries(", LIB)
        self.assertIn("function library.put_on_cursor(", LIB)
        self.assertIn('require("scripts.library_data")', LIB)

    def test_clicking_library_item_puts_blueprint_on_cursor(self):
        self.assertIn("gui.give_library_blueprint", GUI)
        self.assertIn("gui.give_library_blueprint", CONTROL)
        self.assertIn("ai_bot_lib_id", CONTROL)

    def test_restore_keeps_library_blueprint_after_place(self):
        self.assertIn("store.lib_export", GUI)
        self.assertIn("is_blueprint_book", GUI)
        self.assertIn("function gui.schedule_plan_restore", GUI)
        self.assertIn("gui.flush_plan_restore", CONTROL)

    def test_filter_keeps_category_and_name(self):
        self.assertIn("string.find(category, needle, 1, true)", LIB)
        self.assertIn("string.find(name, needle, 1, true)", LIB)


if __name__ == "__main__":
    unittest.main()

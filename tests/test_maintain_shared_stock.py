"""Maintain refill must use the shared fleet trunk, not only this bot."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
MAINTAIN = (ROOT / "scripts" / "maintain.lua").read_text(encoding="utf-8")


class SharedStockTest(unittest.TestCase):
    def test_count_uses_fleet(self):
        helper = MAINTAIN[MAINTAIN.index("local function bot_item_count") : MAINTAIN.index("local function take_from_bot")]
        self.assertIn("inventory.count_fleet_item", helper)

    def test_take_uses_fleet(self):
        helper = MAINTAIN[MAINTAIN.index("local function take_from_bot") : MAINTAIN.index("local function give_to_bot")]
        self.assertIn("inventory.try_remove_from_fleet", helper)

    def test_tick_ammo_counts_with_player(self):
        tick = MAINTAIN[MAINTAIN.index("local function tick_ammo") : MAINTAIN.index("local function insert_fuel")]
        self.assertIn("bot_item_count(player, bot, job.ammo)", tick)
        self.assertIn("take_from_bot(player, bot, job.ammo", tick)

    def test_tick_fuel_counts_with_player(self):
        tick = MAINTAIN[MAINTAIN.index("local function tick_fuel") : MAINTAIN.index("local function tick_repair")]
        self.assertIn("bot_item_count(player, bot, job.fuel)", tick)
        self.assertIn("take_from_bot(player, bot, job.fuel", tick)

    def test_default_gun_turret_keeps_magazine(self):
        rule = MAINTAIN[MAINTAIN.index("function maintain.default_rule") : MAINTAIN.index("function maintain.list_bots")]
        self.assertIn('ammo = ammo or preset.ammo', rule)


if __name__ == "__main__":
    unittest.main()

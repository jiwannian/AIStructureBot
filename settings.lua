-- 启动项 / 地图 / 玩家设置。菜单设置页会读写这些值。
data:extend({
  {
    type = "int-setting",
    name = "ai-bot-tick-interval",
    setting_type = "runtime-global",
    minimum_value = 10,
    maximum_value = 300,
    default_value = 30,
    order = "a"
  },
  {
    type = "int-setting",
    name = "ai-bot-build-batch",
    setting_type = "runtime-global",
    minimum_value = 1,
    maximum_value = 50,
    default_value = 8,
    order = "b"
  },
  {
    type = "int-setting",
    name = "ai-bot-search-radius",
    setting_type = "runtime-per-user",
    minimum_value = 64,
    maximum_value = 2048,
    default_value = 512,
    order = "c"
  },
  {
    type = "int-setting",
    name = "ai-bot-job-radius",
    setting_type = "runtime-per-user",
    minimum_value = 32,
    maximum_value = 4096,
    default_value = 256,
    order = "c2"
  },
  {
    type = "int-setting",
    name = "ai-bot-warn-threshold",
    setting_type = "runtime-per-user",
    minimum_value = 0,
    maximum_value = 10000,
    default_value = 20,
    order = "d"
  },
  {
    type = "int-setting",
    name = "ai-bot-reserve-stock",
    setting_type = "runtime-per-user",
    minimum_value = 0,
    maximum_value = 10000,
    default_value = 50,
    order = "e"
  },
  {
    type = "int-setting",
    name = "ai-bot-work-range",
    setting_type = "runtime-per-user",
    minimum_value = 8,
    maximum_value = 64,
    default_value = 24,
    order = "f"
  },
  {
    type = "bool-setting",
    name = "ai-bot-auto-start",
    setting_type = "runtime-per-user",
    default_value = false,
    order = "g"
  },
  {
    type = "bool-setting",
    name = "ai-bot-force-build",
    setting_type = "runtime-per-user",
    default_value = false,
    order = "h"
  },
  {
    type = "bool-setting",
    name = "ai-bot-take-from-network",
    setting_type = "runtime-per-user",
    default_value = false,
    order = "i"
  },
  {
    type = "bool-setting",
    name = "ai-bot-take-from-player",
    setting_type = "runtime-per-user",
    default_value = true,
    order = "j"
  },
  {
    type = "int-setting",
    name = "ai-bot-wait-timeout",
    setting_type = "runtime-per-user",
    minimum_value = 10,
    maximum_value = 3600,
    default_value = 180,
    order = "k"
  }
})

-- 原型：AI Bot 单位、工具栏快捷方式、热键、选择工具。
-- 不 require 原版 entities.lua，避免重复注册蜘蛛机甲。
local robot_icon = "__base__/graphics/icons/construction-robot.png"
local spider_icon = "__base__/graphics/icons/spidertron.png"

local function copy_named(proto, new_name)
  local copy = table.deepcopy(proto)
  copy.name = new_name
  return copy
end

-- 复制蜘蛛机甲本体与 8 条腿，作为可操控 AI Bot。
local bot_entity = copy_named(data.raw["spider-vehicle"]["spidertron"], "ai-structure-bot")
bot_entity.localised_name = {"entity-name.ai-structure-bot"}
bot_entity.localised_description = {"entity-description.ai-structure-bot"}
bot_entity.minable = {mining_time = 1, result = "ai-structure-bot"}
bot_entity.icon = spider_icon
bot_entity.guns = nil
bot_entity.is_military_target = false
bot_entity.automatic_weapon_cycling = false
bot_entity.allow_remote_driving = true
if bot_entity.flags then
  local has_not_in_kill = false
  for _, flag in pairs(bot_entity.flags) do
    if flag == "not-in-kill-statistics" then
      has_not_in_kill = true
    end
  end
end
bot_entity.chunk_exploration_radius = 4
if bot_entity.inventory_size and bot_entity.inventory_size < 80 then
  bot_entity.inventory_size = 80
end

local extra_entities = {bot_entity}
if bot_entity.spider_engine and bot_entity.spider_engine.legs then
  for index, leg in pairs(bot_entity.spider_engine.legs) do
    local old_leg = leg.leg
    local new_leg = "ai-structure-bot-leg-" .. tostring(index)
    local leg_proto = data.raw["spider-leg"][old_leg]
    if leg_proto then
      local copied_leg = copy_named(leg_proto, new_leg)
      copied_leg.hidden = true
      table.insert(extra_entities, copied_leg)
      leg.leg = new_leg
    end
  end
end

local bot_item = copy_named(data.raw["item-with-entity-data"]["spidertron"], "ai-structure-bot")
bot_item.localised_name = {"entity-name.ai-structure-bot"}
bot_item.localised_description = {"entity-description.ai-structure-bot"}
bot_item.icon = spider_icon
bot_item.place_result = "ai-structure-bot"
bot_item.order = "b[personal-transport]-c[spidertron]-b[ai-structure-bot]"
bot_item.subgroup = "transport"
bot_item.stack_size = 1

local bot_recipe = table.deepcopy(data.raw.recipe.spidertron)
bot_recipe.name = "ai-structure-bot"
bot_recipe.localised_name = {"entity-name.ai-structure-bot"}
bot_recipe.enabled = true
bot_recipe.results = {{type = "item", name = "ai-structure-bot", amount = 1}}
bot_recipe.ingredients = {
  {type = "item", name = "construction-robot", amount = 10},
  {type = "item", name = "logistic-robot", amount = 10},
  {type = "item", name = "roboport", amount = 1},
  {type = "item", name = "advanced-circuit", amount = 20},
  {type = "item", name = "steel-plate", amount = 40},
  {type = "item", name = "iron-gear-wheel", amount = 40}
}

local bot_tech = {
  type = "technology",
  name = "ai-structure-bot",
  localised_name = {"technology-name.ai-structure-bot"},
  localised_description = {"technology-description.ai-structure-bot"},
  icon = "__base__/graphics/technology/construction-robotics.png",
  icon_size = 256,
  effects = {
    {type = "unlock-recipe", recipe = "ai-structure-bot"}
  },
  prerequisites = {"construction-robotics", "logistic-robotics"},
  unit = {
    count = 200,
    ingredients = {
      {"automation-science-pack", 1},
      {"logistic-science-pack", 1},
      {"chemical-science-pack", 1}
    },
    time = 30
  },
  order = "c-k-a-ai-bot"
}

data.raw["gui-style"]["default"].ai_bot_click_catcher = {
  type = "button_style",
  parent = "button",
  padding = 0,
  margin = 0,
  default_graphical_set = {},
  hovered_graphical_set = {},
  clicked_graphical_set = {},
  disabled_graphical_set = {},
  default_font_color = {0, 0, 0, 0},
  hovered_font_color = {0, 0, 0, 0},
  clicked_font_color = {0, 0, 0, 0},
  clicked_vertical_offset = 0,
  left_click_sound = {}
}

data:extend(extra_entities)
data:extend({
  bot_item,
  bot_recipe,
  bot_tech,
  {
    type = "selection-tool",
    name = "ai-bot-assign-tool",
    icons = {{icon = robot_icon, icon_size = 64}},
    flags = {"not-stackable", "only-in-cursor", "spawnable"},
    hidden = true,
    subgroup = "tool",
    order = "c[automated-construction]-e[ai-bot-assign]",
    stack_size = 1,
    select = {
      border_color = {r = 0.15, g = 0.85, b = 0.35},
      cursor_box_type = "entity",
      mode = {"any-entity"}
    },
    alt_select = {
      border_color = {r = 0.85, g = 0.55, b = 0.15},
      cursor_box_type = "copy",
      mode = {"any-entity"}
    }
  },
  {
    type = "custom-input",
    name = "ai-bot-toggle-menu",
    key_sequence = "F1",
    consuming = "none",
    action = "lua",
    localised_name = {"controls.ai-bot-toggle-menu"}
  },
  {
    type = "custom-input",
    name = "ai-bot-close-menu",
    key_sequence = "ESCAPE",
    consuming = "none",
    action = "lua",
    localised_name = {"controls.ai-bot-close-menu"}
  },
  {
    type = "custom-input",
    name = "ai-bot-toggle-plan",
    key_sequence = "SHIFT + P",
    consuming = "none",
    action = "lua",
    localised_name = {"controls.ai-bot-toggle-plan"}
  },
  {
    type = "custom-input",
    name = "ai-bot-assign-ghosts",
    key_sequence = "SHIFT + B",
    consuming = "none",
    action = "lua",
    localised_name = {"controls.ai-bot-assign-ghosts"}
  },
  {
    type = "shortcut",
    name = "ai-bot-toggle-plan",
    action = "lua",
    associated_control_input = "ai-bot-toggle-plan",
    toggleable = true,
    icon = "__base__/graphics/icons/blueprint.png",
    icon_size = 64,
    small_icon = "__base__/graphics/icons/blueprint.png",
    small_icon_size = 64,
    style = "blue",
    localised_name = {"shortcut-name.ai-bot-toggle-plan"}
  },
  {
    type = "shortcut",
    name = "ai-bot-open-menu",
    action = "lua",
    associated_control_input = "ai-bot-toggle-menu",
    toggleable = true,
    icon = robot_icon,
    icon_size = 64,
    small_icon = robot_icon,
    small_icon_size = 64,
    style = "green",
    localised_name = {"shortcut-name.ai-bot-open-menu"}
  }
})

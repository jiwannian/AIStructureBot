-- 规划模式蓝图库：按 ControlNet 站点目录分类，点选后放到光标自由盖章。
local blueprint = require("scripts.blueprint")
local data = require("scripts.library_data")

local library = {}

function library.all()
  return data
end

function library.categories()
  local seen = {}
  local list = {}
  for _, item in ipairs(data) do
    if item.category and not seen[item.category] then
      seen[item.category] = true
      table.insert(list, item.category)
    end
  end
  return list
end

function library.get(index)
  return data[index]
end

function library.matches(item, filter)
  if not filter or filter == "" then
    return true
  end
  local needle = string.lower(filter)
  local name = string.lower(item.name or "")
  local category = string.lower(item.category or "")
  return string.find(name, needle, 1, true) or string.find(category, needle, 1, true)
end

function library.entries(category, filter)
  local list = {}
  for index, item in ipairs(data) do
    if (not category or category == "" or item.category == category) and library.matches(item, filter) then
      table.insert(list, {
        id = index,
        name = item.name,
        category = item.category,
        export = item.export
      })
    end
  end
  return list
end

function library.put_on_cursor(player, index)
  local item = library.get(index)
  if not item or not item.export then
    return false
  end
  return blueprint.put_on_cursor(player, item.export), item
end

return library

local nui = require("ya-tree.ui.nui")
local hl = require("ya-tree.ui.highlights")
local utils = require("ya-tree.utils")

local api = vim.api

local M = {}

local KEYS_SECTION_WIDTH = 15

--Sort by description.
---@param a { key: string, action: Yat.Actions.Name|Yat.Config.Mapping.Custom, desc: string }
---@param b { key: string, action: Yat.Actions.Name|Yat.Config.Mapping.Custom, desc: string }
---@return boolean
local function mapping_sorter(a, b)
  local atype = type(a.action)
  local btype = type(b.action)
  if atype == "string" and btype == "table" then
    return false
  elseif atype == "table" and btype == "string" then
    return true
  end
  return a.desc < b.desc
end

---@param mappings table<string, Yat.Actions.Name|""|Yat.Config.Mapping.Custom>
---@return { key: string, action: Yat.Actions.Name|""|Yat.Config.Mapping.Custom, desc: string }[] insert_mappings
---@return { key: string, action: Yat.Actions.Name|""|Yat.Config.Mapping.Custom, desc: string }[] visual_mappings
---@return integer max_mapping_width
---@return string[] close_keys
local function parse_mappings(mappings)
  local actions = require("ya-tree.actions")._actions
  local max_mapping_width = 0
  local close_keys = { "q", "<ESC>" }

  ---@type { key: string, action: Yat.Actions.Name|Yat.Config.Mapping.Custom, desc: string }[], { key: string, action: Yat.Actions.Name|Yat.Config.Mapping.Custom, desc: string }[]
  local insert, visual = {}, {}
  for key, mapping in pairs(mappings) do
    if mapping ~= "" then
      local modes, desc
      if type(mapping) == "string" then
        local action = actions[mapping]
        modes = action and action.modes or {}
        desc = actions[mapping].desc or mapping
      else
        ---@cast mapping Yat.Config.Mapping.Custom
        modes = mapping.modes or {}
        desc = mapping.desc or "User '<function>'"
      end
      if vim.tbl_contains(modes, "n") then
        insert[#insert + 1] = { key = key, action = mapping, desc = desc }
      end
      for _, mode in ipairs(modes) do
        if mode == "v" or mode == "V" then
          visual[#visual + 1] = { key = key, action = mapping, desc = desc }
          break
        end
      end

      max_mapping_width = math.max(max_mapping_width, api.nvim_strwidth(desc))
      if mapping == "open_help" then
        close_keys[#close_keys + 1] = key
      end
    end
  end

  table.sort(insert, mapping_sorter)
  table.sort(visual, mapping_sorter)

  return insert, visual, max_mapping_width, close_keys
end

---@param format_string string
---@param current_tab integer
---@param all_tree_types Yat.Trees.Type[]
---@param width integer
---@return string[] lines
---@return Yat.Ui.HighlightGroup[][] highlight_groups
local function create_header(format_string, current_tab, all_tree_types, width)
  local tabs = {}
  local index = 1
  for _, tree_type in ipairs(all_tree_types) do
    tabs[#tabs + 1] = string.format(" (%s) %s ", index, tree_type)
    index = index + 1
  end
  local header = string.format("%" .. math.floor((width / 2) + 6) .. "s", "KEY MAPPINGS")
  local keys = "press <Tab>, <S-Tab> or <number> to navigate"
  local formatted_keys = string.format("%" .. math.floor((width / 2) + (#keys / 2)) .. "s", keys)
  local tabs_line = " " .. table.concat(tabs, " ")
  local legend = string.format(format_string, "Key", "Action", "Tree")
  local lines = { header, formatted_keys, "", tabs_line, "", legend, "", " Normal Mode:" }

  ---@type Yat.Ui.HighlightGroup[]
  local tabs_highligt_group = {}
  local current_startpos = 1
  for i, tab in ipairs(tabs) do
    local hl_name
    if i == current_tab then
      hl_name = hl.UI_CURRENT_TAB
    else
      hl_name = hl.UI_OTHER_TAB
    end
    tabs_highligt_group[#tabs_highligt_group + 1] = { name = hl_name, from = current_startpos, to = current_startpos + #tab }
    current_startpos = current_startpos + #tab + 1
  end

  local tab_start = formatted_keys:find("<Tab>", 1, true) - 1
  local stab_start = formatted_keys:find("<S-Tab>", 1, true) - 1
  local number_start = formatted_keys:find("<number>", 1, true) - 1

  ---@type Yat.Ui.HighlightGroup[][]
  local highlight_groups = {
    { { name = hl.ROOT_NAME, from = 0, to = -1 } },
    {
      { name = hl.DIM_TEXT, from = 0, to = tab_start },
      { name = hl.GIT_DIRTY, from = tab_start, to = tab_start + 5 },
      { name = hl.DIM_TEXT, from = tab_start + 6, to = stab_start },
      { name = hl.GIT_DIRTY, from = stab_start, to = stab_start + 7 },
      { name = hl.DIM_TEXT, from = stab_start + 8, to = number_start },
      { name = hl.GIT_DIRTY, from = number_start, to = number_start + 8 },
      { name = hl.DIM_TEXT, from = number_start + 9, to = -1 },
    },
    {},
    tabs_highligt_group,
    {},
    { { name = hl.SEARCH_TERM, from = 0, to = -1 } },
    {},
    { { name = hl.ROOT_NAME, from = 0, to = -1 } },
  }

  return lines, highlight_groups
end

---@param lines string[]
---@param highlight_groups Yat.Ui.HighlightGroup[][]
---@param format_string string
---@param insert { key: string, action: Yat.Actions.Name|Yat.Config.Mapping.Custom, desc: string }[]
---@param visual { key: string, action: Yat.Actions.Name|Yat.Config.Mapping.Custom, desc: string }[]
local function create_mappings_section(lines, highlight_groups, format_string, insert, visual)
  for _, v in ipairs(insert) do
    local line = string.format(format_string, v.key, v.desc)
    lines[#lines + 1] = line
    highlight_groups[#highlight_groups + 1] = {
      { name = hl.GIT_DIRTY, from = 0, to = KEYS_SECTION_WIDTH },
      { name = hl.SYMBOLIC_LINK_TARGET, from = KEYS_SECTION_WIDTH, to = -1 },
    }
  end

  lines[#lines + 1] = ""
  lines[#lines + 1] = " Visual Mode:"
  highlight_groups[#highlight_groups + 1] = {}
  highlight_groups[#highlight_groups + 1] = { { name = hl.ROOT_NAME, from = 0, to = -1 } }

  for _, v in ipairs(visual) do
    local line = string.format(format_string, v.key, v.desc)
    lines[#lines + 1] = line
    highlight_groups[#highlight_groups + 1] = {
      { name = hl.GIT_DIRTY, from = 0, to = KEYS_SECTION_WIDTH },
      { name = hl.SYMBOLIC_LINK_TARGET, from = KEYS_SECTION_WIDTH, to = -1 },
    }
  end
end

---@param all_tree_types Yat.Trees.Type[]
---@param mappings table<Yat.Trees.Type, table<string, Yat.Actions.Name|""|Yat.Config.Mapping.Custom>>
---@param current_tab integer
---@param width integer
---@return string[] lines
---@return Yat.Ui.HighlightGroup[][] highlight_groups
---@return string[] close_keys
local function render_mappings_for_for_tree(current_tab, all_tree_types, mappings, width)
  local tree_type = all_tree_types[current_tab]
  local current_mappings = mappings[tree_type]
  local insert, visual, max_mapping_width, close_keys = parse_mappings(current_mappings)

  local format_string = "%" .. KEYS_SECTION_WIDTH .. "s : %-" .. max_mapping_width .. "s " -- with trailing space to match the left side

  local lines, highlight_groups = create_header(format_string, current_tab, all_tree_types, width)
  create_mappings_section(lines, highlight_groups, format_string, insert, visual)

  return lines, highlight_groups, close_keys
end

---@async
---@param tree Yat.Tree
function M.open_help(tree)
  local mappings = require("ya-tree.actions")._tree_mappings
  local current_tree_type = tree.TYPE

  local tree_types = vim.tbl_keys(mappings) --[=[@as Yat.Trees.Type[]]=]
  table.sort(tree_types)
  utils.tbl_remove(tree_types, current_tree_type)
  table.insert(tree_types, 1, current_tree_type)

  local width = math.min(vim.o.columns - 2, 90)
  local current_tab = 1
  local lines, highlight_groups, close_keys = render_mappings_for_for_tree(current_tab, tree_types, mappings, width)

  local popup = nui.popup({
    title = " Help ",
    relative = "editor",
    enter = true,
    width = width,
    height = "90%",
    close_keys = close_keys,
    close_on_focus_loss = true,
    lines = lines,
    highlight_groups = highlight_groups,
  })
  for i in ipairs(tree_types) do
    popup:map("n", tostring(i), function()
      current_tab = i
      lines, highlight_groups = render_mappings_for_for_tree(current_tab, tree_types, mappings, width)
      popup:set_content(lines, highlight_groups)
    end, { noremap = true })
  end
  popup:map("n", "<Tab>", function()
    current_tab = current_tab + 1
    if current_tab > #tree_types then
      current_tab = 1
    end
    lines, highlight_groups = render_mappings_for_for_tree(current_tab, tree_types, mappings, width)
    popup:set_content(lines, highlight_groups)
  end, { noremap = true })
  popup:map("n", "<S-Tab>", function()
    current_tab = current_tab - 1
    if current_tab == 0 then
      current_tab = #tree_types
    end
    lines, highlight_groups = render_mappings_for_for_tree(current_tab, tree_types, mappings, width)
    popup:set_content(lines, highlight_groups)
  end, { noremap = true })
end

return M

local hl = require("ya-tree.ui.highlights")
local nui = require("ya-tree.ui.nui")
local utils = require("ya-tree.utils")

local api = vim.api

local M = {}

local KEYS_SECTION_WIDTH = 15

---@alias Yat.Help.Entry { key: string, action: Yat.Actions.Name, desc: string, user_defined: boolean }

--Sort by description, with user defined actions first.
---@param a Yat.Help.Entry
---@param b Yat.Help.Entry
---@return boolean
local function mapping_sorter(a, b)
  if not a.user_defined and b.user_defined then
    return false
  elseif a.user_defined and not b.user_defined then
    return true
  end
  return a.desc < b.desc
end

---@param mappings table<string, Yat.Action>
---@return Yat.Help.Entry[] insert_mappings
---@return Yat.Help.Entry[] visual_mappings
---@return integer max_mapping_width
---@return string[] close_keys
local function parse_mappings(mappings)
  local max_mapping_width = 0
  local close_keys = { "q", "<ESC>" }

  ---@type Yat.Help.Entry[], Yat.Help.Entry[]
  local insert, visual = {}, {}
  for key, action in pairs(mappings) do
    for _, mode in ipairs(action.modes) do
      local entry = { key = key, action = action.name, desc = action.desc, user_defined = action.user_defined }
      if mode == "n" then
        insert[#insert + 1] = entry
      elseif mode == "v" or mode == "V" then
        visual[#visual + 1] = entry
        break
      end
    end

    max_mapping_width = math.max(max_mapping_width, api.nvim_strwidth(action.desc))
    if action.name == "open_help" then
      close_keys[#close_keys + 1] = key
    end
  end

  table.sort(insert, mapping_sorter)
  table.sort(visual, mapping_sorter)

  return insert, visual, max_mapping_width, close_keys
end

---@param format_string string
---@param current_tab integer
---@param all_panel_types Yat.Panel.Type[]
---@param width integer
---@return string[] lines
---@return Yat.Ui.HighlightGroup[][] highlight_groups
local function create_header(format_string, current_tab, all_panel_types, width)
  local tabs = {}
  for index, tree_type in ipairs(all_panel_types) do
    tabs[index] = string.format(" (%s) %s ", index, tree_type)
  end
  local header = string.format("%" .. math.floor((width / 2) + 6) .. "s", "KEY MAPPINGS")
  local keys = "press <Tab>, <S-Tab> or <number> to navigate"
  local formatted_keys = string.format("%" .. math.floor((width / 2) + (#keys / 2)) .. "s", keys)
  local tabs_line = " " .. table.concat(tabs, " ")
  local legend = string.format(format_string, "Key", "Action")
  local lines = { header, formatted_keys, "", tabs_line, "", legend }

  ---@type Yat.Ui.HighlightGroup[]
  local tabs_highligt_group = {}
  local current_startpos = 1
  for i, tab in ipairs(tabs) do
    local hl_name = i == current_tab and hl.UI_CURRENT_TAB or hl.UI_OTHER_TAB
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
    { { name = hl.SEARCH_TERM, from = 0, to = KEYS_SECTION_WIDTH }, { name = hl.SEARCH_TERM, from = KEYS_SECTION_WIDTH + 2, to = -1 } },
  }

  return lines, highlight_groups
end

---@param lines string[]
---@param highlight_groups Yat.Ui.HighlightGroup[][]
---@param format_string string
---@param insert Yat.Help.Entry[]
---@param visual Yat.Help.Entry[]
local function create_mappings_section(lines, highlight_groups, format_string, insert, visual)
  lines[#lines + 1] = ""
  lines[#lines + 1] = " Normal Mode:"
  highlight_groups[#highlight_groups + 1] = {}
  highlight_groups[#highlight_groups + 1] = { { name = hl.ROOT_NAME, from = 0, to = -1 } }
  for _, v in ipairs(insert) do
    local line = string.format(format_string, v.key, v.desc)
    lines[#lines + 1] = line
    highlight_groups[#highlight_groups + 1] = {
      { name = hl.GIT_DIRTY, from = 0, to = KEYS_SECTION_WIDTH },
      { name = hl.SYMBOLIC_LINK_TARGET, from = KEYS_SECTION_WIDTH + 2, to = -1 },
    }
  end

  if #visual > 0 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = " Visual Mode:"
    highlight_groups[#highlight_groups + 1] = {}
    highlight_groups[#highlight_groups + 1] = { { name = hl.ROOT_NAME, from = 0, to = -1 } }
    for _, v in ipairs(visual) do
      local line = string.format(format_string, v.key, v.desc)
      lines[#lines + 1] = line
      highlight_groups[#highlight_groups + 1] = {
        { name = hl.GIT_DIRTY, from = 0, to = KEYS_SECTION_WIDTH },
        { name = hl.SYMBOLIC_LINK_TARGET, from = KEYS_SECTION_WIDTH + 2, to = -1 },
      }
    end
  end
end

---@param current_tab integer
---@param all_panel_types Yat.Panel.Type[]
---@param keymaps table<Yat.Panel.Type, table<string, Yat.Action>>
---@param width integer
---@return string[] lines
---@return Yat.Ui.HighlightGroup[][] highlight_groups
---@return string[] close_keys
local function render_mappings_for_for_panel(current_tab, all_panel_types, keymaps, width)
  local tree_type = all_panel_types[current_tab]
  local current_mappings = keymaps[tree_type]
  local insert, visual, max_mapping_width, close_keys = parse_mappings(current_mappings)

  local format_string = "%" .. KEYS_SECTION_WIDTH .. "s : %-" .. max_mapping_width .. "s " -- with trailing space to match the left side

  local lines, highlight_groups = create_header(format_string, current_tab, all_panel_types, width)
  create_mappings_section(lines, highlight_groups, format_string, insert, visual)

  return lines, highlight_groups, close_keys
end

---@async
---@param panel Yat.Panel.Tree
function M.open_help(panel)
  local keymaps = require("ya-tree.panels").keymaps()
  local current_panel_type = panel.TYPE

  local panel_types = vim.tbl_keys(keymaps) --[=[@as Yat.Panel.Type[]]=]
  table.sort(panel_types)
  utils.tbl_remove(panel_types, current_panel_type)
  table.insert(panel_types, 1, current_panel_type)

  local width = math.min(vim.o.columns - 2, 90)
  local current_tab = 1
  local lines, highlight_groups, close_keys = render_mappings_for_for_panel(current_tab, panel_types, keymaps, width)

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
  for i in ipairs(panel_types) do
    popup:map("n", tostring(i), function()
      current_tab = i
      lines, highlight_groups = render_mappings_for_for_panel(current_tab, panel_types, keymaps, width)
      popup:set_content(lines, highlight_groups)
    end, { noremap = true })
  end
  popup:map("n", "<Tab>", function()
    current_tab = current_tab + 1
    if current_tab > #panel_types then
      current_tab = 1
    end
    lines, highlight_groups = render_mappings_for_for_panel(current_tab, panel_types, keymaps, width)
    popup:set_content(lines, highlight_groups)
  end, { noremap = true })
  popup:map("n", "<S-Tab>", function()
    current_tab = current_tab - 1
    if current_tab == 0 then
      current_tab = #panel_types
    end
    lines, highlight_groups = render_mappings_for_for_panel(current_tab, panel_types, keymaps, width)
    popup:set_content(lines, highlight_groups)
  end, { noremap = true })
end

return M

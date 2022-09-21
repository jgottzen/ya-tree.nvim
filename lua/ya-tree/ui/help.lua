local Popup = require("ya-tree.ui.popup")
local hl = require("ya-tree.ui.highlights")

local api = vim.api

local M = {}

--Sort by description, with user functions first.
---@param a Yat.Action.Mapping
---@param b Yat.Action.Mapping
---@return boolean
local function mapping_sorter(a, b)
  if a.fn and not b.fn then
    return true
  elseif b.fn then
    return false
  end
  return a.desc < b.desc
end

function M.open()
  local mappings = require("ya-tree.actions").mappings

  ---@param mapping Yat.Action.Mapping
  local insert = vim.tbl_filter(function(mapping)
    return mapping.mode == "n"
  end, mappings) --[=[@as Yat.Action.Mapping[]]=]
  ---@param mapping Yat.Action.Mapping
  local visual = vim.tbl_filter(function(mapping)
    return mapping.mode == "v" or mapping.mode == "V"
  end, mappings) --[=[@as Yat.Action.Mapping[]]=]
  table.sort(insert, mapping_sorter)
  table.sort(visual, mapping_sorter)

  local max_key_width = 0
  local max_mapping_width = 0
  local close_keys = { "q", "<ESC>" }
  for _, mapping in ipairs(mappings) do
    max_key_width = math.max(max_key_width, api.nvim_strwidth(mapping.key))
    max_mapping_width = math.max(max_mapping_width, api.nvim_strwidth(mapping.desc))
    if mapping.action == "open_help" then
      close_keys[#close_keys + 1] = mapping.key
    end
  end
  max_key_width = max_key_width + 1 -- add 1 so we get 1 character space to the left of the key
  local mapping_col_start = max_key_width + 3 + max_mapping_width
  local format_string = "%" .. max_key_width .. "s : %-" .. max_mapping_width .. "s : %s " -- with trailing space to match the left side

  local header = string.format(format_string, "Key", "Action", "Tree")
  local lines = { "", header, "", " Normal Mode:" }
  ---@type Yat.Ui.HighlightGroup[][]
  local highlight_groups = {
    { { name = hl.ROOT_NAME, from = 0, to = -1 } },
    { { name = hl.SEARCH_TERM, from = 0, to = -1 } },
    {},
    { { name = hl.ROOT_NAME, from = 0, to = -1 } },
  }
  local max_line_width = api.nvim_strwidth(header) --[[@as number]]

  for _, mapping in ipairs(insert) do
    local line = string.format(format_string, mapping.key, mapping.desc, table.concat(mapping.tree_types, ", "))
    lines[#lines + 1] = line
    max_line_width = math.max(max_line_width, api.nvim_strwidth(line))
    highlight_groups[#highlight_groups + 1] = {
      { name = hl.GIT_DIRTY, from = 0, to = max_key_width },
      { name = hl.SYMBOLIC_LINK, from = max_key_width, to = mapping_col_start },
      { name = hl.GIT_NEW, from = mapping_col_start, to = -1 },
    }
  end

  lines[#lines + 1] = ""
  lines[#lines + 1] = " Visual Mode:"
  highlight_groups[#highlight_groups + 1] = {}
  highlight_groups[#highlight_groups + 1] = { { name = hl.ROOT_NAME, from = 0, to = -1 } }

  for _, mapping in ipairs(visual) do
    local line = string.format(format_string, mapping.key, mapping.desc, table.concat(mapping.tree_types, ", "))
    lines[#lines + 1] = line
    max_line_width = math.max(max_line_width, api.nvim_strwidth(line))
    highlight_groups[#highlight_groups + 1] = {
      { name = hl.GIT_DIRTY, from = 0, to = max_key_width },
      { name = hl.SYMBOLIC_LINK, from = max_key_width, to = mapping_col_start },
      { name = hl.GIT_NEW, from = mapping_col_start, to = -1 },
    }
  end

  lines[1] = string.format("%" .. (max_line_width / 2) + 6 .. "s", "KEY MAPPINGS")

  Popup.new(lines, highlight_groups):centered():close_with(close_keys):close_on_focus_loss():open(true)
end

return M

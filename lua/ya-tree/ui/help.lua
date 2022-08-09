local hl = require("ya-tree.ui.highlights")

local api = vim.api

local M = {}

--Sort by description, with user functions first.
---@param a YaTreeActionMapping
---@param b YaTreeActionMapping
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

  ---@param mapping YaTreeActionMapping
  local insert = vim.tbl_filter(function(mapping)
    return mapping.mode == "n"
  end, mappings) --[=[@as YaTreeActionMapping[]]=]
  ---@param mapping YaTreeActionMapping
  local visual = vim.tbl_filter(function(mapping)
    return mapping.mode == "v" or mapping.mode == "V"
  end, mappings) --[=[@as YaTreeActionMapping[]]=]
  table.sort(insert, mapping_sorter)
  table.sort(visual, mapping_sorter)

  local max_key_width = 0
  local max_mapping_width = 0
  ---@type string[]
  local help_mappings = {}
  for _, mapping in ipairs(mappings) do
    max_key_width = math.max(max_key_width, api.nvim_strwidth(mapping.key))
    max_mapping_width = math.max(max_mapping_width, api.nvim_strwidth(mapping.desc))
    if mapping.action == "open_help" then
      help_mappings[#help_mappings + 1] = mapping.key
    end
  end
  max_key_width = max_key_width + 1 -- add 1 so we get 1 character space to the left of the key
  local format_string = "%" .. max_key_width .. "s : %-" .. max_mapping_width .. "s : %s"

  local header = string.format(format_string, "Key", "Mapping", "View")
  ---@type string[]
  local lines = { " KEY MAPPINGS", header, "", " Normal Mode:" }
  ---@type number
  local max_line_width = api.nvim_strwidth(header)

  local insert_start_linenr = #lines + 1
  for _, mapping in ipairs(insert) do
    local line = string.format(format_string, mapping.key, mapping.desc, table.concat(mapping.views, ", "))
    lines[#lines + 1] = line
    max_line_width = math.max(max_line_width, api.nvim_strwidth(line))
  end
  local insert_end_linenr = #lines

  lines[#lines + 1] = ""
  lines[#lines + 1] = " Visual Mode:"

  local visual_start_linenr = #lines + 1
  for _, mapping in ipairs(visual) do
    local line = string.format(format_string, mapping.key, mapping.desc, table.concat(mapping.views, ", "))
    lines[#lines + 1] = line
    max_line_width = math.max(max_line_width, api.nvim_strwidth(line))
  end
  local visual_end_linenr = #lines

  ---@type integer
  local ns = api.nvim_create_namespace("YaTreeKeyMaps")
  ---@type number
  local bufnr = api.nvim_create_buf(false, true)

  local mapping_col_start = max_key_width + 3 + max_mapping_width
  api.nvim_buf_set_lines(bufnr, 0, -1, true, lines)

  api.nvim_buf_add_highlight(bufnr, ns, hl.ROOT_NAME, 0, 0, -1)
  api.nvim_buf_add_highlight(bufnr, ns, hl.SEARCH_TERM, 1, 0, -1)
  api.nvim_buf_add_highlight(bufnr, ns, hl.ROOT_NAME, 3, 0, -1)

  for linenr = insert_start_linenr, insert_end_linenr do
    api.nvim_buf_add_highlight(bufnr, ns, hl.GIT_DIRTY, linenr - 1, 0, max_key_width)
    api.nvim_buf_add_highlight(bufnr, ns, hl.SYMBOLIC_LINK, linenr - 1, max_key_width, mapping_col_start)
    api.nvim_buf_add_highlight(bufnr, ns, hl.GIT_NEW, linenr - 1, mapping_col_start, -1)
  end

  api.nvim_buf_add_highlight(bufnr, ns, hl.ROOT_NAME, insert_end_linenr + 1, 0, -1)

  for linenr = visual_start_linenr, visual_end_linenr do
    api.nvim_buf_add_highlight(bufnr, ns, hl.GIT_DIRTY, linenr - 1, 0, max_key_width)
    api.nvim_buf_add_highlight(bufnr, ns, hl.SYMBOLIC_LINK, linenr - 1, max_key_width, mapping_col_start)
    api.nvim_buf_add_highlight(bufnr, ns, hl.GIT_NEW, linenr - 1, mapping_col_start, -1)
  end

  local opts = { noremap = true, silent = true, nowait = true }
  api.nvim_buf_set_keymap(bufnr, "n", "q", "<cmd>bdelete<CR>", opts)
  api.nvim_buf_set_keymap(bufnr, "n", "<Esc>", "<cmd>bdelete<CR>", opts)
  for _, key in ipairs(help_mappings) do
    api.nvim_buf_set_keymap(bufnr, "n", key, "<cmd>bdelete<CR>", opts)
  end

  local config = require("ya-tree.config").config
  local width = vim.o.columns
  -- have to take into account if the statusline is shown, and the two border line - top and bottom
  local height = vim.o.lines - vim.o.cmdheight - (vim.o.laststatus > 0 and 1 or 0) - 2
  api.nvim_open_win(bufnr, true, {
    relative = "editor",
    row = math.max(0, (height - #lines) / 2),
    col = math.max(0, (width - max_line_width - 1) / 2),
    width = math.min(width, max_line_width + 1),
    height = math.min(height, #lines),
    zindex = 150,
    style = "minimal",
    border = config.view.popups.border,
  })

  -- set the filetype last so that autocommands that change the border can set it correctly
  api.nvim_buf_set_option(bufnr, "filetype", "YaTreeKeyMaps")
  api.nvim_buf_set_option(bufnr, "modifiable", false)
  api.nvim_buf_set_option(bufnr, "bufhidden", "wipe")
end

return M

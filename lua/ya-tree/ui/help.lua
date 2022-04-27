local hl = require("ya-tree.ui.highlights")

local api = vim.api

local M = {}

function M.show()
  local mappings = require("ya-tree.actions").mappings

  ---@type string[]
  local lines
  ---@type ActionMapping[]
  ---@param mapping ActionMapping
  local insert = vim.tbl_filter(function(mapping)
    return mapping.mode == "n"
  end, mappings)
  ---@type ActionMapping[]
  ---@param mapping ActionMapping
  local visual = vim.tbl_filter(function(mapping)
    return mapping.mode == "v" or mapping.mode == "V"
  end, mappings)
  ---@param a ActionMapping
  ---@param b ActionMapping
  table.sort(insert, function(a, b)
    return a.name < b.name
  end)
  ---@param a ActionMapping
  ---@param b ActionMapping
  table.sort(visual, function(a, b)
    return a.name < b.name
  end)

  ---@type string[]
  local help_mappings = {}
  local max_key_width = 0
  local max_mapping_width = 0
  for _, mapping in ipairs(mappings) do
    for _, key in ipairs(mapping.keys) do
      max_key_width = math.max(max_key_width, api.nvim_strwidth(key))
      if mapping.name == "open_help" then
        table.insert(help_mappings, key)
      end
    end
    max_mapping_width = math.max(max_mapping_width, api.nvim_strwidth(mapping.desc or mapping.name))
  end
  max_key_width = max_key_width + 1
  local format_string = "%" .. max_key_width .. "s : %-" .. max_mapping_width .. "s : %s"

  local header = string.format(format_string, "Key", "Mapping", "View")
  lines = { " KEY MAPPINGS", header, "", " Normal Mode:" }
  local max_line_width = api.nvim_strwidth(header)

  local insert_start_linenr = #lines + 1
  for _, mapping in ipairs(insert) do
    for _, key in ipairs(mapping.keys) do
      local line = string.format(format_string, key, mapping.desc or mapping.name, table.concat(vim.tbl_keys(mapping.views), ", "))
      lines[#lines + 1] = line
      max_line_width = math.max(max_line_width, api.nvim_strwidth(line))
    end
  end
  local insert_end_linenr = #lines

  lines[#lines + 1] = ""
  lines[#lines + 1] = " Visual Mode:"

  local visual_start_linenr = #lines + 1
  for _, mapping in ipairs(visual) do
    for _, key in ipairs(mapping.keys) do
      local line = string.format(format_string, key, mapping.desc or mapping.name, table.concat(vim.tbl_keys(mapping.views), ", "))
      lines[#lines + 1] = line
      max_line_width = math.max(max_line_width, api.nvim_strwidth(line))
    end
  end
  local visual_end_linenr = #lines

  local ns = api.nvim_create_namespace("YaTreeKeyMaps")
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

  api.nvim_buf_set_option(bufnr, "modifiable", false)
  api.nvim_buf_set_option(bufnr, "bufhidden", "wipe")

  local width = vim.o.columns
  local height = vim.o.lines - vim.o.cmdheight
  api.nvim_open_win(bufnr, true, {
    relative = "editor",
    row = math.max(0, (height - #lines) / 2),
    col = math.max(0, (width - max_line_width - 1) / 2),
    width = math.min(width, max_line_width + 1),
    height = math.min(height, #lines),
    zindex = 150,
    style = "minimal",
    border = "rounded",
  })
end

return M

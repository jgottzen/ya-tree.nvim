local wrap = require("plenary.async").wrap

local api = vim.api

---@alias Yat.Ui.Position "left"|"right"|"top"|"bottom"

---@class Yat.Ui.HighlightGroup
---@field name string
---@field from integer
---@field to integer

local M = {}

---@param winid? integer
---@return boolean is_floating
function M.is_window_floating(winid)
  local win_config = api.nvim_win_get_config(winid or 0)
  return win_config.relative > "" or win_config.external
end

---@type async fun(opts: {prompt: string|nil, default: string|nil, completion: string|nil, highlight: fun()|nil}): string|nil
M.input = wrap(function(opts, on_confirm)
  vim.ui.input(opts, on_confirm)
end, 2)

---@type async fun(items: table, opts: {prompt: string|nil, format_item: fun(item: any), kind: string|nil}): string?, integer?
M.select = wrap(function(items, opts, on_choice)
  vim.ui.select(items, opts, on_choice)
end, 3)

---@param config Yat.Config
function M.setup(config)
  local hl = require("ya-tree.ui.highlights")
  hl.setup()
  require("ya-tree.ui.renderers").setup(config)

  local events = require("ya-tree.events")
  local event = require("ya-tree.events.event").autocmd
  events.on_autocmd_event(event.COLORSCHEME, "YA_TREE_UI_HIGHLIGHTS", hl.setup)
end

return M

local nui = require("ya-tree.ui.nui")
local wrap = require("ya-tree.async").wrap

local api = vim.api

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

---@param bufnr integer
---@return integer|nil winid
function M.get_window_for_buffer(bufnr)
  for _, winid in ipairs(api.nvim_list_wins()) do
    if api.nvim_win_get_buf(winid) == bufnr then
      return winid
    end
  end
end

---@param height integer|string
---@return integer height
function M.normalize_height(height)
  local win_height = vim.o.lines - vim.o.cmdheight - (vim.o.laststatus > 0 and 1 or 0) - 2
  local size
  if type(height) == "string" then
    if height:sub(-1) == "%" then
      size = math.floor((win_height * tonumber(height:sub(1, -2))) / 100)
    else
      size = tonumber(height) --[[@as integer]]
    end
  elseif type(height) == "number" then
    size = height
  end
  return size
end

---@type async fun(opts: Yat.Ui.InputOpts): string|nil
M.nui_input = wrap(function(opts, on_submit)
  nui.input(opts, {
    on_close = function()
      on_submit(nil)
    end,
    on_submit = function(text)
      on_submit(text)
    end,
  })
end, 2, true)

---@type async fun(opts: {prompt: string|nil, default: string|nil, completion: string|nil, highlight: fun()|nil}): string|nil
M.input = wrap(vim.ui.input, 2, true)

---@type async fun(items: any[], opts: {prompt: string|nil, format_item: fun(item: any), kind: string|nil}): string?, integer?
M.select = wrap(vim.ui.select, 3, true)

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

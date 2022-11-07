local api = vim.api

local ns = api.nvim_create_namespace("YaTreePopUp")
local auto_close_augroup = api.nvim_create_augroup("YaTreePopupAutoClose", { clear = true })

local M = {
  ns = ns,
}

---@param lines string[]
---@return integer max_width
local function get_max_line_size(lines)
  local max_width = 0
  for _, line in ipairs(lines) do
    max_width = math.max(max_width, api.nvim_strwidth(line))
  end
  return max_width
end

---@param win_size integer
---@param value string|integer
---@return integer size
local function compute_size(win_size, value)
  local size
  if type(value) == "string" then
    if value:sub(-1) == "%" then
      size = math.floor((win_size * tonumber(value:sub(1, -2))) / 100)
    else
      size = tonumber(value) --[[@as integer]]
    end
  elseif type(value) == "number" then
    size = value
  end
  return size
end

---@param content_height integer
---@param size { width?: string|integer, height?: string|integer, grow_width?: boolean }
---@param max_width integer
---@param content_width integer
---@param max_height integer
---@return integer widht
---@return integer height
local function compute_width_and_height(content_height, content_width, size, max_width, max_height)
  local width, height
  if size then
    width = size.width and compute_size(max_width, size.width) or content_width
    if width < content_width and size.grow_width then
      width = content_width
    end
    height = size.height and compute_size(max_height, size.height) or content_height
  else
    width = math.min(max_width, content_width)
    height = math.min(max_height, content_height)
  end

  return width, height
end

---@param relative string
---@param row integer
---@param col integer
---@param width integer
---@param height integer
---@param enter boolean
---@return integer winid
---@return integer bufnr
local function create_window(relative, row, col, width, height, enter)
  local bufnr = api.nvim_create_buf(false, true)
  local border = require("ya-tree.config").config.view.popups.border
  local winid = api.nvim_open_win(bufnr, enter, {
    relative = relative,
    row = row,
    col = col,
    width = width,
    height = height,
    zindex = 50,
    style = "minimal",
    border = border or "rounded",
  })
  api.nvim_buf_set_option(bufnr, "bufhidden", "wipe")
  api.nvim_buf_set_option(bufnr, "filetype", "YaTreePopup")
  vim.wo.winhl = table.concat({
    "Normal:YaTreeTextFloat",
    "FloatBorder:FloatBorder",
  }, ",")

  return winid, bufnr
end

---@param bufnr integer
---@param lines string[]
---@param highlight_groups? Yat.Ui.HighlightGroup[][]
local function render(bufnr, lines, highlight_groups)
  api.nvim_buf_set_option(bufnr, "modifiable", true)
  api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  if highlight_groups then
    for line, highlight_group in ipairs(highlight_groups) do
      for _, highlight in ipairs(highlight_group) do
        api.nvim_buf_add_highlight(bufnr, ns, highlight.name, line - 1, highlight.from, highlight.to)
      end
    end
  end
  api.nvim_buf_set_option(bufnr, "modifiable", false)
end

---@class Yat.Ui.Popup.KeyMap
---@field mode string
---@field key string
---@field rhs string|function

---@class Yat.Ui.Popup.Builder
---@field private _lines string[]
---@field private _highlight_groups Yat.Ui.HighlightGroup[][]
---@field private _relative string
---@field private _width? string|integer
---@field private _height? string|integer
---@field private _grow_width boolean
---@field private _close_keys? string[]
---@field private _on_close? fun()
---@field private _close_on_focus_loss boolean
---@field private _keymaps? Yat.Ui.Popup.KeyMap[]
local PopupBuilder = {}
PopupBuilder.__index = PopupBuilder

---@param lines string[]
---@param highlight_groups Yat.Ui.HighlightGroup[][]
---@return Yat.Ui.Popup.Builder builder
function PopupBuilder:new(lines, highlight_groups)
  local this = setmetatable({
    _lines = lines,
    _highlight_groups = highlight_groups,
    _relative = "cursor",
    _grow_width = false,
    _close_on_focus_loss = false,
  }, self)
  return this
end

---@return Yat.Ui.Popup.Builder builder
function PopupBuilder:centered()
  self._relative = "editor"
  return self
end

---@param width? string|integer
---@param height? string|integer
---@param grow_width? boolean
---@return Yat.Ui.Popup.Builder builder
function PopupBuilder:size(width, height, grow_width)
  self._width = width
  self._height = height
  self._grow_width = grow_width or false
  return self
end

---@param close_keys string[]
---@return Yat.Ui.Popup.Builder builder
function PopupBuilder:close_with(close_keys)
  self._close_keys = close_keys
  return self
end

---@param on_close fun()
---@return Yat.Ui.Popup.Builder builder
function PopupBuilder:on_close(on_close)
  self._on_close = on_close
  return self
end

---@return Yat.Ui.Popup.Builder builder
function PopupBuilder:close_on_focus_loss()
  self._close_on_focus_loss = true
  return self
end

---@param mode string
---@param keys string|string[]
---@param rhs string|function
---@return Yat.Ui.Popup.Builder builder
function PopupBuilder:map_keys(mode, keys, rhs)
  if not self._keymaps then
    self._keymaps = {}
  end
  if type(keys) == "string" then
    keys = { keys }
  end
  for _, key in ipairs(keys) do
    self._keymaps[#self._keymaps + 1] = { mode = mode, key = key, rhs = rhs }
  end
  return self
end

---@class Yat.Ui.Popup
---@field winid integer
---@field bufnr integer
local Popup = {}
Popup.__index = Popup

---@param winid integer
---@param bufnr integer
---@return Yat.Ui.Popup popup
function Popup:new(winid, bufnr)
  local this = setmetatable({}, self)
  this.winid = winid
  this.bufnr = bufnr
  return this
end

---@param lines string[]
---@param highlight_groups? Yat.Ui.HighlightGroup[][]
function Popup:set_content(lines, highlight_groups)
  render(self.bufnr, lines, highlight_groups)
end

---@param enter? boolean
---@return Yat.Ui.Popup popup
function PopupBuilder:open(enter)
  enter = enter or false
  -- have to take into account if the statusline is shown, and the two border lines - top and bottom
  local win_width = vim.o.columns
  local win_height = vim.o.lines - vim.o.cmdheight - (vim.o.laststatus > 0 and 1 or 0) - 2
  local nr_of_lines = #self._lines
  local is_relative = self._relative == "cursor"
  local size = { width = self._width, height = self._height, grow_width = self._grow_width }

  local content_width = get_max_line_size(self._lines)
  local max_width = is_relative and content_width or win_width
  local max_height = is_relative and nr_of_lines or win_height
  local width, height = compute_width_and_height(nr_of_lines, content_width, size, max_width, max_height)
  local row = is_relative and 1 or math.max(0, (win_height - height + 1) / 2)
  local col = is_relative and 1 or math.max(0, (win_width - width + 1) / 2)

  local winid, bufnr = create_window(self._relative, row, col, width, height, enter)
  render(bufnr, self._lines, self._highlight_groups)

  local keymap_opts = { buffer = bufnr, silent = true, nowait = true }
  if self._close_keys then
    for _, key in ipairs(self._close_keys) do
      vim.keymap.set("n", key, function()
        api.nvim_win_close(winid, true)
        if self._on_close then
          self._on_close()
        end
      end, keymap_opts)
    end
  end
  if self._keymaps then
    for _, keymap in ipairs(self._keymaps) do
      vim.keymap.set(keymap.mode, keymap.key, keymap.rhs, keymap_opts)
    end
  end
  if self._close_on_focus_loss then
    local aucmd
    aucmd = api.nvim_create_autocmd("WinEnter", {
      group = auto_close_augroup,
      callback = function()
        local buftype = api.nvim_buf_get_option(0, "buftype")
        local filetype = api.nvim_buf_get_option(0, "filetype")
        if buftype ~= "prompt" and (buftype ~= "nofile" or filetype == "YaTree") then
          api.nvim_del_autocmd(aucmd)
          if api.nvim_win_is_valid(winid) then
            api.nvim_win_close(winid, true)
          end
          if self._on_close then
            self._on_close()
          end
        end
      end,
      desc = "Close popup on focus loss",
    })
  end

  return Popup:new(winid, bufnr)
end

---@param lines string[]
---@param highlight_groups Yat.Ui.HighlightGroup[][]
---@return Yat.Ui.Popup.Builder
function M.new(lines, highlight_groups)
  return PopupBuilder:new(lines, highlight_groups)
end

return M

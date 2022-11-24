local events = require("ya-tree.events")
local event = require("ya-tree.events.event").ya_tree
local meta = require("ya-tree.meta")
local log = require("ya-tree.log")("ui")

local api = vim.api
local fn = vim.fn

local ns = api.nvim_create_namespace("YaTreeHighlights")

local BUF_OPTIONS = {
  bufhidden = "hide", -- must be hide and not wipe for Canvas:restore and particularly Canvas:move_buffer_to_edit_window to work
  buflisted = false,
  filetype = "YaTree",
  buftype = "nofile",
  modifiable = false,
  swapfile = false,
}

local WIN_OPTIONS = {
  -- number and relativenumber are taken from their config values when creating a window
  list = false,
  winfixwidth = true,
  winfixheight = true,
  foldenable = false,
  spell = false,
  signcolumn = "no",
  foldmethod = "manual",
  foldcolumn = "0",
  cursorcolumn = false,
  cursorlineopt = "line",
  wrap = false,
  winhl = table.concat({
    "Normal:YaTreeNormal",
    "NormalNC:YaTreeNormalNC",
    "CursorLine:YaTreeCursorLine",
    "VertSplit:YaTreeVertSplit",
    "WinSeparator:YaTreeWinSeparator",
    "StatusLine:YaTreeStatusLine",
    "StatusLineNC:YaTreeStatuslineNC",
  }, ","),
}

---@class Yat.Ui.Canvas : Yat.Object
---@field new fun(self: Yat.Ui.Canvas, position: Yat.Ui.Position, size: integer, tree_and_node_provider: fun(row: integer): Yat.Tree?, Yat.Node?): Yat.Ui.Canvas
---@overload fun(position: Yat.Ui.Position, size: integer, tree_and_node_provider: fun(row: integer): Yat.Tree?, Yat.Node?): Yat.Ui.Canvas
---@field class fun(self: Yat.Ui.Canvas): Yat.Ui.Canvas
---
---@field private _winid? integer
---@field private _edit_winid? integer
---@field private bufnr? integer
---@field private position Yat.Ui.Position
---@field private _size integer
---@field private window_augroup? integer
---@field private previous_row integer
---@field private pos_after_win_leave? integer[]
---@field private tree_and_node_provider fun(row: integer): Yat.Tree?, Yat.Node?
local Canvas = meta.create_class("Yat.Ui.Canvas")

Canvas.__tostring = function(self)
  return string.format("(winid=%s, bufnr=%s, edit_winid=%s", self._winid, self.bufnr, self._edit_winid)
end

---@private
---@param position Yat.Ui.Position
---@param size integer
---@param tree_and_node_provider fun(row: integer): Yat.Tree?, Yat.Node?
function Canvas:init(position, size, tree_and_node_provider)
  self.previous_row = 1
  self.position = position
  self._size = size
  self.tree_and_node_provider = tree_and_node_provider
end

---@return boolean
function Canvas:is_on_side()
  return self.position == "left" or self.position == "right"
end

---@return integer winid
function Canvas:winid()
  return self._winid
end

---@return integer height, integer width
function Canvas:size()
  return api.nvim_win_get_height(self._winid), api.nvim_win_get_width(self._winid)
end

---@return integer
function Canvas:inner_width()
  local info = fn.getwininfo(self._winid)
  return info[1] and (info[1].width - info[1].textoff) or api.nvim_win_get_width(self._winid)
end

---@return integer|nil winid
function Canvas:edit_winid()
  if self._edit_winid and not api.nvim_win_is_valid(self._edit_winid) then
    self._edit_winid = nil
  end
  return self._edit_winid
end

---@param winid integer
function Canvas:set_edit_winid(winid)
  if not winid then
    log.error("setting edit_winid to nil!")
  end
  log.debug("setting edit_winid to %s", winid)
  self._edit_winid = winid
  if self._edit_winid and self._edit_winid == self._winid then
    log.error("setting edit_winid to %s, the same as winid", self._edit_winid)
  end
end

---@return boolean is_open
function Canvas:is_open()
  if self._winid and not api.nvim_win_is_valid(self._winid) then
    self._winid = nil
  end
  return self._winid ~= nil
end

---@return boolean
function Canvas:is_current_window_canvas()
  return self._winid and self._winid == api.nvim_get_current_win() or false
end

---@private
function Canvas:_create_buffer()
  self.bufnr = api.nvim_create_buf(false, false)
  log.debug("created buffer %s", self.bufnr)
  api.nvim_buf_set_name(self.bufnr, "YaTree://YaTree" .. self.bufnr)

  for k, v in pairs(BUF_OPTIONS) do
    vim.bo[self.bufnr][k] = v
  end

  require("ya-tree.actions").apply_mappings(self.bufnr)
end

---@param winid integer
---@param bufnr integer
local function win_set_buf_noautocmd(winid, bufnr)
  local eventignore = vim.o.eventignore
  vim.o.eventignore = "all"
  api.nvim_win_set_buf(winid, bufnr)
  vim.o.eventignore = eventignore
end

function Canvas:restore()
  if self._winid and self.bufnr then
    log.debug("restoring canvas buffer to buffer %s", self.bufnr)
    win_set_buf_noautocmd(self._winid, self.bufnr)
  end
end

---@param bufnr integer
function Canvas:move_buffer_to_edit_window(bufnr)
  if self._winid and self.bufnr then
    if not self._edit_winid then
      self:create_edit_window()
    end
    log.debug("moving buffer %s from window %s to window %s", bufnr, self._winid, self._edit_winid)

    self:restore()
    api.nvim_set_current_win(self._edit_winid)
    --- moving the buffer to the edit window retains the number/relativenumber/signcolumn settings
    -- from the tree window...
    -- save them and apply them after switching
    local number = vim.wo.number
    local relativenumber = vim.wo.relativenumber
    local signcolumn = vim.wo.signcolumn
    api.nvim_win_set_buf(self._edit_winid, bufnr)
    vim.wo.number = number
    vim.wo.relativenumber = relativenumber
    vim.wo.signcolumn = signcolumn
  end
end

---@param size? integer
function Canvas:resize(size)
  if size then
    self._size = size
  end
  if self:is_on_side() then
    api.nvim_win_set_width(self._winid, self._size)
  else
    api.nvim_win_set_height(self._winid, self._size)
  end
end

local POSITIONS_TO_WINCMD = { left = "H", bottom = "J", top = "K", right = "L" }

---@param position? Yat.Ui.Position
---@param size? integer
function Canvas:move_window(position, size)
  self.position = position or self.position
  vim.cmd.wincmd({ POSITIONS_TO_WINCMD[self.position], mods = { noautocmd = true } })
  self:resize(size)
end

---@private
---@param position? Yat.Ui.Position
function Canvas:_create_window(position)
  local winid = api.nvim_get_current_win()
  if winid ~= self._edit_winid then
    local old_edit_winid = self._edit_winid
    self._edit_winid = winid
    log.debug("setting edit_winid to %s, old=%s", self._edit_winid, old_edit_winid)
  end

  vim.cmd.vsplit({ mods = { noautocmd = true } })
  self._winid = api.nvim_get_current_win()
  self:move_window(position, self._size)
  log.debug("created window %s", self._winid)
  self:_set_window_options()
end

---@private
function Canvas:_set_window_options()
  win_set_buf_noautocmd(self._winid, self.bufnr)

  for k, v in pairs(WIN_OPTIONS) do
    vim.wo[self._winid][k] = v
  end
  local config = require("ya-tree.config").config
  vim.wo[self._winid].number = config.view.number
  vim.wo[self._winid].relativenumber = config.view.relativenumber

  self.window_augroup = api.nvim_create_augroup("YaTreeCanvas_Window_" .. self._winid, { clear = true })
  api.nvim_create_autocmd("WinLeave", {
    group = self.window_augroup,
    buffer = self.bufnr,
    callback = function()
      self.pos_after_win_leave = api.nvim_win_get_cursor(self._winid)
      if self._edit_winid then
        self._size = self:is_on_side() and api.nvim_win_get_width(self._winid) or api.nvim_win_get_height(self._winid)
      end
    end,
    desc = "Storing window size",
  })
  api.nvim_create_autocmd("WinClosed", {
    group = self.window_augroup,
    pattern = tostring(self._winid),
    callback = function()
      self:_on_win_closed()
    end,
    desc = "Cleaning up window specific settings",
  })
  if config.move_cursor_to_name then
    api.nvim_create_autocmd("CursorMoved", {
      group = self.window_augroup,
      buffer = self.bufnr,
      callback = function()
        self:_move_cursor_to_name()
      end,
      desc = "Moving cursor to name",
    })
  end
end

---@private
function Canvas:_on_win_closed()
  log.debug("window %s was closed", self._winid)

  local ok, result = pcall(api.nvim_del_augroup_by_id, self.window_augroup)
  if not ok then
    log.error("error deleting window local augroup: %s", result)
  end

  events.fire_yatree_event(event.YA_TREE_WINDOW_CLOSED, { winid = self._winid })

  self.window_augroup = nil
  self._winid = nil
  if self.bufnr then
    -- Deleting the buffer will inhibit TabClosed autocmds from firing...
    -- Deferring it works...
    local bufnr = self.bufnr
    vim.defer_fn(function()
      ok = pcall(api.nvim_buf_delete, bufnr, { force = true })
      if not ok then
        log.error("error deleting buffer %s", bufnr)
      end
    end, 100)
    self.bufnr = nil
  end
end

function Canvas:create_edit_window()
  vim.cmd.vsplit({ mods = { noautocmd = true } })
  self._edit_winid = api.nvim_get_current_win()
  api.nvim_win_call(self._winid, function()
    vim.cmd.wincmd({ POSITIONS_TO_WINCMD[self.position], mods = { noautocmd = true } })
    self:resize()
  end)
  log.debug("created edit window %s", self._edit_winid)
end

---@param winid integer
---@param row integer
---@param col integer
local function set_cursor_position(winid, row, col)
  -- avoids the cursor moving left when switching to the canvas window and then back,
  -- happens with floating windows
  api.nvim_win_call(winid, function()
    local ok = pcall(api.nvim_win_set_cursor, winid, { row, col })
    if ok then
      local win_height = api.nvim_win_get_height(winid)
      if win_height > row then
        pcall(vim.cmd.normal, { "zb", bang = true })
      elseif row < (win_height / 2) then
        pcall(vim.cmd.normal, { "zz", bang = true })
      end
    end
  end)
end

---@param opts? { position?: Yat.Ui.Position, size?: integer }
---  - {opts.position?} `Yat.Ui.Position`
---  - {opts.size?} `integer`
function Canvas:open(opts)
  if self:is_open() then
    return
  end

  opts = opts or {}
  if opts.size then
    self._size = opts.size
  end
  self:_create_buffer()
  self:_create_window(opts.position)

  events.fire_yatree_event(event.YA_TREE_WINDOW_OPENED, { winid = self._winid })
end

function Canvas:restore_previous_position()
  if self.pos_after_win_leave then
    set_cursor_position(self._winid, self.pos_after_win_leave[1], self.pos_after_win_leave[2])
  end
end

function Canvas:focus()
  if self._winid then
    local current_winid = api.nvim_get_current_win()
    if current_winid ~= self._winid then
      if current_winid ~= self._edit_winid then
        log.debug("winid=%s setting edit_winid to %s, old=%s", self._winid, current_winid, self._edit_winid)
        self._edit_winid = current_winid
      end
      api.nvim_set_current_win(self._winid)
    end
  end
end

function Canvas:focus_edit_window()
  if self:edit_winid() then
    api.nvim_set_current_win(self._edit_winid)
  end
end

---@return boolean has_focus
function Canvas:has_focus()
  return self._winid and self._winid == api.nvim_get_current_win() or false
end

function Canvas:close()
  -- if the canvas is the only window, it cannot be closed
  if not self._winid or #api.nvim_list_wins() == 1 then
    return
  end

  local ok = pcall(api.nvim_win_close, self._winid, true)
  if not ok then
    log.error("error closing window %q", self._winid)
  end
end

---@param lines string[]
---@param highlights Yat.Ui.HighlightGroup[][]
function Canvas:draw(lines, highlights)
  api.nvim_buf_set_option(self.bufnr, "modifiable", true)
  api.nvim_buf_clear_namespace(self.bufnr, ns, 0, -1)
  api.nvim_buf_set_lines(self.bufnr, 0, -1, false, lines)
  for linenr, line_highlights in ipairs(highlights) do
    for _, highlight in ipairs(line_highlights) do
      -- guard against bugged out renderer highlights, which will cause an avalanche of errors...
      if not highlight.name then
        log.error("missing highlight name for line=%s, hl=%s", tostring(lines[linenr]), highlight)
      else
        api.nvim_buf_add_highlight(self.bufnr, ns, highlight.name, linenr - 1, highlight.from, highlight.to)
      end
    end
  end
  api.nvim_buf_set_option(self.bufnr, "modifiable", false)
end

do
  local ESC_TERM_CODES = api.nvim_replace_termcodes("<ESC>", true, false, true)

  ---@return integer from, integer to
  function Canvas:get_selected_rows()
    local mode = api.nvim_get_mode().mode --[[@as string]]
    if mode == "v" or mode == "V" then
      local from = fn.getpos("v")[2] --[[@as integer]]
      local to = api.nvim_win_get_cursor(self._winid)[1]
      if from > to then
        from, to = to, from
      end

      api.nvim_feedkeys(ESC_TERM_CODES, "n", true)
      return from, to
    else
      local row = api.nvim_win_get_cursor(self._winid)[1]
      return row, row
    end
  end
end

---@private
function Canvas:_move_cursor_to_name()
  if not self._winid then
    return
  end
  local row, col = unpack(api.nvim_win_get_cursor(self._winid))
  local tree, node = self.tree_and_node_provider(row)
  if not tree or not node or row == self.previous_row then
    return
  end

  self.previous_row = row
  -- don't move the cursor on the root node
  if node == tree.root then
    return
  end

  local line = api.nvim_get_current_line()
  local column = (line:find(node.name, 1, true) or 0) - 1
  if column > 0 and column ~= col then
    api.nvim_win_set_cursor(self._winid, { row, column })
  end
end

---@param row integer
function Canvas:focus_row(row)
  local column = api.nvim_win_get_cursor(self._winid)[2]
  set_cursor_position(self._winid, row, column)
end

return Canvas

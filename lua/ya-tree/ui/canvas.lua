local events = require("ya-tree.events")
local event = require("ya-tree.events.event").ya_tree
local meta = require("ya-tree.meta")
local log = require("ya-tree.log")("ui")

local api = vim.api
local fn = vim.fn

local ns = api.nvim_create_namespace("YaTreeHighlights")

local buf_options = {
  bufhidden = "hide", -- must be hide and not wipe for Canvas:restore and particularly Canvas:move_buffer_to_edit_window to work
  buflisted = false,
  filetype = "YaTree",
  buftype = "nofile",
  modifiable = false,
  swapfile = false,
}

local win_options = {
  -- number and relativenumber are overridden by their config values when creating a window
  number = false,
  relativenumber = false,
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
---@field private winid? integer
---@field private edit_winid? integer
---@field private bufnr? integer
---@field private position Yat.Ui.Position
---@field private size integer
---@field private window_augroup? integer
---@field private previous_row integer
---@field private pos_after_win_leave? integer[]
---@field tree_and_node_provider fun(row: integer): Yat.Tree?, Yat.Node?
local Canvas = meta.create_class("Yat.Ui.Canvas")

Canvas.__tostring = function(self)
  return string.format("(winid=%s, bufnr=%s, edit_winid=%s", self.winid, self.bufnr, self.edit_winid)
end

---@private
---@param position Yat.Ui.Position
---@param size integer
---@param tree_and_node_provider fun(row: integer): Yat.Tree?, Yat.Node?
function Canvas:init(position, size, tree_and_node_provider)
  self.previous_row = 1
  self.position = position
  self.size = size
  self.tree_and_node_provider = tree_and_node_provider
end

---@return boolean
function Canvas:is_on_side()
  return self.position == "left" or self.position == "right"
end

---@return integer height, integer width
function Canvas:get_size()
  return api.nvim_win_get_height(self.winid), api.nvim_win_get_width(self.winid)
end

---@return integer
function Canvas:get_inner_width()
  local info = fn.getwininfo(self.winid)
  return info[1] and (info[1].width - info[1].textoff) or api.nvim_win_get_width(self.winid)
end

---@return integer|nil winid
function Canvas:get_edit_winid()
  if self.edit_winid and not api.nvim_win_is_valid(self.edit_winid) then
    self.edit_winid = nil
  end
  return self.edit_winid
end

---@param winid integer
function Canvas:set_edit_winid(winid)
  if not winid then
    log.error("setting edit_winid to nil!")
  end
  log.debug("setting edit_winid to %s", winid)
  self.edit_winid = winid
  if self.edit_winid and self.edit_winid == self.winid then
    log.error("setting edit_winid to %s, the same as winid", self.edit_winid)
  end
end

---@return boolean is_open
function Canvas:is_open()
  if self.winid and not api.nvim_win_is_valid(self.winid) then
    self.winid = nil
  end
  return self.winid ~= nil
end

---@return boolean
function Canvas:is_current_window_canvas()
  return self.winid and self.winid == api.nvim_get_current_win() or false
end

---@private
function Canvas:_create_buffer()
  self.bufnr = api.nvim_create_buf(false, false)
  log.debug("created buffer %s", self.bufnr)
  api.nvim_buf_set_name(self.bufnr, "YaTree://YaTree" .. self.bufnr)

  for k, v in pairs(buf_options) do
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
  if self.winid and self.bufnr then
    log.debug("restoring canvas buffer to buffer %s", self.bufnr)
    win_set_buf_noautocmd(self.winid, self.bufnr)
  end
end

---@param bufnr integer
function Canvas:move_buffer_to_edit_window(bufnr)
  if self.winid and self.bufnr then
    if not self.edit_winid then
      self:create_edit_window()
    end
    log.debug("moving buffer %s from window %s to window %s", bufnr, self.winid, self.edit_winid)

    self:restore()
    api.nvim_set_current_win(self.edit_winid)
    --- moving the buffer to the edit window retains the number/relativenumber/signcolumn settings
    -- from the tree window...
    -- save them and apply them after switching
    local number = vim.wo.number
    local relativenumber = vim.wo.relativenumber
    local signcolumn = vim.wo.signcolumn
    api.nvim_win_set_buf(self.edit_winid, bufnr)
    vim.wo.number = number
    vim.wo.relativenumber = relativenumber
    vim.wo.signcolumn = signcolumn
  end
end

---@param size? integer
function Canvas:resize(size)
  if size then
    self.size = size
  end
  if self:is_on_side() then
    api.nvim_win_set_width(self.winid, self.size)
  else
    api.nvim_win_set_height(self.winid, self.size)
  end
end

local positions_to_wincmd = { left = "H", bottom = "J", top = "K", right = "L" }

---@param position? Yat.Ui.Position
---@param size? integer
function Canvas:move_window(position, size)
  self.position = position or self.position
  vim.cmd.wincmd({ positions_to_wincmd[self.position], mods = { noautocmd = true } })
  self:resize(size)
end

---@private
---@param position? Yat.Ui.Position
function Canvas:_create_window(position)
  local winid = api.nvim_get_current_win()
  if winid ~= self.edit_winid then
    local old_edit_winid = self.edit_winid
    self.edit_winid = winid
    log.debug("setting edit_winid to %s, old=%s", self.edit_winid, old_edit_winid)
  end

  vim.cmd.vsplit({ mods = { noautocmd = true } })
  self.winid = api.nvim_get_current_win()
  self:move_window(position, self.size)
  log.debug("created window %s", self.winid)
  self:_set_window_options()
end

---@private
function Canvas:_set_window_options()
  win_set_buf_noautocmd(self.winid, self.bufnr)

  local config = require("ya-tree.config").config
  win_options.number = config.view.number
  win_options.relativenumber = config.view.relativenumber
  for k, v in pairs(win_options) do
    vim.wo[k] = v
  end

  self.window_augroup = api.nvim_create_augroup("YaTreeCanvas_Window_" .. self.winid, { clear = true })
  api.nvim_create_autocmd("WinLeave", {
    group = self.window_augroup,
    buffer = self.bufnr,
    callback = function()
      self.pos_after_win_leave = api.nvim_win_get_cursor(self.winid)
      if self.edit_winid then
        self.size = self:is_on_side() and api.nvim_win_get_width(self.winid) or api.nvim_win_get_height(self.winid)
      end
    end,
    desc = "Storing window size",
  })
  api.nvim_create_autocmd("WinClosed", {
    group = self.window_augroup,
    pattern = tostring(self.winid),
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
  log.debug("window %s was closed", self.winid)

  local ok, result = pcall(api.nvim_del_augroup_by_id, self.window_augroup)
  if not ok then
    log.error("error deleting window local augroup: %s", result)
  end

  events.fire_yatree_event(event.YA_TREE_WINDOW_CLOSED, { winid = self.winid })

  self.window_augroup = nil
  self.winid = nil
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
  self.edit_winid = api.nvim_get_current_win()
  api.nvim_win_call(self.winid, function()
    vim.cmd.wincmd({ positions_to_wincmd[self.position], mods = { noautocmd = true } })
    self:resize()
  end)
  log.debug("created edit window %s", self.edit_winid)
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
    self.size = opts.size
  end
  self:_create_buffer()
  self:_create_window(opts.position)

  events.fire_yatree_event(event.YA_TREE_WINDOW_OPENED, { winid = self.winid })
end

function Canvas:restore_previous_position()
  if self.pos_after_win_leave then
    set_cursor_position(self.winid, self.pos_after_win_leave[1], self.pos_after_win_leave[2])
  end
end

function Canvas:focus()
  if self.winid then
    local current_winid = api.nvim_get_current_win()
    if current_winid ~= self.winid then
      if current_winid ~= self.edit_winid then
        log.debug("winid=%s setting edit_winid to %s, old=%s", self.winid, current_winid, self.edit_winid)
        self.edit_winid = current_winid
      end
      api.nvim_set_current_win(self.winid)
    end
  end
end

function Canvas:focus_edit_window()
  if self:get_edit_winid() then
    api.nvim_set_current_win(self.edit_winid)
  end
end

---@return boolean has_focus
function Canvas:has_focus()
  return self.winid and self.winid == api.nvim_get_current_win() or false
end

function Canvas:close()
  -- if the canvas is the only window, it cannot be closed
  if not self.winid or #api.nvim_list_wins() == 1 then
    return
  end

  local ok = pcall(api.nvim_win_close, self.winid, true)
  if not ok then
    log.error("error closing window %q", self.winid)
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
  local esc_term_codes = api.nvim_replace_termcodes("<ESC>", true, false, true)

  ---@return integer from, integer to
  function Canvas:get_selected_rows()
    local mode = api.nvim_get_mode().mode --[[@as string]]
    if mode == "v" or mode == "V" then
      local from = fn.getpos("v")[2] --[[@as integer]]
      local to = api.nvim_win_get_cursor(self.winid)[1]
      if from > to then
        from, to = to, from
      end

      api.nvim_feedkeys(esc_term_codes, "n", true)
      return from, to
    else
      local row = api.nvim_win_get_cursor(self.winid)[1]
      return row, row
    end
  end
end

---@private
function Canvas:_move_cursor_to_name()
  if not self.winid then
    return
  end
  local row, col = unpack(api.nvim_win_get_cursor(self.winid))
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
    api.nvim_win_set_cursor(self.winid, { row, column })
  end
end

---@param row integer
function Canvas:focus_row(row)
  local column = api.nvim_win_get_cursor(self.winid)[2]
  set_cursor_position(self.winid, row, column)
end

return Canvas

local config = require("ya-tree.config").config
local events = require("ya-tree.events")
local event = require("ya-tree.events.event").ya_tree
local log = require("ya-tree.log")("ui")

local api = vim.api

local ns = api.nvim_create_namespace("YaTreeHighlights")

---@type {name: string, value: string|boolean}[]
local buf_options = {
  { name = "bufhidden", value = "hide" }, -- must be hide and not wipe for Canvas:restore and particularly Canvas:move_buffer_to_edit_window to work
  { name = "buflisted", value = false },
  { name = "filetype", value = "YaTree" },
  { name = "buftype", value = "nofile" },
  { name = "modifiable", value = false },
  { name = "swapfile", value = false },
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

---@class Yat.Ui.Canvas
---@field public position Yat.Ui.Position
---@field private winid? integer
---@field private edit_winid? integer
---@field private bufnr? integer
---@field private window_augroup? integer
---@field private previous_row integer
---@field private pos_after_win_leave? integer[]
---@field private size integer
---@field private sidebar Yat.Sidebar
local Canvas = {}
Canvas.__index = Canvas

Canvas.__tostring = function(self)
  return string.format("(winid=%s, bufnr=%s, edit_winid=%s, sidebar=[%s])", self.winid, self.bufnr, self.edit_winid, tostring(self.sidebar))
end

---@return Yat.Ui.Canvas canvas
function Canvas:new()
  local this = setmetatable({}, self)
  this.previous_row = 1
  this.position = config.view.position
  this.size = config.view.size
  return this
end

---@return boolean
function Canvas:is_on_side()
  return self.position == "left" or self.position == "right"
end

---@return integer height, integer width
function Canvas:get_size()
  return api.nvim_win_get_height(self.winid), api.nvim_win_get_width(self.winid)
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
---@return boolean is_loaded
function Canvas:_is_buffer_loaded()
  return self.bufnr and api.nvim_buf_is_loaded(self.bufnr) or false
end

---@private
function Canvas:_create_buffer()
  self.bufnr = api.nvim_create_buf(false, false)
  log.debug("created buffer %s", self.bufnr)
  api.nvim_buf_set_name(self.bufnr, "YaTree://YaTree" .. self.bufnr)

  for _, v in ipairs(buf_options) do
    api.nvim_buf_set_option(self.bufnr, v.name, v.value)
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
  if self.winid and self.edit_winid and self.bufnr then
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

function Canvas:resize()
  if self:is_on_side() then
    api.nvim_win_set_width(self.winid, self.size)
  else
    api.nvim_win_set_height(self.winid, self.size)
  end
end

local positions_to_wincmd = { left = "H", bottom = "J", top = "K", right = "L" }

---@private
---@param position? Yat.Ui.Position
function Canvas:_create_window(position)
  local winid = api.nvim_get_current_win()
  if winid ~= self.edit_winid then
    local old_edit_winid = self.edit_winid
    self.edit_winid = winid
    log.debug("setting edit_winid to %s, old=%s", self.edit_winid, old_edit_winid)
  end

  self.position = position or self.position
  vim.cmd("noautocmd vsplit")
  self.winid = api.nvim_get_current_win()
  vim.cmd("noautocmd wincmd " .. positions_to_wincmd[self.position])
  self:resize()
  log.debug("created window %s", self.winid)
  self:_set_window_options()
end

---@private
function Canvas:_set_window_options()
  win_set_buf_noautocmd(self.winid, self.bufnr)

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
  vim.cmd("noautocmd vsplit")
  self.edit_winid = api.nvim_get_current_win()
  api.nvim_win_call(self.winid, function()
    vim.cmd("noautocmd wincmd " .. positions_to_wincmd[self.position])
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
        pcall(vim.cmd, "normal! zb")
      elseif row < (win_height / 2) then
        pcall(vim.cmd, "normal! zz")
      end
    end
  end)
end

---@class Yat.Ui.Canvas.OpenArgs
---@field position? Yat.Ui.Position
---@field size? integer

---@param sidebar Yat.Sidebar
---@param opts? Yat.Ui.Canvas.OpenArgs
---  - {opts.position?} `YaTreeCanvas.Position`
---  - {opts.size?} `integer`
function Canvas:open(sidebar, opts)
  if self:is_open() then
    return
  end

  opts = opts or {}
  if opts.size then
    self.size = opts.size
  end
  self:_create_buffer()
  self:_create_window(opts.position)
  self.sidebar = sidebar

  self:draw()
  if self.pos_after_win_leave then
    set_cursor_position(self.winid, self.pos_after_win_leave[1], self.pos_after_win_leave[2])
  end

  events.fire_yatree_event(event.YA_TREE_WINDOW_OPENED, { winid = self.winid })
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

function Canvas:draw()
  local width = api.nvim_win_get_width(self.winid)
  local lines, highlights = self.sidebar:render(config, width)
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

---@param tree Yat.Tree
---@return boolean is_rendered
function Canvas:is_tree_rendered(tree)
  return self.sidebar:is_tree_rendered(tree)
end

---@param tree Yat.Tree
---@param node Yat.Node
---@return boolean is_rendered
function Canvas:is_node_rendered(tree, node)
  return self.sidebar:is_node_rendered(tree, node)
end

---@return Yat.Tree? current_tree
---@return Yat.Node? current_node
function Canvas:get_current_tree_and_node()
  local row = api.nvim_win_get_cursor(self.winid)[1]
  return self.sidebar:get_current_tree_and_node(row)
end

do
  local esc_term_codes = api.nvim_replace_termcodes("<ESC>", true, false, true)

  ---@return Yat.Node[] nodes
  function Canvas:get_selected_nodes()
    local mode = api.nvim_get_mode().mode --[[@as string]]
    if mode == "v" or mode == "V" then
      local from = vim.fn.getpos("v")[2] --[[@as integer]]
      local to = api.nvim_win_get_cursor(self.winid)[1]
      if from > to then
        from, to = to, from
      end

      local nodes = self.sidebar:get_nodes(from, to)
      api.nvim_feedkeys(esc_term_codes, "n", true)
      return nodes
    else
      local row = api.nvim_win_get_cursor(self.winid)[1]
      local node = self.sidebar:get_node(row)
      return node and { node } or {}
    end
  end
end

---@private
function Canvas:_move_cursor_to_name()
  if not self.winid then
    return
  end
  local row, col = unpack(api.nvim_win_get_cursor(self.winid))
  local tree, node = self.sidebar:get_current_tree_and_node(row)
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

---@param tree Yat.Tree
---@param node Yat.Node
function Canvas:focus_node(tree, node)
  -- if the node has been hidden after a toggle
  -- go upwards in the tree until we find one that's displayed
  while node and node:is_hidden(config) and node.parent do
    node = node.parent
  end
  if node then
    local row = self.sidebar:get_row_of_node(tree, node)
    if row then
      log.debug("node %s is at line %s", node.path, row)
      local column
      -- don't move the cursor on root node
      if config.move_cursor_to_name and node ~= tree.root then
        local line = api.nvim_buf_get_lines(self.bufnr, row - 1, row, false)[1]
        if line then
          column = (line:find(node.name, 1, true) or 0) - 1
        end
      end
      if not column or column == -1 then
        column = api.nvim_win_get_cursor(self.winid)[2]
      end
      set_cursor_position(self.winid, row, column)
    end
  end
end

---@param row integer
function Canvas:focus_row(row)
  local column = api.nvim_win_get_cursor(self.winid)[2]
  set_cursor_position(self.winid, row, column)
end

function Canvas.setup()
  config = require("ya-tree.config").config
end

return Canvas

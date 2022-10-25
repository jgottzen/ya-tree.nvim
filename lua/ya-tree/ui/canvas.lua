local config = require("ya-tree.config").config
local events = require("ya-tree.events")
local event = require("ya-tree.events.event").ya_tree
local log = require("ya-tree.log")("ui")

local api = vim.api

local ns = api.nvim_create_namespace("YaTreeHighlights") --[[@as integer]]

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

local file_min_diagnostic_severity = config.renderers.builtin.diagnostics.directory_min_severity
local directory_min_diagnstic_severrity = config.renderers.builtin.diagnostics.file_min_severity

---@class Yat.Ui.Canvas
---@field public tree_type Yat.Trees.Type
---@field public position Yat.Ui.Position
---@field private winid? integer
---@field private edit_winid? integer
---@field private bufnr? integer
---@field private window_augroup? integer
---@field private previous_row integer
---@field private size integer
---@field private nodes Yat.Node[]
---@field private node_path_to_index_lookup table<string, integer>
local Canvas = {}
Canvas.__index = Canvas

---@param self Yat.Ui.Canvas
---@return string
Canvas.__tostring = function(self)
  return string.format(
    "(winid=%s, bufnr=%s, edit_winid=%s, tree_type=%s, nodes=[%s, %s])",
    self.winid,
    self.bufnr,
    self.edit_winid,
    self.tree_type,
    self.nodes and #self.nodes or 0,
    self.nodes and tostring(self.nodes[1]) or "nil"
  )
end

---@return Yat.Ui.Canvas canvas
function Canvas:new()
  local this = setmetatable({}, self)
  this.position = config.view.position
  this.size = config.view.size
  this.nodes = {}
  this.node_path_to_index_lookup = {}
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
  self.bufnr = api.nvim_create_buf(false, false) --[[@as integer]]
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
    api.nvim_win_set_buf(self.edit_winid, bufnr)
    api.nvim_set_current_win(self.edit_winid)
  end
end

---@private
function Canvas:_set_window_options()
  win_set_buf_noautocmd(self.winid, self.bufnr)

  win_options.number = config.view.number
  win_options.relativenumber = config.view.relativenumber
  for k, v in pairs(win_options) do
    vim.wo[k] = v
  end

  self.window_augroup = api.nvim_create_augroup("YaTreeCanvas_Window_" .. self.winid, { clear = true }) --[[@as integer]]
  api.nvim_create_autocmd("WinLeave", {
    group = self.window_augroup,
    buffer = self.bufnr,
    callback = function()
      if self.edit_winid then
        self.size = self:is_on_side() and api.nvim_win_get_width(self.winid) or api.nvim_win_get_height(self.winid) --[[@as integer]]
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
    ok = pcall(api.nvim_buf_delete, self.bufnr, { force = true })
    if not ok then
      log.error("error deleting buffer %s", self.bufnr)
    end
    self.bufnr = nil
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
  local winid = api.nvim_get_current_win() --[[@as integer]]
  if winid ~= self.edit_winid then
    local old_edit_winid = self.edit_winid
    self.edit_winid = winid
    log.debug("setting edit_winid to %s, old=%s", self.edit_winid, old_edit_winid)
  end

  self.position = position or self.position
  vim.cmd("noautocmd vsplit")
  self.winid = api.nvim_get_current_win() --[[@as integer]]
  vim.cmd("noautocmd wincmd " .. positions_to_wincmd[self.position])
  self:resize()
  log.debug("created window %s", self.winid)
  self:_set_window_options()
end

function Canvas:create_edit_window()
  vim.cmd("noautocmd vsplit")
  self.edit_winid = api.nvim_get_current_win() --[[@as integer]]
  api.nvim_win_call(self.winid, function()
    vim.cmd("noautocmd wincmd " .. positions_to_wincmd[self.position])
    self:resize()
  end)
  log.debug("created edit window %s", self.edit_winid)
end

---@class Yat.Ui.Canvas.OpenArgs
---@field position? Yat.Ui.Position
---@field size? integer

---@param tree Yat.Tree
---@param opts? Yat.Ui.Canvas.OpenArgs
---  - {opts.position?} `YaTreeCanvas.Position`
---  - {opts.size?} `integer`
function Canvas:open(tree, opts)
  if self:is_open() then
    return
  end

  opts = opts or {}
  if opts.size then
    self.size = opts.size
  end
  self:_create_buffer()
  self:_create_window(opts.position)

  self:draw(tree)

  events.fire_yatree_event(event.YA_TREE_WINDOW_OPENED, { winid = self.winid })
end

function Canvas:focus()
  if self.winid then
    local current_winid = api.nvim_get_current_win() --[[@as integer]]
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

---@param tree Yat.Tree
function Canvas:draw(tree)
  self.tree_type = tree.TYPE
  log.debug("creating %q canvas tree with root node %s", tree.TYPE, tree.root.path)
  local lines, highlights, extra
  lines, highlights, self.nodes, extra = tree:render(config)
  directory_min_diagnstic_severrity = extra.directory_min_diagnstic_severrity
  file_min_diagnostic_severity = extra.file_min_diagnostic_severity
  self.node_path_to_index_lookup = {}
  for index, node in ipairs(self.nodes) do
    self.node_path_to_index_lookup[node.path] = index
  end

  api.nvim_buf_set_option(self.bufnr, "modifiable", true)
  api.nvim_buf_clear_namespace(self.bufnr, ns, 0, -1)

  api.nvim_buf_set_lines(self.bufnr, 0, -1, false, lines)

  for linenr, line_highlights in ipairs(highlights) do
    for _, highlight in ipairs(line_highlights) do
      -- guard against bugged out renderer highlights, which will cause an avalanche of errors...
      if not highlight.name then
        log.error("missing highlight name for node=%s, hl=%s", tostring(self.nodes[linenr]), highlight)
      else
        api.nvim_buf_add_highlight(self.bufnr, ns, highlight.name, linenr - 1, highlight.from, highlight.to)
      end
    end
  end

  api.nvim_buf_set_option(self.bufnr, "modifiable", false)
end

---@param node Yat.Node
---@return boolean visible
function Canvas:is_node_rendered(node)
  return self.node_path_to_index_lookup[node.path] ~= nil
end

---@private
---@return Yat.Node|nil node, integer row, integer column
function Canvas:_get_current_node_and_position()
  if not self.winid then
    return nil, 1, 0
  end

  local row, column = unpack(api.nvim_win_get_cursor(self.winid)) --[[@as integer]]
  local node = self.nodes[row]
  return node, row, column
end

---@return Yat.Node|nil node
function Canvas:get_current_node()
  local node = self:_get_current_node_and_position()
  return node
end

do
  local esc_term_codes = api.nvim_replace_termcodes("<ESC>", true, false, true) --[[@as string]]

  ---@return Yat.Node[] nodes
  function Canvas:get_selected_nodes()
    local mode = api.nvim_get_mode().mode --[[@as string]]
    if mode == "v" or mode == "V" then
      local from = vim.fn.getpos("v")[2] --[[@as integer]]
      local to = api.nvim_win_get_cursor(self.winid)[1] --[[@as integer]]
      if from > to then
        from, to = to, from
      end

      ---@type Yat.Node[]
      local nodes = {}
      for index = from, to do
        local node = self.nodes[index]
        if node then
          nodes[#nodes + 1] = node
        end
      end

      api.nvim_feedkeys(esc_term_codes, "n", true)

      return nodes
    else
      return { self:get_current_node() }
    end
  end
end

---@private
function Canvas:_move_cursor_to_name()
  if not self.winid then
    return
  end
  local node, row, col = self:_get_current_node_and_position()
  if not node or row == self.previous_row then
    return
  end

  self.previous_row = row
  -- don't move the cursor on the first line
  if row == 1 then
    return
  end

  local line = api.nvim_get_current_line() --[[@as string]]
  local column = (line:find(node.name, 1, true) or 0) - 1
  if column > 0 and column ~= col then
    api.nvim_win_set_cursor(self.winid, { row, column })
  end
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
      local win_height = api.nvim_win_get_height(winid) --[[@as integer]]
      if win_height > row then
        pcall(vim.cmd, "normal! zb")
      elseif row < (win_height / 2) then
        pcall(vim.cmd, "normal! zz")
      end
    end
  end)
end

---@param node Yat.Node
function Canvas:focus_node(node)
  -- if the node has been hidden after a toggle
  -- go upwards in the tree until we find one that's displayed
  while node and node:is_hidden(config) and node.parent do
    node = node.parent
  end
  if node then
    local row = self.node_path_to_index_lookup[node.path]
    log.debug("node %s is at index %s", node.path, row)
    if row then
      local column
      -- don't move the cursor on the first line
      if config.move_cursor_to_name and row > 2 then
        local line = api.nvim_buf_get_lines(self.bufnr, row - 1, row, false)[1] --[[@as string?]]
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

---@param node Yat.Node
function Canvas:focus_parent(node)
  if not node or node == self.nodes[1] or not node.parent then
    return
  end

  local row = self.node_path_to_index_lookup[node.parent.path]
  if row then
    local column = api.nvim_win_get_cursor(self.winid)[2] --[[@as integer]]
    set_cursor_position(self.winid, row, column)
  end
end

---@param node Yat.Node
function Canvas:focus_prev_sibling(node)
  if not node or not node.parent or not node.parent:has_children() then
    return
  end

  for _, prev in node.parent:iterate_children({ reverse = true, from = node }) do
    if not node:is_hidden(config) then
      local row = self.node_path_to_index_lookup[prev.path]
      if row then
        local column = api.nvim_win_get_cursor(self.winid)[2] --[[@as integer]]
        set_cursor_position(self.winid, row, column)
        return
      end
    end
  end
end

---@param node Yat.Node
function Canvas:focus_next_sibling(node)
  if not node or not node.parent or not node.parent:has_children() then
    return
  end

  for _, next in node.parent:iterate_children({ from = node }) do
    if not node:is_hidden(config) then
      local row = self.node_path_to_index_lookup[next.path]
      if row then
        local column = api.nvim_win_get_cursor(self.winid)[2] --[[@as integer]]
        set_cursor_position(self.winid, row, column)
        return
      end
    end
  end
end

---@param node Yat.Node
function Canvas:focus_first_sibling(node)
  if not node or not node.parent or not node.parent:has_children() then
    return
  end

  for _, next in node.parent:iterate_children() do
    if not node:is_hidden(config) then
      local row = self.node_path_to_index_lookup[next.path]
      if row then
        local column = api.nvim_win_get_cursor(self.winid)[2] --[[@as integer]]
        set_cursor_position(self.winid, row, column)
        return
      end
    end
  end
end

---@param node Yat.Node
function Canvas:focus_last_sibling(node)
  if not node or not node.parent or not node.parent:has_children() then
    return
  end

  for _, prev in node.parent:iterate_children({ reverse = true }) do
    if not node:is_hidden(config) then
      local row = self.node_path_to_index_lookup[prev.path]
      if row then
        local column = api.nvim_win_get_cursor(self.winid)[2] --[[@as integer]]
        set_cursor_position(self.winid, row, column)
        return
      end
    end
  end
end

---@param node Yat.Node
function Canvas:focus_prev_git_item(node)
  local current_row = self.node_path_to_index_lookup[node.path]
  for row = current_row - 1, 1, -1 do
    if self.nodes[row]:git_status() then
      local column = api.nvim_win_get_cursor(self.winid)[2] --[[@as integer]]
      set_cursor_position(self.winid, row, column)
      return
    end
  end
end

---@param node Yat.Node
function Canvas:focus_next_git_item(node)
  local current_row = self.node_path_to_index_lookup[node.path]
  for row = current_row + 1, #self.nodes do
    if self.nodes[row]:git_status() then
      local column = api.nvim_win_get_cursor(self.winid)[2] --[[@as integer]]
      set_cursor_position(self.winid, row, column)
      return
    end
  end
end

---@param node Yat.Node
function Canvas:focus_prev_diagnostic_item(node)
  local current_row = self.node_path_to_index_lookup[node.path]
  for row = current_row - 1, 1, -1 do
    local node_at_row = self.nodes[row]
    local severity = node_at_row:diagnostic_severity()
    if severity then
      local target_severity = node_at_row:is_directory() and directory_min_diagnstic_severrity or file_min_diagnostic_severity
      if severity <= target_severity then
        local column = api.nvim_win_get_cursor(self.winid)[2] --[[@as integer]]
        set_cursor_position(self.winid, row, column)
        return
      end
    end
  end
end

---@param node Yat.Node
function Canvas:focus_next_diagnostic_item(node)
  local current_row = self.node_path_to_index_lookup[node.path]
  for row = current_row + 1, #self.nodes do
    local node_at_row = self.nodes[row]
    local severity = node_at_row:diagnostic_severity()
    if severity then
      local target_severity = node_at_row:is_directory() and directory_min_diagnstic_severrity or file_min_diagnostic_severity
      if severity <= target_severity then
        local column = api.nvim_win_get_cursor(self.winid)[2] --[[@as integer]]
        set_cursor_position(self.winid, row, column)
        return
      end
    end
  end
end

function Canvas.setup()
  config = require("ya-tree.config").config
end

return Canvas

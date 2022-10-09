local config = require("ya-tree.config").config
local events = require("ya-tree.events")
local event = require("ya-tree.events.event").ya_tree
local utils = require("ya-tree.utils")
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
  -- number and relativenumber are taken directly from config
  number = config.view.number,
  relativenumber = config.view.relativenumber,
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
    "StatusLine:YaTreeStatusLine",
    "StatusLineNC:YaTreeStatuslineNC",
  }, ","),
}

local file_min_diagnostic_severity = config.renderers.builtin.diagnostics.min_severity
local directory_min_diagnstic_severrity = config.renderers.builtin.diagnostics.min_severity

---@alias Yat.Ui.Canvas.Position "left" | "right" | "top" | "bottom"

---@class Yat.Ui.Canvas
---@field public tree_type Yat.Trees.Type
---@field public position Yat.Ui.Canvas.Position
---@field private winid? number
---@field private edit_winid? number
---@field private bufnr? number
---@field private window_augroup? number
---@field private previous_row number
---@field private size number
---@field private nodes Yat.Node[]
---@field private node_path_to_index_lookup table<string, integer>
---@field private directory_renderers Yat.Ui.Canvas.Renderer[]
---@field private file_renderers Yat.Ui.Canvas.Renderer[]
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

---@return number height, number width
function Canvas:get_size()
  return api.nvim_win_get_height(self.winid), api.nvim_win_get_width(self.winid)
end

---@return number|nil winid
function Canvas:get_edit_winid()
  if self.edit_winid and not api.nvim_win_is_valid(self.edit_winid) then
    self.edit_winid = nil
  end
  return self.edit_winid
end

---@param winid number
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
---@param hijack_buffer boolean
function Canvas:_create_buffer(hijack_buffer)
  if hijack_buffer then
    self.bufnr = api.nvim_get_current_buf() --[[@as number]]
    -- need to remove the "readonly" option, otherwise a warning might be raised
    api.nvim_buf_set_option(self.bufnr, "modifiable", true)
    api.nvim_buf_set_option(self.bufnr, "readonly", false)
    log.debug("hijacked buffer %s", self.bufnr)
  else
    self.bufnr = api.nvim_create_buf(false, false) --[[@as number]]
    log.debug("created buffer %s", self.bufnr)
  end
  api.nvim_buf_set_name(self.bufnr, "YaTree://YaTree" .. self.bufnr)

  for _, v in ipairs(buf_options) do
    api.nvim_buf_set_option(self.bufnr, v.name, v.value)
  end

  require("ya-tree.actions").apply_mappings(self.bufnr)
end

---@param winid number
---@param bufnr number
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

---@param bufnr number
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

  self.window_augroup = api.nvim_create_augroup("YaTreeCanvas_Window_" .. self.winid, { clear = true }) --[[@as number]]
  api.nvim_create_autocmd("WinLeave", {
    group = self.window_augroup,
    buffer = self.bufnr,
    callback = function()
      if self.edit_winid then
        self.size = self:is_on_side() and api.nvim_win_get_width(self.winid) or api.nvim_win_get_height(self.winid) --[[@as number]]
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
---@param position? Yat.Ui.Canvas.Position
function Canvas:_create_window(position)
  local winid = api.nvim_get_current_win() --[[@as number]]
  if winid ~= self.edit_winid then
    local old_edit_winid = self.edit_winid
    self.edit_winid = winid
    log.debug("setting edit_winid to %s, old=%s", self.edit_winid, old_edit_winid)
  end

  self.position = position or self.position
  vim.cmd("noautocmd vsplit")
  self.winid = api.nvim_get_current_win() --[[@as number]]
  vim.cmd("noautocmd wincmd " .. positions_to_wincmd[self.position])
  self:resize()
  log.debug("created window %s", self.winid)
  self:_set_window_options()
end

function Canvas:create_edit_window()
  vim.cmd("noautocmd vsplit")
  self.edit_winid = api.nvim_get_current_win() --[[@as number]]
  api.nvim_win_call(self.winid, function()
    vim.cmd("noautocmd wincmd " .. positions_to_wincmd[self.position])
    self:resize()
  end)
  log.debug("created edit window %s", self.edit_winid)
end

---@class Yat.Ui.Canvas.OpenArgs
---@field hijack_buffer? boolean
---@field position? Yat.Ui.Canvas.Position
---@field size? integer

---@param tree Yat.Tree
---@param opts? Yat.Ui.Canvas.OpenArgs
---  - {opts.hijack_buffer?} `boolean`
---  - {opts.position?} `YaTreeCanvas.Position`
---  - {opts.size?} `integer`
function Canvas:open(tree, opts)
  if self:is_open() then
    return
  end

  opts = opts or {}
  if not self:_is_buffer_loaded() then
    self:_create_buffer(opts.hijack_buffer)
  end

  if opts.size then
    self.size = opts.size
  end
  if opts.hijack_buffer then
    self.winid = api.nvim_get_current_win() --[[@as number]]
    log.debug("hijacking current window %s for canvas", self.winid)
    self.edit_winid = nil
    self:_set_window_options()
  else
    self:_create_window(opts.position)
  end

  self:render(tree)

  events.fire_yatree_event(event.YA_TREE_WINDOW_OPENED, { winid = self.winid })
end

function Canvas:focus()
  if self.winid then
    local current_winid = api.nvim_get_current_win() --[[@as number]]
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

function Canvas:delete()
  self:close()
  if self.bufnr then
    local ok = pcall(api.nvim_buf_delete, self.bufnr, { force = true })
    if ok then
      log.debug("deleted canvas buffer %s", self.bufnr)
    else
      log.error("error deleting buffer %s", self.bufnr)
    end
    self.bufnr = nil
  end
end

---@class Yat.Ui.HighlightGroup
---@field name string
---@field from integer
---@field to integer

---@param pos number
---@param padding string
---@param text string
---@param highlight string
---@return number end_position, string content, Yat.Ui.HighlightGroup highlight
local function line_part(pos, padding, text, highlight)
  local from = pos + #padding
  local size = #text
  local group = {
    name = highlight,
    from = from,
    to = from + size,
  }
  return group.to, string.format("%s%s", padding, text), group
end

---@param node Yat.Node
---@param context Yat.Ui.RenderContext
---@param renderers Yat.Ui.Canvas.Renderer[]
---@return string text, Yat.Ui.HighlightGroup[] highlights
local function render_node(node, context, renderers)
  ---@type string[]
  local content = {}
  ---@type Yat.Ui.HighlightGroup[]
  local highlights = {}

  local pos = 0
  for _, renderer in ipairs(renderers) do
    local results = renderer.fn(node, context, renderer.config)
    if results then
      for _, result in ipairs(results) do
        if result.text then
          if not result.highlight then
            log.error("renderer %s didn't return a highlight name for node %q, renderer returned %s", renderer.name, node.path, result)
          end
          pos, content[#content + 1], highlights[#highlights + 1] = line_part(pos, result.padding or "", result.text, result.highlight)
        end
      end
    end
  end

  return table.concat(content), highlights
end

---@class Yat.Ui.RenderContext
---@field tree_type Yat.Trees.Type
---@field config Yat.Config
---@field depth integer
---@field last_child boolean

---@private
---@param tree Yat.Tree
---@return string[] lines, Yat.Ui.HighlightGroup[][] highlights
function Canvas:_render_tree(tree)
  log.debug("creating %q canvas tree with root node %s", self.tree_type, tree.root.path)
  self.nodes, self.node_path_to_index_lookup = {}, {}
  ---@type string[]
  local lines = {}
  ---@type Yat.Ui.HighlightGroup[][]
  local highlights = {}
  local linenr = 0
  ---@type Yat.Ui.RenderContext
  local context = {
    tree_type = self.tree_type,
    config = config,
  }

  ---@param node Yat.Node
  ---@param depth integer
  ---@param last_child boolean
  local function append_node(node, depth, last_child)
    if not node:is_hidden(config) or depth == 0 then
      linenr = linenr + 1
      context.depth = depth
      context.last_child = last_child
      self.nodes[linenr] = node
      self.node_path_to_index_lookup[node.path] = linenr
      local has_children = node:has_children()
      lines[linenr], highlights[linenr] = render_node(node, context, has_children and self.directory_renderers or self.file_renderers)

      if has_children and node.expanded then
        local nr_of_children = #node:children()
        for i, child in node:iterate_children() do
          append_node(child, depth + 1, i == nr_of_children)
        end
      end
    end
  end

  append_node(tree.root, 0, false)

  return lines, highlights
end

---@param tree Yat.Tree
function Canvas:render(tree)
  if self.tree_type ~= tree.TYPE or not (self.directory_renderers and self.file_renderers) then
    self:_set_renderers_for_tree(tree.TYPE)
  end
  self.tree_type = tree.TYPE
  local lines, highlights = self:_render_tree(tree)

  api.nvim_buf_set_option(self.bufnr, "modifiable", true)
  api.nvim_buf_clear_namespace(self.bufnr, ns, 0, -1)

  api.nvim_buf_set_lines(self.bufnr, 0, -1, false, lines)

  for linenr, line_highlights in ipairs(highlights) do
    for _, highlight in ipairs(line_highlights) do
      -- guard against bugged out renderer highlights, which will cause an avalanche of errors...
      if not highlight.name then
        log.error("missing highlight name for node=%q, hl=%s", self.nodes[linenr].path, highlight)
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
---@return Yat.Node|nil node, number row, number column
function Canvas:_get_current_node_and_position()
  if not self.winid then
    return nil, 1, 0
  end

  local row, column = unpack(api.nvim_win_get_cursor(self.winid)) --[[@as number]]
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
      local from = vim.fn.getpos("v")[2] --[[@as number]]
      local to = api.nvim_win_get_cursor(self.winid)[1] --[[@as number]]
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

---@param winid number
---@param row number
---@param col number
local function set_cursor_position(winid, row, col)
  -- avoids the cursor moving left when switching to the canvas window and then back,
  -- happens with floating windows
  api.nvim_win_call(winid, function()
    local ok = pcall(api.nvim_win_set_cursor, winid, { row, col })
    if ok then
      local win_height = api.nvim_win_get_height(winid) --[[@as number]]
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
    local column = api.nvim_win_get_cursor(self.winid)[2] --[[@as number]]
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
        local column = api.nvim_win_get_cursor(self.winid)[2] --[[@as number]]
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
        local column = api.nvim_win_get_cursor(self.winid)[2] --[[@as number]]
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
        local column = api.nvim_win_get_cursor(self.winid)[2] --[[@as number]]
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
        local column = api.nvim_win_get_cursor(self.winid)[2] --[[@as number]]
        set_cursor_position(self.winid, row, column)
        return
      end
    end
  end
end

function Canvas:focus_prev_git_item()
  local current_row, column = unpack(api.nvim_win_get_cursor(self.winid)) --[[@as number]]
  for row = current_row - 1, 1, -1 do
    if self.nodes[row]:git_status() then
      set_cursor_position(self.winid, row, column)
      return
    end
  end
end

function Canvas:focus_next_git_item()
  local current_row, column = unpack(api.nvim_win_get_cursor(self.winid)) --[[@as number]]
  for row = current_row + 1, #self.nodes do
    if self.nodes[row]:git_status() then
      set_cursor_position(self.winid, row, column)
      return
    end
  end
end

function Canvas:focus_prev_diagnostic_item()
  local current_row, column = unpack(api.nvim_win_get_cursor(self.winid)) --[[@as number]]
  for row = current_row - 1, 1, -1 do
    local node = self.nodes[row]
    local severity = node:diagnostic_severity()
    if severity then
      local target_severity = node:is_directory() and directory_min_diagnstic_severrity or file_min_diagnostic_severity
      if severity <= target_severity then
        set_cursor_position(self.winid, row, column)
        return
      end
    end
  end
end

function Canvas:focus_next_diagnostic_item()
  local current_row, column = unpack(api.nvim_win_get_cursor(self.winid)) --[[@as number]]
  for row = current_row + 1, #self.nodes do
    local node = self.nodes[row]
    local severity = node:diagnostic_severity()
    if severity then
      local target_severity = node:is_directory() and directory_min_diagnstic_severrity or file_min_diagnostic_severity
      if severity <= target_severity then
        set_cursor_position(self.winid, row, column)
        return
      end
    end
  end
end

---@class Yat.Ui.Canvas.Renderer
---@field name Yat.Ui.Renderer.Name
---@field fn Yat.Ui.RendererFunction
---@field config? Yat.Config.BaseRendererConfig

do
  local renderers = require("ya-tree.ui.renderers")

  ---@param renderer_type string
  ---@param raw_renderer Yat.Config.Trees.Renderer
  ---@return Yat.Ui.Canvas.Renderer|nil renderer
  local function create_renderer(renderer_type, raw_renderer)
    local name = raw_renderer.name
    if type(name) == "string" then
      local renderer_info = renderers.get_renderer(name)
      if renderer_info then
        ---@type Yat.Ui.Canvas.Renderer
        local renderer = {
          name = name,
          fn = renderer_info.fn,
          config = vim.deepcopy(renderer_info.config),
        }
        if raw_renderer.override then
          for k, v in pairs(raw_renderer.override) do
            if type(k) == "string" then
              log.debug("overriding %q renderer %q config value for %q with %s", renderer_type, renderer.name, k, v)
              renderer.config[k] = v
            end
          end
        end

        return renderer
      end
    end
    utils.warn("Invalid renderer:\n" .. vim.inspect(raw_renderer))
  end

  ---@type Yat.Ui.Canvas.Renderer[], Yat.Ui.Canvas.Renderer[]
  local default_directory_renderers, default_file_renderers = {}, {}
  ---@type table<Yat.Trees.Type, { directory: Yat.Config.Trees.Renderer[], file: Yat.Config.Trees.Renderer[] }>
  local tree_renderers = {}
  local highlight_open_file = false

  ---@private
  ---@param tree_type Yat.Trees.Type
  function Canvas:_set_renderers_for_tree(tree_type)
    local _renderers = tree_renderers[tree_type]
    if not _renderers then
      _renderers = {}
      local tree_config = config.trees[tree_type]
      if tree_config and tree_config.renderers and (tree_config.renderers.directory or tree_config.renderers.file) then
        if tree_config.renderers.directory then
          _renderers.directory = {}
          for _, directory_renderer in ipairs(tree_config.renderers.directory) do
            local renderer = create_renderer("directory", directory_renderer)
            if renderer then
              _renderers.directory[#_renderers.directory + 1] = renderer
            end
          end
        end

        if tree_config.renderers.file then
          _renderers.file = {}
          for _, file_renderer in ipairs(tree_config.renderers.file) do
            local renderer = create_renderer("file", file_renderer)
            if renderer then
              _renderers.file[#_renderers.file + 1] = renderer
            end
          end
        end
      end

      _renderers.directory = _renderers.directory or default_directory_renderers
      _renderers.file = _renderers.file or default_file_renderers
      tree_renderers[tree_type] = _renderers
    end

    self.directory_renderers = _renderers.directory
    self.file_renderers = _renderers.file

    for _, renderer in ipairs(self.directory_renderers) do
      if renderer.name == "diagnostics" then
        local renderer_config = renderer.config --[[@as Yat.Config.Renderers.Builtin.Diagnostics]]
        directory_min_diagnstic_severrity = renderer_config.min_severity or config.renderers.builtin.diagnostics.min_severity
      end
    end
    for _, renderer in ipairs(self.file_renderers) do
      if renderer.name == "name" then
        local renderer_config = renderer.config --[[@as Yat.Config.Renderers.Builtin.Name]]
        highlight_open_file = renderer_config.highlight_open_file
      elseif renderer.name == "diagnostics" then
        local renderer_config = renderer.config --[[@as Yat.Config.Renderers.Builtin.Diagnostics]]
        file_min_diagnostic_severity = renderer_config.min_severity or config.renderers.builtin.diagnostics.min_severity
      end
    end
  end

  function Canvas.setup()
    config = require("ya-tree.config").config

    renderers.setup(config)

    -- reset the renderer arrays, since the setup can be called repeatedly
    ---@type Yat.Ui.Canvas.Renderer[], Yat.Ui.Canvas.Renderer[]
    default_directory_renderers, default_file_renderers = {}, {}

    for _, directory_renderer in ipairs(config.view.default_renderers.directory) do
      local renderer = create_renderer("directory", directory_renderer)
      if renderer then
        default_directory_renderers[#default_directory_renderers + 1] = renderer
      end
    end
    log.trace("default directory renderers=%s", default_directory_renderers)

    for _, file_renderer in ipairs(config.view.default_renderers.file) do
      local renderer = create_renderer("file", file_renderer)
      if renderer then
        default_file_renderers[#default_file_renderers + 1] = renderer
      end
    end
    log.trace("default file renderers=%s", default_file_renderers)
  end

  ---@return boolean enabled
  function Canvas.is_highlight_open_file_enabled()
    return highlight_open_file
  end
end

return Canvas

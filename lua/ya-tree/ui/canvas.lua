local config = require("ya-tree.config").config
local utils = require("ya-tree.utils")
local log = require("ya-tree.log")

local api = vim.api
local fn = vim.fn

local ns = api.nvim_create_namespace("YaTreeHighlights")

local barbar_exists = false

---@class BarBarState
---@field set_offset fun(width: number, text?: string): nil
local barbar_state = {}

---@type {name: string, value: string|boolean}[]
local buf_options = {
  { name = "bufhidden", value = "hide" },
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

local tab_var_barbar_set_name = "_YaTreeBarbar"

---@alias YaTreeCanvasDisplayMode "tree"|"search"|"buffers"

---@class YaTreeCanvas
---@field public display_mode YaTreeCanvasDisplayMode
---@field private winid number
---@field private edit_winid number
---@field private bufnr number
---@field private window_augroup number
---@field private previous_row number
---@field private width number
---@field private nodes YaTreeNode[]
---@field private node_path_to_index_lookup table<string, number>
local Canvas = {}
Canvas.__index = Canvas

---@param self YaTreeCanvas
---@return string
Canvas.__tostring = function(self)
  return string.format(
    "(winid=%s, bufnr=%s, edit_winid=%s, mode=%s, nodes=[%s, %s])",
    self.winid,
    self.bufnr,
    self.edit_winid,
    self.display_mode,
    self.nodes and #self.nodes or 0,
    self.nodes and tostring(self.nodes[1]) or "nil"
  )
end

---@return YaTreeCanvas canvas
function Canvas:new()
  ---@type YaTreeCanvas
  local this = setmetatable({}, self)
  this.display_mode = "tree"
  this.width = config.view.width
  this.nodes = {}
  this.node_path_to_index_lookup = {}
  return this
end

---@return number height, number width
function Canvas:get_size()
  ---@type number
  local height = api.nvim_win_get_height(self.winid)
  ---@type number
  local width = api.nvim_win_get_width(self.winid)
  return height, width
end

---@return number? winid
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
  self.edit_winid = winid
  if self.edit_winid and self.edit_winid == self.winid then
    log.error("setting edit_winid to %s, the same as winid", self.edit_winid)
  end
end

function Canvas:create_edit_window()
  local position = config.view.side ~= "left" and "aboveleft" or "belowright"
  local size = vim.o.columns - self.width - 1
  api.nvim_command("noautocmd " .. position .. " " .. size .. "vsplit")
  ---@type number
  local winid = api.nvim_get_current_win()
  self.edit_winid = winid

  log.debug("created edit window %s", winid)
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
  return self.bufnr and api.nvim_buf_is_valid(self.bufnr) and api.nvim_buf_is_loaded(self.bufnr) or false
end

---@private
---@param hijack_buffer boolean
function Canvas:_create_buffer(hijack_buffer)
  if hijack_buffer then
    ---@type number
    self.bufnr = api.nvim_get_current_buf()
    -- need to remove the "readonly" option, otherwise a warning might be raised
    api.nvim_buf_set_option(self.bufnr, "modifiable", true)
    api.nvim_buf_set_option(self.bufnr, "readonly", false)
    log.debug("hijacked buffer %s", self.bufnr)
  else
    ---@type number
    self.bufnr = api.nvim_create_buf(false, false)
    log.debug("created buffer %s", self.bufnr)
  end
  api.nvim_buf_set_name(self.bufnr, "YaTree" .. self.bufnr)

  for _, v in ipairs(buf_options) do
    api.nvim_buf_set_option(self.bufnr, v.name, v.value)
  end

  require("ya-tree.actions").apply_mappings(self.bufnr)
end

function Canvas:restore()
  if self.winid and self.bufnr then
    log.debug("restoring canvas buffer to buffer %s", self.bufnr)
    api.nvim_win_set_buf(self.winid, self.bufnr)
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
  api.nvim_win_set_buf(self.winid, self.bufnr)

  win_options.number = config.view.number
  win_options.relativenumber = config.view.relativenumber
  for k, v in pairs(win_options) do
    vim.opt_local[k] = v
  end

  ---@type number
  self.window_augroup = api.nvim_create_augroup("YaTreeCanvas_Window_" .. self.winid, { clear = true })
  api.nvim_create_autocmd("WinLeave", {
    group = self.window_augroup,
    buffer = self.bufnr,
    callback = function()
      self.width = api.nvim_win_get_width(self.winid)
    end,
    desc = "Storing window width",
  })
  api.nvim_create_autocmd("WinClosed", {
    group = self.window_augroup,
    pattern = tostring(self.winid),
    callback = function()
      self:_on_win_closed()
    end,
    desc = "Cleaning up window specific settings",
  })
  if config.hijack_cursor then
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

---@param width number
local function set_barbar_offset(width)
  if barbar_exists then
    local ok, result = pcall(barbar_state.set_offset, width, config.view.barbar.title or "")
    if ok then
      api.nvim_tabpage_set_var(0, tab_var_barbar_set_name, width)
    else
      log.error("error calling barbar to set offset: %", result)
    end
  end
end

---@private
function Canvas:_on_win_closed()
  log.debug("window %s was closed", self.winid)
  if config.view.barbar.enable and barbar_exists and config.view.side == "left" then
    set_barbar_offset(0)
  end

  if type(config.view.on_close) == "function" then
    local ok, result = pcall(config.view.on_close, config)
    if not ok then
      log.error("error calling user supplied on_close function: %", result)
    end
  end

  local ok, result = pcall(api.nvim_del_augroup_by_id, self.window_augroup)
  if not ok then
    log.error("error deleting window local augroup: %s", result)
  end

  self.window_augroup = nil
  self.winid = nil
end

---@private
function Canvas:_create_window()
  ---@type number
  local winid = api.nvim_get_current_win()
  if winid ~= self.edit_winid then
    local old_edit_winid = self.edit_winid
    self.edit_winid = winid
    log.debug("setting edit_winid to %s, old=%s", self.edit_winid, old_edit_winid)
  end

  local position = config.view.side == "left" and "aboveleft" or "belowright"
  api.nvim_command("noautocmd " .. position .. " " .. self.width .. "vsplit")
  ---@type number
  self.winid = api.nvim_get_current_win()
  log.debug("created window %s", self.winid)
  self:_set_window_options()
end

---@param root YaTreeNode
---@param opts? {hijack_buffer?: boolean}
---  - {opts.hijack_buffer?} `boolean`
function Canvas:open(root, opts)
  if self:is_open() then
    return
  end

  opts = opts or {}
  if not self:_is_buffer_loaded() then
    self:_create_buffer(opts.hijack_buffer)
  end

  if opts.hijack_buffer then
    ---@type number
    self.winid = api.nvim_get_current_win()
    log.debug("hijacking current window %s for canvas", self.winid)
    self.edit_winid = nil
    self:_set_window_options()
  else
    self:_create_window()
  end

  self:render(root)

  -- barbar can only set offsets on the left side
  if config.view.barbar.enable and barbar_exists and config.view.side == "left" then
    set_barbar_offset(self.width)
  end

  if type(config.view.on_open) == "function" then
    local ok, result = pcall(config.view.on_open, config)
    if not ok then
      log.error("error calling user supplied on_open function: %", result)
    end
  end
end

function Canvas:focus()
  if self.winid then
    ---@type number
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

---@type YaTreeViewRenderer[]
local directory_renderers = {}
---@type YaTreeViewRenderer[]
local file_renderers = {}

---@class highlight_group
---@field name string
---@field from number
---@field to number

---@param pos number
---@param padding string
---@param text string
---@param highlight string
---@return number end_position, string content, highlight_group highlight
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

---@param node YaTreeNode
---@param mode YaTreeCanvasDisplayMode
---@return string text, highlight_group[] highlights
local function render_node(node, mode)
  ---@type string[]
  local content = {}
  ---@type highlight_group[]
  local highlights = {}

  local renderers = node:is_directory() and directory_renderers or file_renderers
  local pos = 0
  ---@type RenderingContext
  local context = { display_mode = mode, config = config }
  for _, renderer in ipairs(renderers) do
    if vim.tbl_contains(renderer.config.view_mode, mode) then
      local results = renderer.fun(node, context, renderer.config)
      if results then
        results = results[1] and results or { results }
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
  end

  return table.concat(content), highlights
end

---@private
---@param root YaTreeNode
---@return string[] lines, highlight_group[][] highlights
function Canvas:_render_tree(root)
  log.debug("creating canvas tree with root node %s", root.path)
  self.nodes, self.node_path_to_index_lookup = {}, {}
  ---@type string[]
  local lines = {}
  ---@type highlight_group[][]
  local highlights = {}
  local linenr = 0

  ---@param node YaTreeNode
  ---@param depth number
  ---@param last_child boolean
  local function append_node(node, depth, last_child)
    -- all nodes should be displayed if in 'buffers' display mode
    if utils.should_display_node(node, config) or self.display_mode == "buffers" or depth == 0 then
      linenr = linenr + 1
      node.depth = depth
      node.last_child = last_child
      self.nodes[linenr] = node
      self.node_path_to_index_lookup[node.path] = linenr
      lines[linenr], highlights[linenr] = render_node(node, self.display_mode)

      if node:is_directory() and node.expanded then
        local nr_of_children = #node.children
        for i, child in ipairs(node.children) do
          append_node(child, depth + 1, i == nr_of_children)
        end
      end
    end
  end

  append_node(root, 0, false)

  return lines, highlights
end

---@param root YaTreeNode|YaTreeSearchNode
function Canvas:render(root)
  local lines, highlights = self:_render_tree(root)

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

---@param node YaTreeNode
---@return boolean visible
function Canvas:is_node_visible(node)
  return self.node_path_to_index_lookup[node.path] ~= nil
end

---@private
---@return YaTreeNode node, number row, number column
function Canvas:_get_current_node_and_position()
  if not self.winid then
    return nil
  end

  ---@type number
  local row, column = unpack(api.nvim_win_get_cursor(self.winid))
  local node = self.nodes[row]
  return node, row, column
end

---@return YaTreeNode? node
function Canvas:get_current_node()
  local node = self:_get_current_node_and_position()
  return node
end

do
  ---@type string
  local esc_term_codes = api.nvim_replace_termcodes("<ESC>", true, false, true)

  ---@return YaTreeNode[] nodes
  function Canvas:get_selected_nodes()
    ---@type string
    local mode = api.nvim_get_mode().mode
    if mode == "v" or mode == "V" then
      ---@type number
      local from = fn.getpos("v")[2]
      ---@type number
      local to = api.nvim_win_get_cursor(self.winid)[1]
      if from > to then
        from, to = to, from
      end

      ---@type YaTreeNode[]
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

  ---@type string
  local line = api.nvim_get_current_line()
  local pos = (line:find(node.name, 1, true) or 0) - 1
  if pos > 0 and pos ~= col then
    api.nvim_win_set_cursor(self.winid, { row, pos })
  end
end

---@param winid number
---@param row number
---@param col number
local function set_cursor_position(winid, row, col)
  ---@type number
  local win_height = api.nvim_win_get_height(winid)
  local ok = pcall(api.nvim_win_set_cursor, winid, { row, col })
  if ok then
    if win_height > row then
      vim.cmd("normal! zb")
    elseif row < (win_height / 2) then
      vim.cmd("normal! zz")
    end
  end
end

---@param node YaTreeNode
function Canvas:focus_node(node)
  -- if the node has been hidden after a toggle
  -- go upwards in the tree until we find one that's displayed
  while not utils.should_display_node(node, config) and node.parent do
    node = node.parent
  end
  if node then
    local index = self.node_path_to_index_lookup[node.path]
    log.debug("node %s is at index %s", node.path, index)
    if index then
      ---@type number
      local _, column = unpack(api.nvim_win_get_cursor(self.winid))
      set_cursor_position(self.winid, index, column)
    end
  end
end

---@param node YaTreeNode
function Canvas:focus_parent(node)
  if not node or node == self.nodes[1] or not node.parent then
    return
  end

  local index = self.node_path_to_index_lookup[node.parent.path]
  if index then
    ---@type number
    local _, column = unpack(api.nvim_win_get_cursor(self.winid))
    set_cursor_position(self.winid, index, column)
  end
end

---@param node YaTreeNode
function Canvas:focus_prev_sibling(node)
  if not node or not node.parent or not node.parent.children then
    return
  end

  for prev in node.parent:iterate_children({ reverse = true, from = node }) do
    if utils.should_display_node(prev, config) then
      local index = self.node_path_to_index_lookup[prev.path]
      if index then
        ---@type number
        local _, column = unpack(api.nvim_win_get_cursor(self.winid))
        set_cursor_position(self.winid, index, column)
        return
      end
    end
  end
end

---@param node YaTreeNode
function Canvas:focus_next_sibling(node)
  if not node or not node.parent or not node.parent.children then
    return
  end

  for next in node.parent:iterate_children({ from = node }) do
    if utils.should_display_node(next, config) then
      local index = self.node_path_to_index_lookup[next.path]
      if index then
        ---@type number
        local _, column = unpack(api.nvim_win_get_cursor(self.winid))
        set_cursor_position(self.winid, index, column)
        return
      end
    end
  end
end

---@param node YaTreeNode
function Canvas:focus_first_sibling(node)
  if not node or not node.parent or not node.parent.children then
    return
  end

  for next in node.parent:iterate_children() do
    if utils.should_display_node(next, config) then
      local index = self.node_path_to_index_lookup[next.path]
      if index then
        ---@type number
        local _, column = unpack(api.nvim_win_get_cursor(self.winid))
        set_cursor_position(self.winid, index, column)
        return
      end
    end
  end
end

---@param node YaTreeNode
function Canvas:focus_last_sibling(node)
  if not node or not node.parent or not node.parent.children then
    return
  end

  for prev in node.parent:iterate_children({ reverse = true }) do
    if utils.should_display_node(prev, config) then
      local index = self.node_path_to_index_lookup[prev.path]
      if index then
        ---@type number
        local _, column = unpack(api.nvim_win_get_cursor(self.winid))
        set_cursor_position(self.winid, index, column)
        return
      end
    end
  end
end

---@param node YaTreeNode
function Canvas:focus_prev_git_item(node)
  if not node then
    return
  end

  ---@type number
  local row, column = unpack(api.nvim_win_get_cursor(self.winid))
  for index = row - 1, 1, -1 do
    if self.nodes[index]:get_git_status() then
      set_cursor_position(self.winid, index, column)
      return
    end
  end
end

---@param node YaTreeNode
function Canvas:focus_next_git_item(node)
  if not node then
    return
  end

  ---@type number
  local row, column = unpack(api.nvim_win_get_cursor(self.winid))
  for index = row + 1, #self.nodes do
    if self.nodes[index]:get_git_status() then
      set_cursor_position(self.winid, index, column)
      return
    end
  end
end

local function on_tab_leave() end

local function on_tab_enter() end

do
  ---@type number
  local previous_tab_page

  on_tab_leave = function()
    previous_tab_page = api.nvim_get_current_tabpage()
  end

  ---@param tabpage number
  ---@return boolean was_set, number? width
  local function get_tabbar_offset(tabpage)
    local ok, value = pcall(api.nvim_tabpage_get_var, tabpage, tab_var_barbar_set_name)
    if ok then
      return ok, value
    else
      return false
    end
  end

  on_tab_enter = function()
    if previous_tab_page then
      local was_set, _ = get_tabbar_offset(previous_tab_page)
      local is_set, current_width = get_tabbar_offset(api.nvim_get_current_tabpage())
      if was_set and not is_set then
        set_barbar_offset(0)
      elseif is_set then
        set_barbar_offset(current_width)
      end
    end
  end
end

---@class YaTreeViewRenderer
---@field name string
---@field fun fun(node: YaTreeNode, context: RenderingContext, renderer: YaTreeRendererConfig): RenderResult|RenderResult[]|nil
---@field config? YaTreeRendererConfig

do
  local renderers = require("ya-tree.ui.renderers")

  ---@param view_renderer YaTreeConfig.View.Renderers.DirectoryRenderer|YaTreeConfig.View.Renderers.FileRenderer
  ---@return YaTreeViewRenderer?
  local function create_renderer(view_renderer)
    ---@type YaTreeViewRenderer
    local renderer = {}

    local name = view_renderer[1]
    if type(name) == "string" then
      renderer.name = name
      local fun = renderers[name]
      if type(fun) == "function" then
        renderer.fun = fun
        ---@type YaTreeRendererConfig
        renderer.config = vim.deepcopy(config.renderers[name])
      else
        fun = config.renderers[name]
        if type(fun) == "function" then
          renderer.fun = fun
        else
          utils.warn(string.format("Renderer %s is not a function in the renderers table, ignoring renderer", name))
        end
      end
    else
      utils.warn("Invalid renderer " .. vim.inspect(view_renderer))
    end

    if renderer.fun then
      return renderer
    end
  end

  local highlight_open_file = false

  function Canvas.setup()
    config = require("ya-tree.config").config

    renderers.setup(config)

    -- reset the renderer arrays, since the setup can be called repeatedly
    ---@type YaTreeRendererConfig[]
    directory_renderers = {}
    ---@type YaTreeRendererConfig[]
    file_renderers = {}

    for _, directory_renderer in ipairs(config.view.renderers.directory) do
      local renderer = create_renderer(directory_renderer)
      if renderer then
        for k, v in pairs(directory_renderer) do
          if type(k) ~= "number" then
            log.debug("overriding directory renderer %q config value for %q with %s", renderer.name, k, v)
            renderer.config[k] = v
          end
        end
        directory_renderers[#directory_renderers + 1] = renderer
      end
    end
    log.trace("directory renderers=%s", directory_renderers)

    for _, file_renderer in ipairs(config.view.renderers.file) do
      local renderer = create_renderer(file_renderer)
      if renderer then
        for k, v in pairs(file_renderer) do
          if type(k) ~= "number" then
            log.debug("overriding file renderer %q config value for %q with %s", renderer.name, k, v)
            renderer.config[k] = v
          end
        end
        file_renderers[#file_renderers + 1] = renderer

        if renderer.name == "name" then
          ---@type YaTreeConfig.Renderers.Name
          local renderer_config = renderer.config
          highlight_open_file = renderer_config.highlight_open_file
        end
      end
    end
    log.trace("file renderers=%s", file_renderers)

    barbar_exists, barbar_state = pcall(require, "bufferline.state")
    barbar_exists = barbar_exists and type(barbar_state.set_offset) == "function"
    log.debug("barbar has " .. (barbar_exists and "successfully" or "not") .. " been detected")
    if config.view.barbar.enable and not barbar_exists then
      utils.notify("barbar was not detected. Disabling 'view.barbar.enable' in the configuration")
      config.view.barbar.enable = false
    end

    if barbar_exists and config.view.barbar.enable then
      local group = api.nvim_create_augroup("YaTreeCanvas", { clear = true })
      api.nvim_create_autocmd("TabLeave", {
        group = group,
        callback = function()
          on_tab_leave()
        end,
        desc = "barbar tabline integration handling",
      })
      api.nvim_create_autocmd("TabEnter", {
        group = group,
        callback = function()
          on_tab_enter()
        end,
        desc = "barbar tabline integration handling",
      })
    end
  end

  ---@return boolean enabled
  function Canvas.is_highlight_open_file_enabled()
    return highlight_open_file
  end
end

return Canvas

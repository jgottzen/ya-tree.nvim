local config = require("ya-tree.config").config
local help = require("ya-tree.ui.help")
local utils = require("ya-tree.utils")
local log = require("ya-tree.log")

local api = vim.api
local fn = vim.fn

local ns = api.nvim_create_namespace("YaTreeHighlights")

local win_options = {
  -- number and relativenumber are taken directly from config
  -- number = false,
  -- relativenumber = false,
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

---@type {name: string, value: string|boolean}[]
local buf_options = {
  { name = "bufhidden", value = "hide" },
  { name = "buflisted", value = false },
  { name = "filetype", value = "YaTree" },
  { name = "buftype", value = "nofile" },
  { name = "modifiable", value = false },
  { name = "swapfile", value = false },
}

---@class YaTreeCanvas
---@field private winid number
---@field private edit_winid number
---@field private bufnr number
---@field private mode "'tree'"|"'search'"
---@field private in_help boolean
---@field private nodes YaTreeNode[]
---@field private node_path_to_index_lookup table<string, number>
---@field private node_lines string[]
---@field private node_highlights highlight_group[][]
local Canvas = {}
Canvas.__index = Canvas

function Canvas:new()
  return setmetatable({}, Canvas)
end

---@return number number height, number width
function Canvas:get_size()
  if self.winid then
    ---@type number
    local height = api.nvim_win_get_height(self.winid)
    ---@type number
    local width = api.nvim_win_get_width(self.winid)
    return height, width
  end
end

---@return number winid
function Canvas:get_edit_winid()
  return self.edit_winid
end

---@param winid number
function Canvas:set_edit_winid(winid)
  self.edit_winid = winid
  if self.edit_winid ~= nil and self.edit_winid == self.winid then
    log.error("setting edit_winid to %s, the same as winid", self.edit_winid)
  end
end

---@return boolean is_open
function Canvas:is_open()
  return self.winid ~= nil and api.nvim_win_is_valid(self.winid)
end

---@return boolean
function Canvas:is_current_window_canvas()
  if self.winid then
    return self.winid == api.nvim_get_current_win()
  end
end

---@private
---@return boolean is_loaded
function Canvas:_is_buffer_loaded()
  return self.bufnr ~= nil and api.nvim_buf_is_valid(self.bufnr) and api.nvim_buf_is_loaded(self.bufnr)
end

---@private
---@param hijack_buffer boolean
function Canvas:_create_buffer(hijack_buffer)
  if hijack_buffer then
    ---@type number
    self.bufnr = api.nvim_get_current_buf()
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

---@param key string
---@param value boolean|string
---@return string
local function format_option(key, value)
  if value == true then
    return key
  elseif value == false then
    return string.format("no%s", key)
  else
    return string.format("%s=%s", key, value)
  end
end

function Canvas:restore()
  if self.winid and self.bufnr then
    log.debug("restoring canvas buffer to buffer %s", self.bufnr)
    api.nvim_win_set_buf(self.winid, self.bufnr)
  end
end

---@param bufnr number
---@param root YaTreeNode
function Canvas:move_buffer_to_edit_window(bufnr, root)
  if self.winid and self.edit_winid and self.bufnr then
    log.debug("moving buffer %s from window %s to window %s", bufnr, api.nvim_get_current_win(), self.edit_winid)

    api.nvim_win_set_buf(self.winid, self.bufnr)
    self:render_tree(root)
    api.nvim_win_set_buf(self.edit_winid, bufnr)
    api.nvim_set_current_win(self.edit_winid)
  end
end

---@private
function Canvas:_set_window_options_and_size()
  api.nvim_win_set_buf(self.winid, self.bufnr)
  api.nvim_command("noautocmd wincmd " .. (config.view.side == "right" and "L" or "H"))
  api.nvim_command("noautocmd vertical resize " .. config.view.width)

  for k, v in pairs(win_options) do
    api.nvim_command(string.format("noautocmd setlocal %s", format_option(k, v)))
  end
  api.nvim_command(string.format("noautocmd setlocal %s", format_option("number", config.view.number)))
  api.nvim_command(string.format("noautocmd setlocal %s", format_option("relativenumber", config.view.relativenumber)))

  self:resize()
end

---@private
function Canvas:_create_window()
  ---@type number
  local old_edit_winid = self.edit_winid
  self.edit_winid = api.nvim_get_current_win()
  log.debug("setting edit_winid to %s, old=%s", self.edit_winid, old_edit_winid)

  api.nvim_command("noautocmd vsplit")
  ---@type number
  self.winid = api.nvim_get_current_win()
  log.debug("created window %s", self.winid)
  self:_set_window_options_and_size()
end

---@param root YaTreeNode
---@param opts {hijack_buffer?: boolean}
function Canvas:open(root, opts)
  if self:is_open() then
    return
  end

  opts.redraw = false
  if not self:_is_buffer_loaded() then
    opts.redraw = true
    self:_create_buffer(opts.hijack_buffer)
  end

  if opts.hijack_buffer then
    ---@type number
    self.winid = api.nvim_get_current_win()
    log.debug("hijacking current window %s for canvas", self.winid)
    self.edit_winid = nil
    self:_set_window_options_and_size()
  else
    self:_create_window()
  end

  if opts.redraw then
    self:render_tree(root, opts)
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
  if self.edit_winid then
    api.nvim_set_current_win(self.edit_winid)
  end
end

---@return boolean has_focus
function Canvas:has_focus()
  return self.winid and self.winid == api.nvim_get_current_win()
end

function Canvas:close()
  if not self.winid then
    return
  end

  local ok = pcall(api.nvim_win_close, self.winid, true)
  if ok then
    log.debug("closed canvas window=%s", self.winid)
  else
    log.error("error closing window %q", self.winid)
  end
  self.winid = nil
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

function Canvas:resize()
  if not self.winid then
    return
  end

  api.nvim_win_set_width(self.winid, config.view.width)
  vim.cmd("wincmd =")
end

function Canvas:reset_canvas()
  if self.winid and not config.view.number and not config.view.relativenumber then
    api.nvim_command("stopinsert")
    api.nvim_command("noautocmd setlocal norelativenumber")
  end
end

---@type YaTreeViewRenderer[]
local directory_renderers
---@type YaTreeViewRenderer[]
local file_renderers

---@class highlight_group
---@field name string
---@field from number
---@field to number

---@param pos number
---@param padding string
---@param text string
---@param hl_name string
---@return number end_position, string content, highlight_group highlight
local function line_part(pos, padding, text, hl_name)
  local from = pos + #padding
  local size = #text
  local group = {
    name = hl_name,
    from = from,
    to = from + size,
  }
  return group.to, string.format("%s%s", padding, text), group
end

---@param node YaTreeNode
---@return string content, highlight_group[] highlights
local function render_node(node)
  ---@type string[]
  local content = {}
  ---@type highlight_group[]
  local highlights = {}

  local renderers = node:is_directory() and directory_renderers or file_renderers
  local pos = 0
  ---@type YaTreeViewRenderer
  for _, renderer in ipairs(renderers) do
    local result = renderer.fun(node, config, renderer.config)
    if result then
      result = result[1] and result or { result }
      for _, v in ipairs(result) do
        if v.text then
          if not v.highlight then
            log.error("renderer %s didn't return a highlight name for node %q, renderer returned %s", renderer.name, node.path, v)
          end
          pos, content[#content + 1], highlights[#highlights + 1] = line_part(pos, v.padding or "", v.text, v.highlight)
        end
      end
    end
  end

  return table.concat(content), highlights
end

---@param node YaTreeNode
---@return boolean
local function should_display_node(node)
  if config.filters.enable then
    if config.filters.dotfiles and node:is_dotfile() then
      return false
    end
    if config.filters.custom[node.name] then
      return false
    end
  end

  if config.git.show_ignored then
    if node:is_git_ignored() then
      return false
    end
  end

  return true
end

---@private
---@param root YaTreeNode
function Canvas:_create_tree(root)
  self.nodes, self.node_lines, self.node_highlights, self.node_path_to_index_lookup = {}, {}, {}, {}

  root.depth = 0
  local content, highlights = render_node(root)

  self.nodes[#self.nodes + 1] = root
  self.node_path_to_index_lookup[root.path] = #self.nodes
  self.node_lines[#self.node_lines + 1] = content
  self.node_highlights[#self.node_highlights + 1] = highlights

  ---@param node YaTreeNode
  ---@param depth number
  ---@param last_child boolean
  local function append_node(node, depth, last_child)
    if should_display_node(node) then
      node.depth = depth
      node.last_child = last_child
      content, highlights = render_node(node)

      self.nodes[#self.nodes + 1] = node
      self.node_path_to_index_lookup[node.path] = #self.nodes
      self.node_lines[#self.node_lines + 1] = content
      self.node_highlights[#self.node_highlights + 1] = highlights

      if node:is_directory() and node.expanded then
        local nr_of_children = #node.children
        for i, child in ipairs(node.children) do
          append_node(child, depth + 1, i == nr_of_children)
        end
      end
    end
  end

  local nr_of_children = #root.children
  for i, node in ipairs(root.children) do
    append_node(node, 1, i == nr_of_children)
  end
end

---@private
function Canvas:_draw()
  api.nvim_buf_set_option(self.bufnr, "modifiable", true)
  api.nvim_buf_clear_namespace(self.bufnr, ns, 0, -1)

  ---@type string[]
  local lines
  ---@type highlight_group[][]
  local highlights
  if self.in_help then
    lines, highlights = help.create_help()
  else
    lines = self.node_lines
    highlights = self.node_highlights
  end

  api.nvim_buf_set_lines(self.bufnr, 0, -1, false, lines)

  for linenr, chunk in ipairs(highlights) do
    for _, highlight in ipairs(chunk) do
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

---@param root YaTreeNode
---@param opts? {redraw: boolean}
---  - {opts.redraw} `boolean`
function Canvas:render_tree(root, opts)
  if opts and opts.redraw then
    self:_create_tree(root)
  end
  self.in_help = false
  self.mode = "tree"
  self:_draw()
end

function Canvas:render_help()
  self.in_help = true
  self:_draw()
end

---@param search_root YaTreeSearchNode
function Canvas:render_search(search_root)
  if search_root then
    self:_create_tree(search_root)
  end
  self.in_help = false
  self.mode = "search"
  self:_draw()
end

---@private
---@return YaTreeNode node, number row, number column
function Canvas:_get_current_node_and_position()
  local row, column = unpack(api.nvim_win_get_cursor(self.winid))
  local node = self.nodes[row]
  return node, row, column
end

---@return YaTreeNode? node
function Canvas:get_current_node()
  local node = self:_get_current_node_and_position()
  return node
end

---@return YaTreeNode[] nodes
function Canvas:get_selected_nodes()
  local mode = api.nvim_get_mode().mode
  if mode == "v" or mode == "V" then
    -- see https://github.com/neovim/neovim/pull/13896
    local from = fn.getpos("v")
    local to = fn.getcurpos()
    if from[2] > to[2] then
      from, to = to, from
    end

    ---@type number
    local first = from[2]
    ---@type number
    local last = to[2]
    ---@type YaTreeNode
    local nodes = {}
    if first <= #self.nodes then
      for index = first, last do
        local node = self.nodes[index]
        if node then
          nodes[#nodes + 1] = node
        end
      end
    end

    local keys = api.nvim_replace_termcodes("<ESC>", true, false, true)
    api.nvim_feedkeys(keys, "n", true)

    return nodes
  else
    return { self:get_current_node() }
  end
end

do
  ---@type number
  local previous_row

  function Canvas:move_cursor_to_name()
    if self.in_help then
      return
    end
    local node, row, col = self:_get_current_node_and_position()
    if not node or row == previous_row then
      return
    end

    previous_row = row
    -- don't move the cursor on the first line
    if row == 1 then
      return
    end

    ---@type string
    local line = api.nvim_get_current_line()
    local pos = (line:find(node.name, 1, true) or 0) - 1
    if pos > 0 and pos ~= col then
      api.nvim_win_set_cursor(self.winid or 0, { row, pos })
    end
  end
end

---@param winid number
---@param row number
---@param col number
local function set_cursor_position(winid, row, col)
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
  while not should_display_node(node) and node.parent do
    node = node.parent
  end
  if node then
    local index = self.node_path_to_index_lookup[node.path]
    if index then
      local column = 0
      if config.hijack_cursor then
        column = (self.node_lines[index]:find(node.name, 1, true) or 0) - 1
      end
      set_cursor_position(self.winid, index, column)
    end
  end
end

function Canvas:focus_prev_sibling()
  local node, _, col = self:_get_current_node_and_position()
  local parent = node.parent
  if not parent or not parent.children then
    return
  end

  for prev in parent:iterate_children({ reverse = true, from = node }) do
    if should_display_node(prev) then
      local index = self.node_path_to_index_lookup[prev.path]
      if index then
        set_cursor_position(self.winid, index, col)
        return
      end
    end
  end
end

function Canvas:focus_next_sibling()
  local node, _, col = self:_get_current_node_and_position()
  local parent = node.parent
  if not parent or not parent.children then
    return
  end

  for next in parent:iterate_children({ from = node }) do
    if should_display_node(next) then
      local index = self.node_path_to_index_lookup[next.path]
      if index then
        set_cursor_position(self.winid, index, col)
        return
      end
    end
  end
end

function Canvas:focus_first_sibling()
  local node, _, col = self:_get_current_node_and_position()
  local parent = node.parent
  if not parent or not parent.children then
    return
  end

  for next in parent:iterate_children() do
    if should_display_node(next) then
      local index = self.node_path_to_index_lookup[next.path]
      if index then
        set_cursor_position(self.winid, index, col)
        return
      end
    end
  end
end

function Canvas:focus_last_sibling()
  local node, _, col = self:_get_current_node_and_position()
  local parent = node.parent
  if not parent or not parent.children then
    return
  end

  for prev in parent:iterate_children({ reverse = true }) do
    if should_display_node(prev) then
      local index = self.node_path_to_index_lookup[prev.path]
      if index then
        set_cursor_position(self.winid, index, col)
        return
      end
    end
  end
end

---@class YaTreeViewRenderer
---@field name string
---@field fun fun(node: YaTreeNode, config: YaTreeConfig, renderer: YaTreeRendererConfig): RenderResult|RenderResult[]
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
        renderer.config = vim.deepcopy(config.renderers[name])
      else
        fun = config.renderers[name]
        if type(fun) == "function" then
          renderer.fun = fun
        else
          utils.print_error(string.format("Renderer %s is not a function in the renderers table, ignoring renderer", name))
        end
      end
    else
      utils.print_error("Invalid renderer " .. vim.inspect(view_renderer))
    end

    if renderer.fun then
      for k, v in pairs(view_renderer) do
        if type(k) ~= "number" then
          log.debug("overriding renderer %q config value for %s with %s", renderer.name, k, v)
          renderer.config[k] = v
        end
      end
      return renderer
    end
  end

  function Canvas.setup()
    renderers.setup(config)

    -- reset the renderer arrays, since the setup can be called repeatedly
    directory_renderers = {}
    file_renderers = {}

    for _, directory_renderer in pairs(config.view.renderers.directory) do
      local renderer = create_renderer(directory_renderer)
      if renderer then
        directory_renderers[#directory_renderers + 1] = renderer
      end
    end
    log.trace("directory renderers=%s", directory_renderers)

    for _, file_renderer in pairs(config.view.renderers.file) do
      local renderer = create_renderer(file_renderer)
      if renderer then
        file_renderers[#file_renderers + 1] = renderer
      end
    end
    log.trace("file renderers=%s", file_renderers)
  end
end

return Canvas

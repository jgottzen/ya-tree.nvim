local config = require("ya-tree.config").config
local help = require("ya-tree.ui.help")
local utils = require("ya-tree.utils")
local log = require("ya-tree.log")

local api = vim.api

local M = {}

local ns = api.nvim_create_namespace("YaTreeHighlights")

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
---@param hl_name string
---@return number, string, highlight_group
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
---@return string, highlight_group[]
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

---@type YaTreeNode[]
local nodes
---@type table<string, number>
local node_path_to_index_lookup
---@type string[]
local node_lines
---@type highlight_group[][]
local node_highlights

---@param root YaTreeNode
local function create_tree(root)
  nodes, node_path_to_index_lookup, node_lines, node_highlights = {}, {}, {}, {}

  root.depth = 0
  local content, highlights = render_node(root)

  nodes[#nodes + 1] = root
  node_path_to_index_lookup[root.path] = #nodes
  node_lines[#node_lines + 1] = content
  node_highlights[#node_highlights + 1] = highlights

  ---@param node YaTreeNode
  ---@param depth number
  ---@param last_child boolean
  local function append_node(node, depth, last_child)
    if should_display_node(node) then
      node.depth = depth
      node.last_child = last_child
      content, highlights = render_node(node)

      nodes[#nodes + 1] = node
      node_path_to_index_lookup[node.path] = #nodes
      node_lines[#node_lines + 1] = content
      node_highlights[#node_highlights + 1] = highlights

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

---@param bufnr number
---@param opts {help: boolean}
---  - {opts.help} `boolean`
local function draw(bufnr, opts)
  api.nvim_buf_set_option(bufnr, "modifiable", true)
  api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

  ---@type string[]
  local lines
  ---@type highlight_group[][]
  local highlights
  if opts and opts.help then
    lines, highlights = help.create_help()
  else
    lines = node_lines
    highlights = node_highlights
  end

  api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

  for index, chunk in ipairs(highlights) do
    for _, highlight in ipairs(chunk) do
      -- guard against bugged out renderer highlights, which will cause an avalanche of errors...
      if not highlight.name then
        log.error("missing highlight name for node=%q, hl=%s", nodes[index].path, highlight)
      else
        api.nvim_buf_add_highlight(bufnr, ns, highlight.name, index - 1, highlight.from, highlight.to)
      end
    end
  end

  api.nvim_buf_set_option(bufnr, "modifiable", false)
end

---@param bufnr number
---@param root YaTreeNode
---@param opts {redraw: boolean}
---  - {opts.redraw} `boolean`
function M.render(bufnr, root, opts)
  if opts and opts.redraw then
    create_tree(root)
  end
  draw(bufnr)
end

---@param bufnr number
function M.render_help(bufnr)
  draw(bufnr, { help = true })
end

---@param bufnr number
---@param search_root YaTreeSearchNode
function M.render_search(bufnr, search_root)
  create_tree(search_root)
  draw(bufnr)
end

---@param winid number
---@return YaTreeNode?
function M.get_current_node(winid)
  local node = M.get_current_node_and_position(winid)
  return node
end

---@param winid number
---@return YaTreeNode, number, number
function M.get_current_node_and_position(winid)
  local row, column = unpack(api.nvim_win_get_cursor(winid))
  return nodes[row], row, column
end

do
  ---@type number
  local previous_row
  ---@param winid number
  function M.move_cursor_to_name(winid)
    local node, row, _ = M.get_current_node_and_position(winid)
    if not node or row == previous_row then
      return
    end

    previous_row = row
    ---@type string
    local line = api.nvim_get_current_line()
    local pos = line:find(node.name, 1, true) - 1
    if pos > 0 then
      api.nvim_win_set_cursor(winid or 0, { row, pos })
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

---@param winid number
---@param node YaTreeNode
function M.focus_node(winid, node)
  -- if the node has been hidden after a toggle
  -- go upwards in the tree until we find one that's displayed
  while not should_display_node(node) and node.parent do
    node = node.parent
  end
  if node then
    local index = node_path_to_index_lookup[node.path]
    if index then
      local column = 0
      if config.hijack_cursor then
        column = node_lines[index]:find(node.name, 1, true) - 1
      end
      set_cursor_position(winid, index, column)
    end
  end
end

---@param winid number
function M.focus_prev_sibling(winid)
  local node, _, col = M.get_current_node_and_position()
  local parent = node.parent
  if not parent or not parent.children then
    return
  end

  for prev in parent:iterate_children({ reverse = true, from = node }) do
    if should_display_node(prev) then
      local index = node_path_to_index_lookup[prev.path]
      if index then
        set_cursor_position(winid, index, col)
        return
      end
    end
  end
end

---@param winid number
function M.focus_next_sibling(winid)
  local node, _, col = M.get_current_node_and_position()
  local parent = node.parent
  if not parent or not parent.children then
    return
  end

  for next in parent:iterate_children({ from = node }) do
    if should_display_node(next) then
      local index = node_path_to_index_lookup[next.path]
      if index then
        set_cursor_position(winid, index, col)
        return
      end
    end
  end
end

---@param winid number
function M.focus_first_sibling(winid)
  local node, _, col = M.get_current_node_and_position()
  local parent = node.parent
  if not parent or not parent.children then
    return
  end

  for next in parent:iterate_children() do
    if should_display_node(next) then
      local index = node_path_to_index_lookup[next.path]
      if index then
        set_cursor_position(winid, index, col)
        return
      end
    end
  end
end

---@param winid number
function M.focus_last_sibling(winid)
  local node, _, col = M.get_current_node_and_position()
  local parent = node.parent
  if not parent or not parent.children then
    return
  end

  for prev in parent:iterate_children({ reverse = true }) do
    if should_display_node(prev) then
      local index = node_path_to_index_lookup[prev.path]
      if index then
        set_cursor_position(winid, index, col)
        return
      end
    end
  end
end

---@param first number
---@param last number
---@return YaTreeNode[]
function M.get_nodes_for_lines(first, last)
  local result = {}
  if first > #nodes then
    return result
  end

  for index = first, last do
    local node = nodes[index]
    if node then
      result[#result + 1] = node
    end
  end
  return result
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

  function M.setup()
    renderers.setup(config)

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

return M

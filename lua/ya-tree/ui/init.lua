local wrap = require("plenary.async").wrap

local config = require("ya-tree.config").config
local Canvas = require("ya-tree.ui.canvas")
local help = require("ya-tree.ui.help")
local hl = require("ya-tree.ui.highlights")
local log = require("ya-tree.log")

local api = vim.api

local M = {
  ---@private
  ---@type table<string, YaTreeCanvas>
  _canvases = {},
}

---@param tabpage number
function M.delete_ui(tabpage)
  local tab = tostring(tabpage)
  if M._canvases[tab] then
    M._canvases[tab]:delete()
    M._canvases[tab] = nil
  end
end

---@return YaTreeCanvas canvas
local function get_canvas()
  return M._canvases[tostring(api.nvim_get_current_tabpage())]
end

---@return boolean is_open
function M.is_open()
  local canvas = get_canvas()
  return canvas and canvas:is_open() or false
end

---@param root YaTreeNode
---@param node? YaTreeNode
---@param opts? {hijack_buffer?: boolean, focus?: boolean}
---  - {opts.hijack_buffer?} `boolean`
---  - {opts.focus?} `boolean`
function M.open(root, node, opts)
  opts = opts or {}
  local tabpage = tostring(api.nvim_get_current_tabpage())
  local canvas = M._canvases[tabpage]
  if not canvas then
    canvas = Canvas:new()
    M._canvases[tabpage] = canvas
  end

  if not canvas:is_open() then
    canvas:open(root, opts)
  elseif node and not canvas:is_node_visible(node) then
    -- redraw the tree if a specific node is to be focused, and it's currently not rendered
    canvas:render(root)
  end

  if node then
    canvas:focus_node(node)
  end

  if opts.focus then
    canvas:focus()
  else
    canvas:focus_edit_window()
  end
end

function M.focus()
  local canvas = get_canvas()
  if canvas then
    canvas:focus()
  end
end

function M.close()
  local canvas = get_canvas()
  if canvas then
    canvas:close()
  end
end

---@param root YaTreeNode
---@param node? YaTreeNode
---@param opts? {focus_node?: boolean}
---  - {opts.focus_node?} `boolean` focuse `node`
function M.update(root, node, opts)
  opts = opts or {}
  local canvas = get_canvas()
  if canvas and canvas:is_open() then
    canvas:render(root)
    -- only update the focused node if the current window is the view window,
    -- or explicitly requested
    if node and (opts.focus_node or canvas:has_focus()) then
      canvas:focus_node(node)
    end
  end
end

---@return YaTreeNode current_node
function M.get_current_node()
  return get_canvas():get_current_node()
end

---@return YaTreeNode[] selected_nodes
function M.get_selected_nodes()
  return get_canvas():get_selected_nodes()
end

---@param node YaTreeNode
function M.focus_node(node)
  get_canvas():focus_node(node)
end

---@param node YaTreeNode
function M.focus_parent(node)
  get_canvas():focus_parent(node)
end

---@param node YaTreeNode
function M.focus_prev_sibling(node)
  get_canvas():focus_prev_sibling(node)
end

---@param node YaTreeNode
function M.focus_next_sibling(node)
  get_canvas():focus_next_sibling(node)
end

---@param node YaTreeNode
function M.focus_first_sibling(node)
  get_canvas():focus_first_sibling(node)
end

---@param node YaTreeNode
function M.focus_last_sibling(node)
  get_canvas():focus_last_sibling(node)
end

---@param node YaTreeNode
function M.focus_prev_git_item(node)
  get_canvas():focus_prev_git_item(node)
end

---@param node YaTreeNode
function M.focus_next_git_item(node)
  get_canvas():focus_next_git_item(node)
end

---@param winid? number
---@return boolean is_floating
function M.is_window_floating(winid)
  ---@type table
  local win_config = api.nvim_win_get_config(winid or 0)
  return win_config.relative > "" or win_config.external
end

---@return boolean
function M.is_current_window_ui()
  local canvas = get_canvas()
  return canvas and canvas:is_current_window_canvas() or false
end

---@param bufnr number
---@return boolean
function M.is_buffer_yatree(bufnr)
  local ok, filetype = pcall(api.nvim_buf_get_option, bufnr, "filetype")
  return ok and filetype == "YaTree" or false
end

---@return number height, number width
function M.get_size()
  return get_canvas():get_size()
end

---@return YaTreeCanvasDisplayMode mode
function M.get_current_view_mode()
  local canvas = get_canvas()
  return canvas and canvas.display_mode
end

function M.open_help()
  help.open()
end

---@return boolean
function M.is_search_open()
  return M.get_current_view_mode() == "search"
end

---@param mode YaTreeCanvasDisplayMode
---@param root YaTreeNode|YaTreeSearchNode
---@param node? YaTreeNode
local function change_display_mode(mode, root, node)
  local canvas = get_canvas()
  canvas.display_mode = mode
  canvas:render(root)
  if node then
    canvas:focus_node(node)
  end
end

---@param search_root YaTreeSearchNode
---@param node? YaTreeNode
function M.open_search(search_root, node)
  change_display_mode("search", search_root, node)
end

---@param root YaTreeNode
---@param node YaTreeNode
function M.close_search(root, node)
  change_display_mode("tree", root, node)
end

---@return boolean
function M.is_buffers_open()
  return M.get_current_view_mode() == "buffers"
end

---@param root YaTreeNode
---@param node YaTreeNode
function M.open_buffers(root, node)
  change_display_mode("buffers", root, node)
end

---@param root YaTreeNode
---@param node YaTreeNode
function M.close_buffers(root, node)
  change_display_mode("tree", root, node)
end

---@param bufnr number
function M.on_win_leave(bufnr)
  if M.is_window_floating() or M.is_buffer_yatree(bufnr) then
    return
  end

  local canvas = get_canvas()
  if canvas and not canvas:is_current_window_canvas() then
    canvas:set_edit_winid(api.nvim_get_current_win())
  end
end

function M.restore()
  get_canvas():restore()
end

---@param canvas YaTreeCanvas
---@return number winid the winid of the created edit window
local function create_edit_window(canvas)
  local position = config.view.side ~= "left" and "aboveleft" or "belowright"
  vim.cmd(position .. " vsplit")
  ---@type number
  local winid = api.nvim_get_current_win()
  canvas:set_edit_winid(winid)
  canvas:resize()

  log.debug("created edit window %s", winid)
end

---@param bufnr number
function M.move_buffer_to_edit_window(bufnr)
  local canvas = get_canvas()
  if not canvas:get_edit_winid() then
    create_edit_window(canvas)
  end
  canvas:move_buffer_to_edit_window(bufnr)
end

---@param file string the file path to open
---@param cmd cmdmode
function M.open_file(file, cmd)
  local canvas = get_canvas()
  local winid = canvas:get_edit_winid()
  if not winid then
    -- only the tree window is open, e.g. netrw replacement
    -- create a new window for buffers

    create_edit_window(canvas)
    if cmd == "split" or cmd == "vsplit" then
      cmd = "edit"
    end
  else
    api.nvim_set_current_win(winid)
  end

  vim.cmd(cmd .. " " .. vim.fn.fnameescape(file))
end

---@type fun(opts: {prompt: string|nil, default: string|nil, completion: string|nil, highlight: fun()|nil}): string|nil
---  - {opts.prompt?} `string|nil` Text of the prompt.
---  - {opts.default?} `string|nil` Default reply to the input.
---  - {opts.completion?} `string|nil` Specifies type of completion supported for input.
---  - {opts.highlight?} `function|nil` Function that will be used for highlighting user input.
---@see |vim.ui.input()|
M.input = wrap(function(opts, on_confirm)
  vim.ui.input(opts, on_confirm)
end, 2)

---@type fun(items: table, opts: {prompt: string|nil, format_item: fun(item: any), kind: string|nil}): string?, number?
---  - {items} `table` Arbitrary items.
---  - {opts.prompt?} `string|nil` Text of the input.
---  - {opts.format_item} `function(item: any):string` Function to format an individual item, defaults to `tostring`.
---  - {opts.kind} `string|nil` Arbitrary item hinting the shape of an item.
---@see |vim.ui.select()|
M.select = wrap(function(items, opts, on_choice)
  vim.ui.select(items, opts, on_choice)
end, 3)

function M.setup()
  config = require("ya-tree.config").config

  M.setup_highlights()
  Canvas.setup()
end

function M.setup_highlights()
  hl.setup()
end

---@return boolean enabled
function M.is_highlight_open_file_enabled()
  return Canvas.is_highlight_open_file_enabled()
end

return M

local wrap = require("plenary.async").wrap

local config = require("ya-tree.config").config
local Canvas = require("ya-tree.ui.canvas")
local help = require("ya-tree.ui.help")
local hl = require("ya-tree.ui.highlights")
local log = require("ya-tree.log")

local api = vim.api

---@class TabData
---@field canvas YaTreeCanvas

local M = {
  ---@private
  ---@type table<string, TabData>
  _tabs = {},
}

---@return TabData|nil tab
local function get_tab()
  return M._tabs[tostring(api.nvim_get_current_tabpage())]
end

---@param tabpage number
function M.delete_tab(tabpage)
  tabpage = tostring(tabpage)
  if M._tabs[tabpage] then
    M._tabs[tabpage].canvas:delete()
    M._tabs[tabpage] = nil
  end
end

---@return boolean
function M.is_open()
  local tab = get_tab()
  return tab and tab.canvas:is_open()
end

---@param root YaTreeNode
---@param opts? {hijack_buffer?: boolean, focus?: boolean}
---  - {opts.hijack_buffer?} `boolean`
---  - {opts.focus?} `boolean`
---@param node? YaTreeNode
function M.open(root, opts, node)
  opts = opts or {}
  local tabpage = tostring(api.nvim_get_current_tabpage())
  local tab = M._tabs[tabpage]
  if not tab then
    tab = {
      canvas = Canvas:new(),
    }
    M._tabs[tabpage] = tab
  end

  local canvas = tab.canvas
  if not canvas:is_open() then
    canvas:open(root, opts)
  elseif node then
    -- the tree might need to be redrawn if a specific node is to be focused
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

function M.close()
  local tab = get_tab()
  if tab then
    tab.canvas:close()
  end
end

---@param root YaTreeNode
---@param node? YaTreeNode
---@param opts? {focus_node?: boolean}
---  - {opts.focus_node?} `boolean` focuse `node`
function M.update(root, node, opts)
  opts = opts or {}
  local tab = get_tab()
  if not tab or not tab.canvas:is_open() then
    return
  end

  local canvas = tab.canvas
  canvas:render(root)
  -- only update the focused node if the current window is the view window,
  -- or explicitly requested
  if node and (opts.focus_node or canvas:has_focus()) then
    canvas:focus_node(node)
  end
end

---@return YaTreeNode? current_node
function M.get_current_node()
  local tab = get_tab()
  if not tab or not tab.canvas:is_open() then
    log.error("called when tab=%s", tab and "not open" or "nil")
    return
  end

  return tab.canvas:get_current_node()
end

---@return YaTreeNode[] selected_nodes
function M.get_selected_nodes()
  local tab = get_tab()
  if not tab or not tab.canvas:is_open() then
    log.error("called when tab=%s", tab and "not open" or "nil")
    return {}
  end

  return tab.canvas:get_selected_nodes()
end

---@param node YaTreeNode
function M.focus_node(node)
  local tab = get_tab()
  if not tab or not tab.canvas:is_open() then
    log.error("called when tab=%s", tab and "not open" or "nil")
    return
  end

  tab.canvas:focus_node(node)
end

function M.focus_prev_sibling()
  local tab = get_tab()
  if not tab or not tab.canvas:is_open() then
    log.error("called when tab=%s", tab and "not open" or "nil")
    return
  end

  tab.canvas:focus_prev_sibling()
end

function M.focus_next_sibling()
  local tab = get_tab()
  if not tab or not tab.canvas:is_open() then
    log.error("called when tab=%s", tab and "not open" or "nil")
    return
  end

  tab.canvas:focus_next_sibling()
end

function M.focus_first_sibling()
  local tab = get_tab()
  if not tab or not tab.canvas:is_open() then
    log.error("called when tab=%s", tab and "not open" or "nil")
    return
  end

  tab.canvas:focus_first_sibling()
end

function M.focus_last_sibling()
  local tab = get_tab()
  if not tab or not tab.canvas:is_open() then
    log.error("called when tab=%s", tab and "not open" or "nil")
    return
  end

  tab.canvas:focus_last_sibling()
end

function M.focus_prev_git_item()
  local tab = get_tab()
  if not tab or not tab.canvas:is_open() then
    log.error("called when tab=%s", tab and "not open" or "nil")
    return
  end

  tab.canvas:focus_prev_git_item()
end

function M.focus_next_git_item()
  local tab = get_tab()
  if not tab or not tab.canvas:is_open() then
    log.error("called when tab=%s", tab and "not open" or "nil")
    return
  end

  tab.canvas:focus_next_git_item()
end

function M.move_cursor_to_name()
  local tab = get_tab()
  if not tab or not tab.canvas:is_open() then
    log.error("called when tab=%s", tab and "not open" or "nil")
    return
  end

  tab.canvas:move_cursor_to_name()
end

---@param winid? number
---@return boolean is_floating
function M.is_window_floating(winid)
  local win_config = api.nvim_win_get_config(winid or 0)
  return win_config.relative > "" or win_config.external
end

---@return boolean
function M.is_current_window_ui()
  local tab = get_tab()
  return tab and tab.canvas:is_current_window_canvas() or false
end

---@param bufnr number
---@return boolean
function M.is_buffer_yatree(bufnr)
  local ok, filetype = pcall(api.nvim_buf_get_option, bufnr, "filetype")
  return ok and filetype == "YaTree" or false
end

---@return number height, number width
function M.get_size()
  local tab = get_tab()
  if not tab or not tab.canvas:is_open() then
    log.error("called when tab=%s", tab and "not open" or "nil")
    return
  end

  return tab.canvas:get_size()
end

function M.reset_window()
  local tab = get_tab()
  if not tab or not tab.canvas:is_open() then
    log.error("called when tab=%s", tab and "not open" or "nil")
    return
  end

  tab.canvas:reset_canvas()
end

---@return YaTreeCanvasMode mode
function M.get_view_mode()
  local tab = get_tab()
  return tab and tab.canvas.mode
end

function M.open_help()
  help.show()
end

---@return boolean
function M.is_search_open()
  local tab = get_tab()
  return tab and tab.canvas.mode == "search" or false
end

---@param search_root YaTreeSearchNode
function M.open_search(search_root)
  local tab = get_tab()
  if not tab or not tab.canvas:is_open() then
    log.error("called when tab=%s", tab and "not open" or "nil")
    return
  end

  tab.canvas.mode = "search"
  tab.canvas:render(search_root)
end

---@param root YaTreeNode
---@param node YaTreeNode
function M.close_search(root, node)
  local tab = get_tab()
  if not tab then
    return
  end

  local canvas = tab.canvas
  canvas.mode = "tree"
  canvas:render(root)
  if node and canvas:has_focus() then
    canvas:focus_node(node)
  end
end

---@param bufnr number
function M.on_win_leave(bufnr)
  local tab = get_tab()
  if not tab or M.is_buffer_yatree(bufnr) then
    return
  end

  if not (M.is_window_floating() or tab.canvas:is_current_window_canvas()) then
    tab.canvas:set_edit_winid(api.nvim_get_current_win())
  end
end

function M.restore()
  local tab = get_tab()
  if not tab or not tab.canvas:is_open() then
    log.error("called when tab=%s", tab and "not open" or "nil")
    return
  end

  tab.canvas:restore()
end

---@param canvas YaTreeCanvas
---@return number winid the winid of the created edit window
local function create_edit_window(canvas)
  local position = config.view.side ~= "left" and "aboveleft" or "belowright"
  vim.cmd(position .. " vsplit")
  local winid = api.nvim_get_current_win()
  canvas:set_edit_winid(winid)
  canvas:resize()

  return winid
end

---@param bufnr number
function M.move_buffer_to_edit_window(bufnr)
  local tab = get_tab()
  if not tab or not tab.canvas:is_open() or M.is_buffer_yatree(bufnr) then
    return
  end

  local canvas = tab.canvas
  if canvas:is_current_window_canvas() then
    if not canvas:get_edit_winid() then
      create_edit_window(canvas)
    end
    canvas:move_buffer_to_edit_window(bufnr)
  end
end

---@param file string the file path to open
---@param cmd cmdmode
function M.open_file(file, cmd)
  local tab = get_tab()
  if not tab then
    log.error("ui is not present, cannot open file %q with command %q", file, cmd)
    return
  end

  local canvas = tab.canvas
  local winid = canvas:get_edit_winid()
  if not winid then
    -- only the tree window is open, e.g. netrw replacement
    -- create a new window for buffers

    winid = create_edit_window(canvas)
    if cmd == "split" or cmd == "vsplit" then
      cmd = "edit"
    end
  end

  api.nvim_set_current_win(winid)
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

local wrap = require("plenary.async").wrap

local config = require("ya-tree.config").config
local Canvas = require("ya-tree.ui.canvas")
local hl = require("ya-tree.ui.highlights")
local log = require("ya-tree.log")

local api = vim.api

---@class TabData
---@field tabpage number
---@field canvas YaTreeCanvas

local M = {
  ---@private
  ---@type table<string, TabData>
  _tabs = {},
}

---@param tabpage? number
---@return TabData|nil tab
local function get_tab(tabpage)
  return M._tabs[tostring(tabpage or api.nvim_get_current_tabpage())]
end

---@param tabpage number
function M.delete_tab(tabpage)
  tabpage = tostring(tabpage)
  if M._tabs[tabpage] then
    M._tabs[tabpage].canvas:delete()
    M._tabs[tabpage] = nil
  end
end

---@param tabpage? number
---@return boolean
function M.is_open(tabpage)
  local tab = get_tab(tabpage)
  return tab and tab.canvas:is_open()
end

---@param root YaTreeNode
---@param opts? {hijack_buffer?: boolean, focus?: boolean}
---  - {opts.hijack_buffer?} `boolean`
---  - {opts.focus?} `boolean`
---@param node? YaTreeNode
function M.open(root, opts, node)
  opts = opts or {}
  local tabpage = api.nvim_get_current_tabpage()
  local tab = M._tabs[tostring(tabpage)]
  if not tab then
    tab = {
      tabpage = tabpage,
      canvas = Canvas:new(),
      in_help = false,
      in_search = false,
    }
    M._tabs[tostring(tabpage)] = tab
  end
  local canvas = tab.canvas

  canvas:open(root, opts)

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
---@param opts {focus?: boolean, tabpage?: number}
---  - {opts.focus?} `boolean` focuse `node`
---  - {opts.tabpage?} `number`
function M.update(root, node, opts)
  opts = opts or {}
  local tab = get_tab(opts.tabpage)
  if not tab or not tab.canvas:is_open() then
    return
  end

  local canvas = tab.canvas
  canvas:render_tree(root, { redraw = true })
  -- only update the focused node if the current window is the view window,
  -- or explicitly requested
  if node and (opts.focus or canvas:has_focus()) then
    canvas:focus_node(node)
  end
end

---@param node YaTreeNode|YaTreeSearchNode
function M.focus_node(node)
  local tab = get_tab()
  if not tab or not tab.canvas:is_open() then
    log.error("ui.focus_node called when tab=%s", tab and "not open" or "nil")
    return
  end

  tab.canvas:focus_node(node)
end

function M.focus_prev_sibling()
  local tab = get_tab()
  if not tab or not tab.canvas:is_open() then
    log.error("ui.focus_prev_sibling called when tab=%s", tab and "not open" or "nil")
    return
  end

  tab.canvas:focus_prev_sibling()
end

function M.focus_next_sibling()
  local tab = get_tab()
  if not tab or not tab.canvas:is_open() then
    log.error("ui.focus_next_sibling called when tab=%s", tab and "not open" or "nil")
    return
  end

  tab.canvas:focus_next_sibling()
end

function M.focus_first_sibling()
  local tab = get_tab()
  if not tab or not tab.canvas:is_open() then
    log.error("ui.focus_first_sibling called when tab=%s", tab and "not open" or "nil")
    return
  end

  tab.canvas:focus_first_sibling()
end

function M.focus_last_sibling()
  local tab = get_tab()
  if not tab or not tab.canvas:is_open() then
    log.error("ui.focus_last_sibling called when tab=%s", tab and "not open" or "nil")
    return
  end

  tab.canvas:focus_last_sibling()
end

function M.get_current_node()
  local tab = get_tab()
  if not tab or not tab.canvas:is_open() then
    log.error("ui.get_current_node called when tab=%s", tab and "not open" or "nil")
    return
  end

  return tab.canvas:get_current_node()
end

function M.move_cursor_to_name()
  local tab = get_tab()
  if not tab or not tab.canvas:is_open() then
    log.error("ui.move_cursor_to_name called when tab=%s", tab and "not open" or "nil")
    return
  end

  tab.canvas:move_cursor_to_name()
end

---@return YaTreeNode[]
function M.get_selected_nodes()
  local tab = get_tab()
  if not tab or not tab.canvas:is_open() then
    log.error("ui.get_selected_nodes called when tab=%s", tab and "not open" or "nil")
    return {}
  end

  return tab.canvas:get_selected_nodes()
end

---@param winid? number
---@return boolean is_floating
function M.is_window_floating(winid)
  local win_config = api.nvim_win_get_config(winid or 0)
  return win_config.relative > "" or win_config.external
end

---@param bufnr number
---@return boolean
function M.is_buffer_yatree(bufnr)
  local ok, filetype = pcall(api.nvim_buf_get_option, bufnr, "filetype")
  return ok and filetype == "YaTree"
end

function M.get_size()
  local tab = get_tab()
  if not tab then
    log.error("ui.get_ui_winid_and_size called when tab=%s", tab)
    return
  end

  return tab.canvas:get_size()
end

function M.reset_window()
  local tab = get_tab()
  if not tab then
    log.error("ui.reset_ui_window called when tab=%s", tab)
    return
  end

  tab.canvas:reset_canvas()
end

---@param root YaTreeNode|YaTreeSearchNode
---@param node YaTreeNode|YaTreeSearchNode
function M.toggle_help(root, node)
  local tab = get_tab()
  if not tab then
    log.error("ui.toggle_help called when tab=%s", tab)
    return
  end

  local canvas = tab.canvas

  if canvas.in_help then
    if canvas.mode == "search" then
      canvas:render_search(root)
      canvas:focus_node(node)
    else
      canvas:render_tree(root, { redraw = true })
      canvas:focus_node(node)
    end
  else
    canvas:render_help()
  end
end

---@param tabpage? number
---@return boolean
function M.is_help_open(tabpage)
  local tab = get_tab(tabpage)
  return tab and tab.canvas.in_help
end

---@param search_root YaTreeSearchNode
function M.open_search(search_root)
  local tab = get_tab()
  if not tab then
    log.error("ui.search called when tab=%s", tab)
    return
  end

  tab.canvas:render_search(search_root)
end

---@param tabpage? number
---@return boolean
function M.is_search_open(tabpage)
  local tab = get_tab(tabpage)
  return tab and tab.canvas.mode == "search"
end

---@param root YaTreeNode
---@param node YaTreeNode
function M.close_search(root, node)
  local tab = get_tab()
  if tab and tab.canvas.mode == "search" then
    M.update(root, node)
  end
end

---@param bufnr number
function M.on_win_leave(bufnr)
  local tab = get_tab()
  if not tab then
    return
  end

  if not M.is_buffer_yatree(bufnr) then
    local is_floating_win = M.is_window_floating()
    local is_ui_win = tab.canvas:is_current_window_canvas()
    if not (is_floating_win or is_ui_win) then
      tab.canvas:set_edit_winid(api.nvim_get_current_win())
    end
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
    -- only the tree window is open, i.e. netrw replacement
    -- create a new window for buffers

    local position = config.view.side == "left" and "belowright" or "aboveleft"
    vim.cmd(position .. " vsp")
    canvas:set_edit_winid(winid)
    canvas:resize()
    if cmd == "split" or cmd == "vsplit" then
      cmd = "edit"
    end
  end

  api.nvim_set_current_win(winid)
  vim.cmd(cmd .. " " .. vim.fn.fnameescape(file))
end

---@type fun(opts: {prompt: string|nil, default: string|nil, completion: string|nil, highlight: fun()}): string?
---@see |vim.ui.input()|
M.input = wrap(function(opts, on_confirm)
  vim.ui.input(opts, on_confirm)
end, 2)

---@type fun(items: string[], opts: {prompt: string|nil, format_item: fun(item: any), kind: string|nil}): string?, number?
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

return M

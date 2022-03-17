local wrap = require("plenary.async").wrap

local Canvas = require("ya-tree.ui.canvas")
local hl = require("ya-tree.ui.highlights")
local log = require("ya-tree.log")

local api = vim.api

---@class TabData
---@field tabpage number
---@field canvas YaTreeCanvas

local M = {
  ---@private
  ---@type table<number, TabData>
  _tabs = {},
}

---@return TabData|nil tab
local function get_tab()
  return M._tabs[api.nvim_get_current_tabpage()]
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
  local tabpage = api.nvim_get_current_tabpage()
  local tab = M._tabs[tabpage]
  if not tab then
    tab = {
      tabpage = tabpage,
      canvas = Canvas:new(),
    }
    M._tabs[tabpage] = tab
  end

  local canvas = tab.canvas
  opts.redraw = canvas:open(opts.hijack_buffer)
  if not opts.redraw and not node and not opts.focus then
    return
  end

  canvas:render(root, opts)

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
---@param focus? boolean
function M.update(root, node, focus)
  local tab = get_tab()
  if not tab or not tab.canvas:is_open() then
    log.error("ui.update called when tab=%s", tab and "not open" or "nil")
    return
  end

  local canvas = tab.canvas
  canvas:render(root, { redraw = true })
  -- only update the focused node if the current window is the view window
  if node and (focus or canvas:has_focus()) then
    canvas:focus_node(node)
  end
end

---@param node YaTreeNode
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
  if not tab then
    log.error("ui.get_selected_nodes called when tab=%s", tab)
    return
  end

  return tab.canvas:get_selected_nodes()
end

---@param winid number
---@return boolean
function M.is_window_floating(winid)
  local config = api.nvim_win_get_config(winid or 0)
  return config.relative > "" or config.external
end

---@param bufnr number
---@return boolean
function M.is_buffer_yatree(bufnr)
  local ok, filetype = pcall(api.nvim_buf_get_option, bufnr, "filetype")
  return ok and filetype == "YaTree"
end

---@return number edit_winid
function M.get_edit_winid()
  local tab = get_tab()
  if not tab then
    log.error("ui.get_edit_winid called when tab=%s", tab)
    return
  end

  return tab.canvas:get_edit_winid()
end

function M.set_edit_winid(edit_winid)
  local tab = get_tab()
  if not tab then
    log.error("ui.set_edit_winid called when tab=%s", tab)
    return
  end

  tab.canvas:set_edit_winid(edit_winid)
end

function M.get_ui_winid()
  local tab = get_tab()
  if not tab then
    log.error("ui.get_ui_winid called when tab=%s", tab)
    return
  end

  return tab.canvas:get_winid()
end

function M.get_ui_winid_and_size()
  local tab = get_tab()
  if not tab then
    log.error("ui.get_ui_winid_and_size called when tab=%s", tab)
    return
  end

  return tab.canvas:get_winid_and_size()
end

function M.is_current_window_ui_window()
  local tab = get_tab()
  if not tab then
    log.error("ui.is_current_window_ui_window called when tab=%s", tab)
    return
  end

  return tab.canvas:is_current_window_canvas()
end

function M.reset_ui_window()
  local tab = get_tab()
  if not tab then
    log.error("ui.reset_ui_window called when tab=%s", tab)
    return
  end

  tab.canvas:reset_canvas()
end

function M.resize()
  local tab = get_tab()
  if not tab then
    log.error("ui.resize called when tab=%s", tab)
    return
  end

  tab.canvas:resize()
end

do
  local showing_help = false
  local in_search = false

  ---@param root YaTreeNode
  ---@param node YaTreeNode
  function M.toggle_help(root, node)
    local tab = get_tab()
    if not tab then
      log.error("ui.toggle_help called when tab=%s", tab)
      return
    end

    local canvas = tab.canvas

    showing_help = not showing_help
    if showing_help then
      canvas:render_help()
    else
      if in_search then
        canvas:render()
      else
        canvas:render(root, { redraw = true })
        canvas:focus_node(node)
      end
    end
  end

  ---@return boolean
  function M.is_help_open()
    return showing_help
  end

  ---@param search_root YaTreeSearchNode
  function M.search(search_root)
    in_search = true
    local tab = get_tab()
    if not tab then
      log.error("ui.search called when tab=%s", tab)
      return
    end

    tab.canvas:render_search(search_root)
  end

  ---@return boolean
  function M.is_search_open()
    return in_search
  end

  ---@param root YaTreeNode
  ---@param node YaTreeNode
  function M.close_search(root, node)
    in_search = false
    M.update(root, node)
  end
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

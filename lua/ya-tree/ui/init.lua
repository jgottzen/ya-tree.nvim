local wrap = require("plenary.async").wrap

local Canvas = require("ya-tree.ui.canvas")
local hl = require("ya-tree.ui.highlights")
local log = require("ya-tree.log")("ui")

local api = vim.api

local M = {
  ---@private
  ---@type table<string, Yat.Ui.Canvas>
  _canvases = {},
}

function M.delete_ui_for_nonexisting_tabpages()
  local tabpages = api.nvim_list_tabpages()
  for tabpage, canvas in pairs(M._canvases) do
    if not vim.tbl_contains(tabpages, tonumber(tabpage)) then
      canvas:close()
      log.debug("deleted ui %s for tabpage %s", tostring(canvas), tabpage)
      M._canvases[tabpage] = nil
    end
  end
end

---@return Yat.Ui.Canvas canvas
local function get_canvas()
  return M._canvases[tostring(api.nvim_get_current_tabpage())]
end

---@param tree_type? Yat.Trees.Type
---@return boolean is_open
function M.is_open(tree_type)
  local canvas = get_canvas()
  local is_open = canvas and canvas:is_open() or false
  if is_open and tree_type then
    return canvas.tree_type == tree_type
  end
  return is_open
end

---@param node Yat.Node
---@return boolean
function M.is_node_rendered(node)
  local canvas = get_canvas()
  return canvas and canvas:is_node_rendered(node) or false
end

---@class Yat.Ui.OpenArgs
---@field hijack_buffer? boolean
---@field focus? boolean
---@field focus_edit_window? boolean
---@field position? Yat.Ui.Canvas.Position
---@field size? integer

---@param tree Yat.Tree
---@param node? Yat.Node
---@param opts Yat.Ui.OpenArgs
---  - {opts.hijack_buffer?} `boolean`
---  - {opts.focus?} `boolean`
---  - {opts.focus_edit_window?} `boolean`
---  - {opts.position?} `YaTreeCanvas.Position`
---  - {opts.size?} `integer`
function M.open(tree, node, opts)
  opts = opts or {}
  local tabpage = tostring(api.nvim_get_current_tabpage())
  local canvas = M._canvases[tabpage]
  if not canvas then
    canvas = Canvas:new()
    M._canvases[tabpage] = canvas
  end

  if not canvas:is_open() then
    canvas:open(tree, { hijack_buffer = opts.hijack_buffer, position = opts.position, size = opts.size })
  elseif tree.TYPE ~= canvas.tree_type or (node and not canvas:is_node_rendered(node)) then
    -- redraw the tree if the tree type changed or a specific node is to be focused, and it's currently not rendered
    canvas:render(tree)
  end

  if node then
    canvas:focus_node(node)
  end

  if opts.focus then
    canvas:focus()
  elseif opts.focus_edit_window then
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

---@param tree Yat.Tree
---@param node? Yat.Node
---@param opts? { focus_node?: boolean, focus_window?: boolean }
---  - {opts.focus_node?} `boolean`
---  - {opts.focus_window?} `boolean`
function M.update(tree, node, opts)
  opts = opts or {}
  local canvas = get_canvas()
  if canvas and canvas:is_open() then
    canvas:render(tree)
    if opts.focus_window then
      canvas:focus()
    end
    -- only update the focused node if the current window is the view window,
    -- or explicitly requested
    if node and (opts.focus_node or canvas:has_focus()) then
      canvas:focus_node(node)
    end
  end
end

---@return Yat.Node current_node
function M.get_current_node()
  return get_canvas():get_current_node() --[[@as Yat.Node]]
end

---@return Yat.Node[] selected_nodes
function M.get_selected_nodes()
  return get_canvas():get_selected_nodes()
end

---@param node Yat.Node
function M.focus_node(node)
  get_canvas():focus_node(node)
end

---@param _ Yat.Tree
---@param node Yat.Node
function M.focus_parent(_, node)
  get_canvas():focus_parent(node)
end

---@param _ Yat.Tree
---@param node Yat.Node
function M.focus_prev_sibling(_, node)
  get_canvas():focus_prev_sibling(node)
end

---@param _ Yat.Tree
---@param node Yat.Node
function M.focus_next_sibling(_, node)
  get_canvas():focus_next_sibling(node)
end

---@param _ Yat.Tree
---@param node Yat.Node
function M.focus_first_sibling(_, node)
  get_canvas():focus_first_sibling(node)
end

---@param _ Yat.Tree
---@param node Yat.Node
function M.focus_last_sibling(_, node)
  get_canvas():focus_last_sibling(node)
end

function M.focus_prev_git_item()
  get_canvas():focus_prev_git_item()
end

function M.focus_next_git_item()
  get_canvas():focus_next_git_item()
end

function M.focus_prev_diagnostic_item()
  get_canvas():focus_prev_diagnostic_item()
end

function M.focus_next_diagnostic_item()
  get_canvas():focus_next_diagnostic_item()
end

---@param winid? number
---@return boolean is_floating
function M.is_window_floating(winid)
  local win_config = api.nvim_win_get_config(winid or 0)
  return win_config.relative > "" or win_config.external
end

---@return boolean
function M.is_current_window_ui()
  local canvas = get_canvas()
  return canvas and canvas:is_current_window_canvas() or false
end

---@return number height, number width
function M.get_size()
  return get_canvas():get_size()
end

---@return Yat.Trees.Type|nil tree_type
function M.get_tree_type()
  local canvas = get_canvas()
  return canvas and canvas.tree_type
end

function M.restore()
  get_canvas():restore()
end

---@param bufnr number
function M.move_buffer_to_edit_window(bufnr)
  local canvas = get_canvas()
  if not canvas:get_edit_winid() then
    canvas:create_edit_window()
  end
  canvas:move_buffer_to_edit_window(bufnr)
end

---@param file string the file path to open
---@param cmd Yat.Action.Files.Open.Mode
function M.open_file(file, cmd)
  local canvas = get_canvas()
  local winid = canvas:get_edit_winid()
  if not winid then
    -- only the tree window is open, e.g. netrw replacement
    -- create a new window for buffers

    canvas:create_edit_window()
    if cmd == "split" or cmd == "vsplit" then
      cmd = "edit"
    end
  else
    api.nvim_set_current_win(winid)
  end

  vim.cmd(cmd .. " " .. vim.fn.fnameescape(file))
end

---@type async fun(opts: {prompt: string|nil, default: string|nil, completion: string|nil, highlight: fun()|nil}): string|nil
M.input = wrap(function(opts, on_confirm)
  vim.ui.input(opts, on_confirm)
end, 2)

---@type async fun(items: table, opts: {prompt: string|nil, format_item: fun(item: any), kind: string|nil}): string?, number?
M.select = wrap(function(items, opts, on_choice)
  vim.ui.select(items, opts, on_choice)
end, 3)

---@return boolean enabled
function M.is_highlight_open_file_enabled()
  return Canvas.is_highlight_open_file_enabled()
end

---@param bufnr number
local function on_win_leave(bufnr)
  if M.is_window_floating() then
    return
  end
  local ok, buftype = pcall(api.nvim_buf_get_option, bufnr, "buftype")
  if not ok or buftype ~= "" then
    return
  end

  local canvas = get_canvas()
  if canvas and not canvas:is_current_window_canvas() then
    canvas:set_edit_winid(api.nvim_get_current_win())
  end
end

function M.setup()
  hl.setup()
  Canvas.setup()

  local events = require("ya-tree.events")
  local event = require("ya-tree.events.event").autocmd

  events.on_autocmd_event(event.TAB_CLOSED, "YA_TREE_UI_TAB_CLOSE_CLEANUP", M.delete_ui_for_nonexisting_tabpages)
  events.on_autocmd_event(event.WINDOW_LEAVE, "YA_TREE_UI_SAVE_EDIT_WINDOW_ID", on_win_leave)
  events.on_autocmd_event(event.COLORSCHEME, "YA_TREE_UI_HIGHLIGHTS", hl.setup)
end

return M

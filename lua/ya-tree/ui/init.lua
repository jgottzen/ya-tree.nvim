local wrap = require("plenary.async").wrap

local Canvas = require("ya-tree.ui.canvas")
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
    log.debug("deleting ui for tabpage %s", tabpage)
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

---@param node YaTreeNode
---@return boolean
function M.is_node_rendered(node)
  local canvas = get_canvas()
  return canvas and canvas:is_node_rendered(node) or false
end

---@param root YaTreeNode
---@param node? YaTreeNode
---@param opts? {hijack_buffer?: boolean, focus?: boolean, focus_edit_window?: boolean, view_mode?: YaTreeCanvasViewMode}
---  - {opts.hijack_buffer?} `boolean`
---  - {opts.focus?} `boolean`
---  - {opts.focus_edit_window?} `boolean`
---  - {opts.view_mode?} `YaTreeCanvasViewMode`
function M.open(root, node, opts)
  opts = opts or {}
  local tabpage = tostring(api.nvim_get_current_tabpage())
  local canvas = M._canvases[tabpage]
  if not canvas then
    canvas = Canvas:new()
    M._canvases[tabpage] = canvas
  end
  local view_mode_change = opts.view_mode and canvas.view_mode ~= opts.view_mode or false
  if view_mode_change then
    canvas.view_mode = opts.view_mode --[[@as YaTreeCanvasViewMode]]
  end

  if not canvas:is_open() then
    canvas:open(root, opts)
  elseif view_mode_change or (node and not canvas:is_node_rendered(node)) then
    -- redraw the tree if the diplay mode changed or a specific node is to be focused, and it's currently not rendered
    canvas:render(root)
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

---@return YaTreeNode|nil current_node
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

---@return YaTreeCanvasViewMode|nil view_mode
function M.get_view_mode()
  local canvas = get_canvas()
  return canvas and canvas.view_mode
end

---@param view_mode YaTreeCanvasViewMode
function M.set_view_mode(view_mode)
  local canvas = get_canvas()
  if canvas then
    canvas.view_mode = view_mode
  end
end

---@return boolean
function M.is_search_view_open()
  return M.get_view_mode() == "search"
end

---@param mode YaTreeCanvasViewMode
---@param root YaTreeNode
---@param node? YaTreeNode
local function change_view_mode(mode, root, node)
  local canvas = get_canvas()
  canvas.view_mode = mode
  canvas:render(root)
  if node then
    canvas:focus_node(node)
  end
end

---@param root YaTreeSearchRootNode
---@param node? YaTreeSearchNode
function M.open_search_view(root, node)
  change_view_mode("search", root, node)
end

---@param root YaTreeNode
---@param node YaTreeNode
function M.close_search_view(root, node)
  change_view_mode("files", root, node)
end

---@return boolean
function M.is_git_view_open()
  return M.get_view_mode() == "git"
end

---@param root YaTreeGitRootNode
---@param node? YaTreeGitNode
function M.open_git_view(root, node)
  change_view_mode("git", root, node)
end

---@param root YaTreeNode
---@param node YaTreeNode
function M.close_git_view(root, node)
  change_view_mode("files", root, node)
end

---@return boolean
function M.is_buffers_view_open()
  return M.get_view_mode() == "buffers"
end

---@param root YaTreeBufferRootNode
---@param node? YaTreeBufferNode
function M.open_buffers_view(root, node)
  change_view_mode("buffers", root, node)
end

---@param root YaTreeNode
---@param node YaTreeNode
function M.close_buffers_view(root, node)
  change_view_mode("files", root, node)
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
---@param cmd cmd_mode
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
  ---@type number
  local group = api.nvim_create_augroup("YaTreeUi", { clear = true })
  api.nvim_create_autocmd("WinLeave", {
    group = group,
    callback = function(input)
      on_win_leave(input.buf)
    end,
    desc = "Keeping track of which window to open buffers in",
  })
  api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = function()
      hl.setup()
    end,
    desc = "Updating highlights",
  })

  hl.setup()
  Canvas.setup()
end

---@return boolean enabled
function M.is_highlight_open_file_enabled()
  return Canvas.is_highlight_open_file_enabled()
end

return M

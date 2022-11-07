local wrap = require("plenary.async").wrap

local Canvas = require("ya-tree.ui.canvas")
local log = require("ya-tree.log")("ui")

local api = vim.api

---@alias Yat.Ui.Position "left" | "right" | "top" | "bottom"

---@class Yat.Ui.HighlightGroup
---@field name string
---@field from integer
---@field to integer

local M = {
  ---@private
  ---@type table<integer, Yat.Ui.Canvas>
  _canvases = {},
}

function M.delete_ui_for_nonexisting_tabpages()
  local tabpages = api.nvim_list_tabpages()
  for tabpage, canvas in pairs(M._canvases) do
    if not vim.tbl_contains(tabpages, tabpage) then
      canvas:close()
      log.info("deleted ui %s for tabpage %s", tostring(canvas), tabpage)
      M._canvases[tabpage] = nil
    end
  end
end

---@param tabpage? integer
---@return Yat.Ui.Canvas canvas
local function get_canvas(tabpage)
  return M._canvases[tabpage or api.nvim_get_current_tabpage()]
end

---@param tabpage integer
---@param tree? Yat.Tree
---@return boolean is_open
function M.is_open(tabpage, tree)
  local canvas = get_canvas(tabpage)
  local is_open = canvas and canvas:is_open() or false
  if is_open and tree then
    return canvas:is_tree_rendered(tree)
  end
  return is_open
end

---@param tabpage integer
---@param tree Yat.Tree
---@param node Yat.Node
---@return boolean
function M.is_node_rendered(tabpage, tree, node)
  local canvas = get_canvas(tabpage)
  return canvas and canvas:is_node_rendered(tree, node) or false
end

---@class Yat.Ui.OpenArgs
---@field focus? boolean
---@field focus_edit_window? boolean
---@field position? Yat.Ui.Position
---@field size? integer

---@param sidebar Yat.Sidebar
---@param tree Yat.Tree
---@param node? Yat.Node
---@param opts Yat.Ui.OpenArgs
---  - {opts.focus?} `boolean`
---  - {opts.focus_edit_window?} `boolean`
---  - {opts.position?} `YaTreeCanvas.Position`
---  - {opts.size?} `integer`
function M.open(sidebar, tree, node, opts)
  local tabpage = api.nvim_get_current_tabpage()
  local canvas = M._canvases[tabpage]
  if not canvas then
    canvas = Canvas:new()
    M._canvases[tabpage] = canvas
  elseif canvas:is_open() then
    return
  end

  opts = opts or {}
  canvas:open(sidebar, { position = opts.position, size = opts.size })

  if node then
    canvas:focus_node(tree, node)
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

---@param tree? Yat.Tree
---@param node? Yat.Node
---@param opts? { focus_node?: boolean, focus_window?: boolean }
---  - {opts.focus_node?} `boolean`
---  - {opts.focus_window?} `boolean`
function M.update(tree, node, opts)
  opts = opts or {}
  local canvas = get_canvas()
  if canvas and canvas:is_open() then
    canvas:draw()
    if opts.focus_window then
      canvas:focus()
    end
    -- only update the focused node if the current window is the view window,
    -- or explicitly requested
    if tree and node and (opts.focus_node or canvas:has_focus()) then
      canvas:focus_node(tree, node)
    end
  end
end

---@param tabpage integer
---@return Yat.Tree current_tree, Yat.Node current_node
function M.get_current_tree_and_node(tabpage)
  return get_canvas(tabpage):get_current_tree_and_node()
end

---@return Yat.Node[] selected_nodes
function M.get_selected_nodes()
  return get_canvas():get_selected_nodes()
end

---@param row integer
function M.focus_row(row)
  get_canvas():focus_row(row)
end

---@param tree Yat.Tree
---@param node Yat.Node
function M.focus_node(tree, node)
  get_canvas():focus_node(tree, node)
end

---@param winid? integer
---@return boolean is_floating
function M.is_window_floating(winid)
  local win_config = api.nvim_win_get_config(winid or 0)
  return win_config.relative > "" or win_config.external
end

---@param tabpage integer
---@return boolean
function M.is_current_window_ui(tabpage)
  local canvas = get_canvas(tabpage)
  return canvas and canvas:is_current_window_canvas() or false
end

---@return integer height, integer width
function M.get_size()
  return get_canvas():get_size()
end

---@param tabpage integer
function M.restore(tabpage)
  get_canvas(tabpage):restore()
end

---@param tabpage integer
---@param bufnr integer
function M.move_buffer_to_edit_window(tabpage, bufnr)
  local canvas = get_canvas(tabpage)
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

---@type async fun(items: table, opts: {prompt: string|nil, format_item: fun(item: any), kind: string|nil}): string?, integer?
M.select = wrap(function(items, opts, on_choice)
  vim.ui.select(items, opts, on_choice)
end, 3)

---@param bufnr integer
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

---@param config Yat.Config
function M.setup(config)
  local hl = require("ya-tree.ui.highlights")
  hl.setup()
  require("ya-tree.ui.renderers").setup(config)
  Canvas.setup()

  local group = api.nvim_create_augroup("YaTreeUi", { clear = true })
  api.nvim_create_autocmd("TabClosed", {
    group = group,
    callback = M.delete_ui_for_nonexisting_tabpages,
    desc = "Clean up after closing tabpage",
  })
  api.nvim_create_autocmd("WinLeave", {
    group = group,
    callback = on_win_leave,
    desc = "Save the last used window id",
  })

  local events = require("ya-tree.events")
  local event = require("ya-tree.events.event").autocmd
  events.on_autocmd_event(event.COLORSCHEME, "YA_TREE_UI_HIGHLIGHTS", hl.setup)
end

return M

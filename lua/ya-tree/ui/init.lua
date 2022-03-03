local wrap = require("plenary.async").wrap

local hl = require("ya-tree.ui.highlights")
local view = require("ya-tree.ui.view")
local canvas = require("ya-tree.ui.canvas")

local api = vim.api
local fn = vim.fn

local M = {}

M.is_open = view.is_open

function M.open(root, opts, node)
  opts = opts or {}
  local is_open = view.is_open()
  if is_open and not opts.redraw and not node then
    return
  end

  if not is_open then
    opts.redraw = view.open(opts.hijack_buffer) or opts.redraw
  end
  canvas.render(root, opts)
  if node then
    M.focus_node(node)
  end
  if opts.focus then
    view.focus()
  else
    api.nvim_set_current_win(view.get_edit_winnr())
  end
end

M.close = view.close

function M.focus(root)
  if not view.is_open() then
    M.open(root, { focus = true })
  else
    view.focus()
  end
end

function M.update(root, node)
  if not view.is_open() then
    return
  end

  canvas.render(root, { redraw = true })
  local winnr = api.nvim_get_current_win()
  -- only update the focused node if the current window is the view window
  if node and winnr == view.winnr() then
    M.focus_node(node)
  end
end

M.focus_node = canvas.focus_node
M.focus_prev_sibling = canvas.focus_prev_sibling
M.focus_next_sibling = canvas.focus_next_sibling
M.focus_first_sibling = canvas.focus_first_sibling
M.focus_last_sibling = canvas.focus_last_sibling

M.get_current_node = canvas.get_current_node
M.move_cursor_to_name = canvas.move_cursor_to_name

function M.get_selected_nodes()
  -- see https://github.com/neovim/neovim/pull/13896
  local from = fn.getpos("v")
  local to = fn.getcurpos()
  if from[2] > to[2] then
    from, to = to, from
  end

  return canvas.get_nodes_for_lines(from[2], to[2])
end

M.get_edit_winnr = view.get_edit_winnr
M.set_edit_winnr = view.set_edit_winnr

function M.is_current_window_floating()
  local config = api.nvim_win_get_config(0)
  return config.relative > "" or config.external
end

function M.is_buffer_yatree(bufnr)
  return view.bufnr() == bufnr
end

M.is_current_win_ui_win = view.is_current_win_ui_win
M.get_ui_winnr_and_size = view.get_winnr_and_size
M.reset_ui_window = view.reset_ui_window

function M.resize()
  if view.is_open() then
    view.resize()
  end
end

do
  local showing_help = false
  local in_search = false

  function M.toggle_help(root, node)
    if not view.is_open() then
      view.open()
    end

    showing_help = not showing_help
    if showing_help then
      canvas.render_help()
    else
      if in_search then
        canvas.render()
      else
        canvas.render(root, { redraw = true })
        M.focus_node(node)
      end
    end
  end

  function M.is_help_open()
    return showing_help
  end

  function M.search(search_root)
    in_search = true
    canvas.render_search(search_root)
  end

  function M.is_search_open()
    return in_search
  end

  function M.close_search(root, node)
    in_search = false
    M.update(root, node)
  end
end

M.input = wrap(function(opts, callback)
  vim.ui.input(opts, callback)
end, 2)

function M.setup()
  M.setup_highlights()
  canvas.setup()
  view.setup()
end

function M.setup_highlights()
  hl.setup()
end

return M

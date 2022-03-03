local config = require("ya-tree.config").config
local log = require("ya-tree.log")

local api = vim.api

local M = {
  view = {
    edit_winnr = nil,
    winnr = nil,
    bufnr = nil,
    win_options = {
      number = false,
      relativenumber = false,
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
    },
  },
}

local buf_options = {
  { name = "bufhidden", value = "hide" },
  { name = "buflisted", value = false },
  { name = "filetype", value = "YaTree" },
  { name = "buftype", value = "nofile" },
  { name = "modifiable", value = false },
  { name = "swapfile", value = false },
}

function M.is_open()
  return M.view.winnr ~= nil and api.nvim_win_is_valid(M.view.winnr)
end

local function is_buffer_loaded(bufnr)
  return bufnr ~= nil and api.nvim_buf_is_valid(bufnr) and api.nvim_buf_is_loaded(bufnr)
end

function M.bufnr()
  return is_buffer_loaded(M.view.bufnr) and M.view.bufnr or nil
end

function M.winnr()
  return M.is_open() and M.view.winnr or nil
end

function M.is_current_win_ui_win()
  return api.nvim_get_current_win() == M.view.winnr
end

function M.get_winnr_and_size()
  local winnr = M.winnr()
  if winnr then
    local height = api.nvim_win_get_height(winnr)
    local width = api.nvim_win_get_width(winnr)
    return winnr, height, width
  end
end

local function format_option(key, value)
  if value == true then
    return key
  elseif value == false then
    return string.format("no%s", key)
  else
    return string.format("%s=%s", key, value)
  end
end

function M.reset_ui_window()
  if not M.view.win_options.number and not M.view.win_options.relativenumber then
    api.nvim_command("stopinsert")
    api.nvim_command("noautocmd setlocal norelativenumber")
  end
end

local function delete_buffers()
  for _, bufnr in ipairs(api.nvim_list_bufs()) do
    if bufnr ~= M.view.bufnr and vim.fn.bufname(bufnr) == "YaTree" then
      pcall(api.nvim_buf_delete, bufnr, { force = true })
    end
  end
end

local function create_buffer(hijack_buffer)
  M.view.bufnr = hijack_buffer and api.nvim_get_current_buf() or api.nvim_create_buf(false, false)
  delete_buffers()
  api.nvim_buf_set_name(M.view.bufnr, "YaTree")

  for _, v in ipairs(buf_options) do
    api.nvim_buf_set_option(M.view.bufnr, v.name, v.value)
  end

  require("ya-tree.actions").apply_mappings(M.view.bufnr)
end

local function set_window_options_and_size()
  api.nvim_win_set_buf(M.view.winnr, M.view.bufnr)
  api.nvim_command("noautocmd wincmd " .. (M.view.side == "right" and "L" or "H"))
  api.nvim_command("noautocmd vertical resize " .. M.view.width)

  for k, v in pairs(M.view.win_options) do
    api.nvim_command(string.format("noautocmd setlocal %s", format_option(k, v)))
  end

  M.resize()
end

local function create_window()
  api.nvim_command("noautocmd vsplit")

  M.view.winnr = api.nvim_get_current_win()
  set_window_options_and_size()
end

function M.open(hijack_buffer)
  local redraw = false
  if not is_buffer_loaded(M.view.bufnr) then
    redraw = true
    create_buffer(hijack_buffer)
  end

  if hijack_buffer then
    log.debug("view.open: setting edit_winnr to nil")
    M.view.edit_winnr = nil
    M.view.winnr = api.nvim_get_current_win()
    set_window_options_and_size()
  end

  if not M.is_open() then
    log.debug("view.open: setting edit_winnr to %s, old=%s", api.nvim_get_current_win(), M.view.edit_winnr)
    M.view.edit_winnr = api.nvim_get_current_win()
    create_window()
  end

  return redraw
end

function M.resize()
  api.nvim_win_set_width(M.view.winnr, M.view.width)
  vim.cmd("wincmd =")
end

function M.focus()
  local current_winnr = api.nvim_get_current_win()
  local winnr = M.winnr()
  if winnr and current_winnr ~= winnr then
    log.debug("view.focus: winnr=%s setting edit_winnr to %s, old=%s", winnr, current_winnr, M.view.edit_winnr)
    M.view.edit_winnr = current_winnr
    api.nvim_set_current_win(winnr)
  end
end

function M.close()
  local winnr = M.view.winnr
  if not winnr then
    return
  end

  local ok = pcall(api.nvim_win_close, winnr, true)
  M.view.winnr = nil
  if not ok then
    log.error("error closing window %q", winnr)
  end
end

function M.get_edit_winnr()
  return M.view.edit_winnr
end

function M.set_edit_winnr(winnr)
  log.debug("view.set_edit_winnr: setting edit_winnr to %s, old=%s", api.nvim_get_current_win(), M.view.edit_winnr)
  M.view.edit_winnr = winnr
end

function M.setup()
  M.view.width = config.view.width
  M.view.side = config.view.side
  M.view.win_options.number = config.view.number
  M.view.win_options.relativenumber = config.view.relativenumber
end

return M

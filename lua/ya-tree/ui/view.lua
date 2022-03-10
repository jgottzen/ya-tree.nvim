local config = require("ya-tree.config").config
local log = require("ya-tree.log")

local api = vim.api

local M = {
  tabs = {},
}

local win_options = {
  -- number and relativenumber are taken directly from config
  -- number = false,
  -- relativenumber = false,
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
}

local buf_options = {
  { name = "bufhidden", value = "hide" },
  { name = "buflisted", value = false },
  { name = "filetype", value = "YaTree" },
  { name = "buftype", value = "nofile" },
  { name = "modifiable", value = false },
  { name = "swapfile", value = false },
}

---@class TabData
---@field bufnr number
---@field winid number
---@field edit_winid number

---@return TabData
local function get_or_create_tab_data()
  local tabpage = api.nvim_get_current_tabpage()
  local tab = M.tabs[tabpage]
  if not tab then
    tab = {}
    M.tabs[tabpage] = tab
  end

  return tab
end

---@param tab? TabData
---@return boolean
function M.is_open(tab)
  tab = tab or get_or_create_tab_data()
  return tab.winid ~= nil and api.nvim_win_is_valid(tab.winid)
end

---@param bufnr? number
---@return boolean
local function is_buffer_loaded(bufnr)
  return bufnr ~= nil and api.nvim_buf_is_valid(bufnr) and api.nvim_buf_is_loaded(bufnr)
end

---@return number?
function M.bufnr()
  local tab = get_or_create_tab_data()
  return is_buffer_loaded(tab.bufnr) and tab.bufnr
end

---@return number?
function M.winid()
  local tab = M.tabs[api.nvim_get_current_tabpage()]
  return M.is_open(tab) and tab.winid
end

---@return boolean
function M.is_current_win_ui_win()
  local tab = get_or_create_tab_data()
  return api.nvim_get_current_win() == tab.winid
end

---@return number winid, number height, number width
function M.get_winid_and_size()
  local winid = M.winid()
  if winid then
    local height = api.nvim_win_get_height(winid)
    local width = api.nvim_win_get_width(winid)
    return winid, height, width
  end
end

---@param key string
---@param value boolean|string
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
  if not config.view.number and not config.view.relativenumber then
    api.nvim_command("stopinsert")
    api.nvim_command("noautocmd setlocal norelativenumber")
  end
end

---@param tab TabData
---@param hijack_buffer boolean
local function create_buffer(tab, hijack_buffer)
  tab.bufnr = hijack_buffer and api.nvim_get_current_buf() or api.nvim_create_buf(false, false)
  api.nvim_buf_set_name(tab.bufnr, "YaTree")

  for _, v in ipairs(buf_options) do
    api.nvim_buf_set_option(tab.bufnr, v.name, v.value)
  end

  require("ya-tree.actions").apply_mappings(tab.bufnr)
end

---@param tab TabData
local function set_window_options_and_size(tab)
  api.nvim_win_set_buf(tab.winid, tab.bufnr)
  api.nvim_command("noautocmd wincmd " .. (config.view.side == "right" and "L" or "H"))
  api.nvim_command("noautocmd vertical resize " .. config.view.width)

  for k, v in pairs(win_options) do
    api.nvim_command(string.format("noautocmd setlocal %s", format_option(k, v)))
  end
  api.nvim_command(string.format("noautocmd setlocal %s", format_option("number", config.view.number)))
  api.nvim_command(string.format("noautocmd setlocal %s", format_option("relativenumber", config.view.relativenumber)))

  M.resize(tab.winid)
end

---@param tab TabData
local function create_window(tab)
  local edit_winid = api.nvim_get_current_win()
  api.nvim_command("noautocmd vsplit")

  local winid = api.nvim_get_current_win()
  tab.winid = winid
  tab.edit_winid = edit_winid
  set_window_options_and_size(tab)
end

---@param hijack_buffer boolean
---@return boolean redraw, number bufnr
function M.open(hijack_buffer)
  local redraw = false
  local tab = get_or_create_tab_data()
  if not is_buffer_loaded(tab.bufnr) then
    redraw = true
    create_buffer(tab, hijack_buffer)
  end

  if hijack_buffer then
    log.debug("view.open: setting edit_winid to nil")
    tab.winid = api.nvim_get_current_win()
    tab.edit_winid = nil
    set_window_options_and_size(tab)
  end

  if not M.is_open() then
    log.debug("view.open: setting edit_winid to %s, old=%s", api.nvim_get_current_win(), tab.edit_winid)
    create_window(tab)
  end

  return redraw, tab.bufnr
end

---@param winid number
function M.resize(winid)
  api.nvim_win_set_width(winid, config.view.width)
  vim.cmd("wincmd =")
end

function M.focus()
  local tab = get_or_create_tab_data()
  if tab.winid then
    local current_winid = api.nvim_get_current_win()
    if current_winid ~= tab.winid then
      log.debug("view.focus: winid=%s setting edit_winid to %s, old=%s", tab.winid, current_winid, tab.edit_winid)
      tab.edit_winid = current_winid
      api.nvim_set_current_win(tab.winid)
    end
  end
end

function M.close()
  local tab = get_or_create_tab_data()
  if not tab.winid then
    return
  end

  local ok = pcall(api.nvim_win_close, tab.winid, true)
  if not ok then
    tab.winid = nil
    log.error("error closing window %q", tab.winid)
  end
end

---@return number?
function M.get_edit_winid()
  return get_or_create_tab_data().edit_winid
end

---@param winid number
function M.set_edit_winid(winid)
  local tab = get_or_create_tab_data()
  log.debug("view.set_edit_winid: setting edit_winid to %s, old=%s", api.nvim_get_current_win(), tab.edit_winid)
  tab.edit_winid = winid
end

return M

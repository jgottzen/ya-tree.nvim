local log = require("ya-tree.log")

local M = {}

-- use indirection so the config can be required as is for live changes to it
---@module"ya-tree.lib"
local function lib()
  return require("ya-tree.lib")
end

local function setup_commands()
  vim.cmd([[
    command! YaTreeOpen lua require('ya-tree').open()
    command! YaTreeClose lua require('ya-tree').close()
    command! YaTreeToggle lua require('ya-tree').toggle()
    command! YaTreeFocus lua require('ya-tree').focus()
    command! -nargs=? -complete=file YaTreeFindFile lua require('ya-tree').find_file('<args>')
  ]])
end

---@param config YaTreeConfig
local function setup_netrw(config)
  if config.replace_netrw then
    vim.cmd([[silent! autocmd! FileExplorer *]])
    vim.cmd([[autocmd VimEnter * ++once silent! autocmd! FileExplorer *]])
    vim.g.loaded_netrw = 1
    vim.g.loaded_netrwPlugin = 1
  end
end

---@param config YaTreeConfig
local function setup_autocommands(config)
  vim.cmd("augroup YaTree")
  vim.cmd("autocmd!")

  vim.cmd([[autocmd WinLeave * lua require('ya-tree.lib').on_win_leave(vim.fn.expand('<abuf>'))]])
  vim.cmd([[autocmd ColorScheme * lua require('ya-tree.lib').on_color_scheme()]])

  vim.cmd([[autocmd TabEnter * lua require('ya-tree.lib').on_tab_enter()]])
  vim.cmd([[autocmd TabClosed * lua require('ya-tree.lib').on_tab_closed(vim.fn.expand('<afile>'))]])

  vim.cmd([[autocmd BufEnter,BufNewFile * lua require('ya-tree.lib').on_buf_new_file(vim.fn.expand('<afile>:p'), vim.fn.expand('<abuf>'))]])

  if config.auto_close then
    vim.cmd([[autocmd WinClosed * lua require('ya-tree.lib').on_win_closed(vim.fn.expand('<amatch>'))]])
  end
  if config.auto_reload_on_write then
    vim.cmd([[autocmd BufWritePost * lua require('ya-tree.lib').on_buf_write_post(vim.fn.expand('<afile>:p'))]])
  end
  if config.follow_focused_file then
    vim.cmd([[autocmd BufEnter * lua require('ya-tree.lib').on_buf_enter(vim.fn.expand('<afile>:p'), vim.fn.expand('<abuf>'))]])
  end
  if config.hijack_cursor then
    vim.cmd([[autocmd CursorMoved YaTree* lua require('ya-tree.lib').on_cursor_moved()]])
  end
  if config.cwd.follow then
    vim.cmd([[autocmd DirChanged * lua require('ya-tree.lib').on_dir_changed()]])
  end
  if config.git.enable then
    vim.cmd([[autocmd User FugitiveChanged,NeogitStatusRefreshed lua require('ya-tree.lib').on_git_event()]])
  end
  if config.diagnostics.enable then
    vim.cmd([[autocmd DiagnosticChanged * lua require('ya-tree.lib').on_diagnostics_changed()]])
  end

  vim.cmd("augroup END")
end

function M.open()
  lib().open()
end

function M.close()
  lib().close()
end

function M.toggle()
  lib().toggle()
end

function M.focus()
  lib().focus()
end

---@param file string
function M.find_file(file)
  lib().open({ file = file, focus = true })
end

---@param level "'trace'"|"'debug'"|"'info'"|"'warn'"|"'error'"
function M.set_log_level(level)
  log.config.level = level
end

---@param opts YaTreeConfig
function M.setup(opts)
  local config = require("ya-tree.config").setup(opts)

  log.config.level = config.log_level
  log.config.to_console = config.log_to_console
  log.config.to_file = config.log_to_file

  log.trace("using config=%s", config)

  require("ya-tree.actions").setup()
  require("ya-tree.git").setup()
  require("ya-tree.ui").setup()

  setup_commands()
  setup_netrw(config)
  setup_autocommands(config)

  lib().setup()
end

return M

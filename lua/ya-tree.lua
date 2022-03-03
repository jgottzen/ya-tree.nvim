local log = require("ya-tree.log")

local M = {}

-- use indirection so the global is available to all modules
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

local function setup_netrw(config)
  if config.replace_netrw then
    vim.cmd([[silent! autocmd! FileExplorer *]])
    vim.cmd([[autocmd VimEnter * ++once silent! autocmd! FileExplorer *]])
    vim.g.loaded_netrw = 1
    vim.g.loaded_netrwPlugin = 1
  end
end

local function setup_autocommands(config)
  vim.cmd("augroup YaTree")
  vim.cmd("autocmd!")

  vim.cmd([[autocmd WinLeave * lua require('ya-tree.lib').on_win_leave()]])
  vim.cmd([[autocmd ColorScheme * lua require('ya-tree.lib').on_color_scheme()]])

  if config.auto_close then
    vim.cmd([[autocmd WinClosed * lua require('ya-tree.lib').on_win_closed()]])
  end
  if config.auto_reload_on_write then
    vim.cmd([[autocmd BufWritePost * lua require('ya-tree.lib').on_buf_write_post()]])
  end
  if config.follow_focused_file then
    vim.cmd([[autocmd BufEnter * lua require('ya-tree.lib').on_buf_enter()]])
  end
  if config.hijack_cursor then
    vim.cmd([[autocmd CursorMoved YaTree lua require('ya-tree.lib').on_cursor_moved()]])
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

function M.find_file(file)
  lib().navigate_to(file)
end

function M.set_log_level(level)
  log.config.level = level
end

function M.setup(opts)
  local config = require("ya-tree.config").setup(opts)

  log.config.level = config.log_level
  log.config.to_console = config.log_to_console
  log.config.to_file = config.log_to_file

  log.trace("using config=%s", config)

  require("ya-tree.actions").setup()
  require("ya-tree.git").setup(config)
  require("ya-tree.ui").setup()

  setup_netrw(config)
  setup_commands()
  setup_autocommands(config)

  lib().setup()
end

return M

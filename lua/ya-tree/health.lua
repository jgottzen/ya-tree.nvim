local M = {}

function M.check()
  local _start = vim.health.start or vim.health.report_start
  local _ok = vim.health.ok or vim.health.report_ok
  local _warn = vim.health.warn or vim.health.report_warn
  local _error = vim.health.error or vim.health.report_error

  if vim.fn.has("nvim-0.8.0") == 1 then
    _ok("Neovim version >= 0.8.0")
  else
    _error("Neovim version < 0.8.0")
  end

  _start("Checking for required plugins")
  local nui = pcall(require, "nui.input")
  if nui then
    _ok("**plugins:** `nui.nvim` installed")
  else
    _error("**plugins:** `nui.nvim` not installed")
  end

  _start("Checking for optional plugins")
  local devicons = pcall(require, "nvim-web-devicons")
  if devicons then
    _ok("**plugins:** `nvim-web-devicons` installed")
  else
    _warn("**plugins:** `nvim-web-devicons` not installed")
  end

  _start("Checking for executables")
  local git, message = pcall(vim.fn.systemlist, { "git", "--version" })
  if git then
    local version = vim.split(message[1], " ", { plain = true })[3]
    _ok("**git:** `git` version " .. version)
    if vim.fn.executable("yadm") == 1 then
      _ok("**yadm:** `yadm` executable found")
    else
      _warn("**yadm**: no executable found")
    end
  else
    _warn("**git:** no `git` executable found")
  end

  if vim.fn.executable("fd") == 1 then
    _ok("**search:** `fd` executable found")
  elseif vim.fn.executable("fdfind") == 1 then
    _ok("**search:** `fdfind` executable found")
  elseif vim.fn.executable("find") == 1 and vim.fn.has("win32") == 0 then
    _ok("**search:** `find` executable found")
  elseif vim.fn.executable("where") == 1 then
    _ok("**search:** `where` executable found")
  else
    _warn("**search:** no executable found")
  end

  if vim.fn.executable("trash") == 1 then
    _ok("**trash:** `trash` executable found")
  else
    _warn("**trash:** no executable found")
  end

  _start("Checking configuration")
  local config_warnings = false
  if not require("ya-tree.config").setup_called then
    _error("**config:** `ya-tree.setup()` has not been called")
    config_warnings = true
  end
  local config = require("ya-tree.config").config
  if config.search.max_results == 0 then
    _warn("**config:** 'conifg.search.max_results' is set to `0`, this can cause performance problems")
    config_warnings = true
  end
  if not config_warnings then
    _ok("**config:** no issues found")
  end
end

return M

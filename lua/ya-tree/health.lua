local M = {}

function M.check()
  local start, ok, warn, report_error = vim.health.report_start, vim.health.report_ok, vim.health.report_warn, vim.health.report_error

  if vim.fn.has("nvim-0.8.0") == 1 then
    ok("Neovim version >= 0.8.0")
  else
    report_error("Neovim version < 0.8.0")
  end

  start("Checking for required plugins")
  local nui = pcall(require, "nui.input")
  if nui then
    ok("**plugins:** `nui.nvim` installed")
  else
    report_error("**plugins:** `nui.nvim` not installed")
  end

  start("Checking for optional plugins")
  local devicons = pcall(require, "nvim-web-devicons")
  if devicons then
    ok("**plugins:** `nvim-web-devicons` installed")
  else
    warn("**plugins:** `nvim-web-devicons` not installed")
  end

  start("Checking for executables")
  local git, message = pcall(vim.fn.systemlist, { "git", "--version" })
  if git then
    local version = vim.split(message[1], " ", { plain = true })[3]
    ok("**git:** `git` version " .. version)
    if vim.fn.executable("yadm") == 1 then
      ok("**yadm:** `yadm` executable found")
    else
      warn("**yadm**: no executable found")
    end
  else
    warn("**git:** no `git` executable found")
  end

  if vim.fn.executable("fd") == 1 then
    ok("**search:** `fd` executable found")
  elseif vim.fn.executable("fdfind") == 1 then
    ok("**search:** `fdfind` executable found")
  elseif vim.fn.executable("find") == 1 and vim.fn.has("win32") == 0 then
    ok("**search:** `find` executable found")
  elseif vim.fn.executable("where") == 1 then
    ok("**search:** `where` executable found")
  else
    warn("**search:** no executable found")
  end

  if vim.fn.executable("trash") == 1 then
    ok("**trash:** `trash` executable found")
  else
    warn("**trash:** no executable found")
  end

  start("Checking configuration")
  local config_warnings = false
  if not require("ya-tree.config").setup_called then
    report_error("**config:** `ya-tree.setup()` has not been called")
    config_warnings = true
  end
  local config = require("ya-tree.config").config
  if config.search.max_results == 0 then
    warn("**config:** 'conifg.search.max_results' is set to `0`, this can cause performance problems")
    config_warnings = true
  end
  if not config_warnings then
    ok("**config:** no issues found")
  end
end

return M

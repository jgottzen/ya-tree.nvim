local M = {}

function M.check()
  local report_ok, report_warn, report_error = vim.health.report_ok, vim.health.report_warn, vim.health.report_error

  if vim.fn.has("nvim-0.8.0") == 1 then
    report_ok("Neovim version >= 0.8.0")
  else
    report_error("Neovim version < 0.8.0")
  end

  vim.health.report_start("checking for required plugins")
  local plenary = pcall(require, "plenary.async")
  if plenary then
    report_ok("**plugins:** `plenary` installed")
  else
    report_error("**plugins:** `plenary` not installed")
  end

  vim.health.report_start("checking for optional plugins")
  local devicons = pcall(require, "nvim-web-devicons")
  if devicons then
    report_ok("**plugins:** `nvim-web-devicons` installed")
  else
    report_warn("**plugins:** `nvim-web-devicons` not installed")
  end

  vim.health.report_start("checking for executables")
  local git, message = pcall(vim.fn.systemlist, { "git", "--version" })
  if git then
    local version = vim.split(message[1], " ", { plain = true })[3]
    report_ok("**git:** `git` version " .. version)
    if vim.fn.executable("yadm") then
      report_ok("**yadm:** `yadm` executable found")
    else
      report_warn("**yadm**: no executable found")
    end
  else
    report_warn("**git:** no `git` executable found")
  end

  if vim.fn.executable("fd") == 1 then
    report_ok("**search:** `fd` executable found")
  elseif vim.fn.executable("fdfind") == 1 then
    report_ok("**search:** `fdfind` executable found")
  elseif vim.fn.executable("find") == 1 and not vim.fn.has("win32") == 1 then
    report_ok("**search:** `find` executable found")
  elseif vim.fn.executable("where") == 1 then
    report_ok("**search:** `where` executable found")
  else
    report_warn("**search:** no executable found")
  end

  if vim.fn.executable("trash") == 1 then
    report_ok("**trash:** `trash` executable found")
  else
    report_warn("**trash:** no executable found")
  end

  vim.health.report_start("checking config")
  local config = require("ya-tree.config").config
  local config_warnings = false
  if not config.search.max_results or config.search.max_results == 0 then
    report_warn("**config:** 'conifg.search.max_results' is set to `0`, this can cause performance problems")
    config_warnings = true
  end
  if not config_warnings then
    report_ok("**config:** no issues found")
  end
end

return M

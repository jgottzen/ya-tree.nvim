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

---@param level LogLevel
function M.set_log_level(level)
  log.config.level = level
end

---@param opts? YaTreeConfig
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

  lib().setup()
end

return M

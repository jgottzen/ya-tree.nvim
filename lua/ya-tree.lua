local log = require("ya-tree.log")

local M = {}

-- use indirection so the config can be required as is for live changes to it
---@module "ya-tree.lib"
local function lib()
  return require("ya-tree.lib")
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
  lib().open({ focus = true })
end

---@param file string
function M.find_file(file)
  lib().open({ file = file, focus = true })
end

---@param level LogLevel
function M.set_log_level(level)
  log.config.level = level
end

---@param to_console boolean
function M.set_lot_to_console(to_console)
  log.config.to_console = to_console
end

---@param to_file boolean
function M.set_lot_to_file(to_file)
  log.config.to_file = to_file
end

---@param opts? YaTreeConfig
function M.setup(opts)
  local config = require("ya-tree.config").setup(opts)

  log.config.level = config.log.level
  log.config.to_console = config.log.to_console
  log.config.to_file = config.log.to_file

  log.trace("using config=%s", config)

  require("ya-tree.actions").setup()
  require("ya-tree.git").setup()
  require("ya-tree.ui").setup()

  lib().setup(function()
    vim.cmd([[
      command! YaTreeOpen lua require('ya-tree').open()
      command! YaTreeClose lua require('ya-tree').close()
      command! YaTreeToggle lua require('ya-tree').toggle()
      command! YaTreeFocus lua require('ya-tree').focus()
      command! -nargs=? -complete=file YaTreeFindFile lua require('ya-tree').find_file('<args>')
    ]])
  end)
end

return M

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
  require("ya-tree.config").config.log.level = level
  log.config.level = level
end

---@param to_console boolean
function M.set_log_to_console(to_console)
  require("ya-tree.config").config.log.to_console = to_console
  log.config.to_console = to_console
end

---@param to_file boolean
function M.set_log_to_file(to_file)
  require("ya-tree.config").config.log.to_file = to_file
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

  lib().setup()

  vim.api.nvim_create_user_command("YaTreeOpen", function()
    M.open()
  end, { desc = "Opens the tree view" })
  vim.api.nvim_create_user_command("YaTreeClose", function()
    M.close()
  end, { desc = "Closes the tree view" })
  vim.api.nvim_create_user_command("YaTreeToggle", function()
    M.toggle()
  end, { desc = "Toggles the tree view" })
  vim.api.nvim_create_user_command("YaTreeFocus", function()
    M.focus()
  end, { desc = "Focuses the tree view, opens it if not open" })
  vim.api.nvim_create_user_command("YaTreeFindFile", function(input)
    M.find_file(input.args)
  end, { nargs = "?", complete = "file", desc = "Opens and focuses on the file of the current buffer, or the supplied file name" })
end

return M

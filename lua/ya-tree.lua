local log = require("ya-tree.log")

local api = vim.api

local M = {}

-- use indirection so the config can be required as is for live changes to it
---@module "ya-tree.lib"
local function lib()
  return require("ya-tree.lib")
end

---@param path? string
---@param switch_root? boolean
---@param focus? boolean
function M.open(path, switch_root, focus)
  lib().open_tree({ file = path, switch_root = switch_root, focus = focus })
end

function M.close()
  lib().close_tree()
end

function M.toggle()
  lib().toggle_tree()
end

function M.focus()
  lib().open_tree({ focus = true })
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

---@param arg_lead string
---@param cmdline string
---@return string[] completions
local function complete_open(arg_lead, cmdline)
  local splits = vim.split(cmdline, "%s+")
  local i = #splits
  if i == 2 then
    if vim.startswith(arg_lead, "path=") then
      return vim.fn.getcompletion(arg_lead:sub(6), "file")
    elseif vim.startswith(arg_lead, "focus=") then
      return { "true", "false" }
    else
      return { "path=./", "focus=" }
    end
  elseif i == 3 then
    if vim.startswith(splits[2], "path=") then
      return { "focus=true", "focus=false" }
    elseif vim.startswith(splits[2], "focus=") then
      return { "path=./" }
    end
  end
end

---@param fargs string[]
---@return string? path, boolean focus
local function parse_open_command_input(fargs)
  ---@type string
  local path = nil
  local focus = false
  for _, v in ipairs(fargs) do
    local pos = v:find("=")
    if pos then
      local kind = v:sub(1, pos - 1)
      local arg = v:sub(pos + 1)
      if kind == "focus" then
        focus = arg == "true"
      elseif kind == "path" then
        path = arg
      end
    end
  end

  return path, focus
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

  api.nvim_create_user_command("YaTreeOpen", function(input)
    local path, focus = parse_open_command_input(input.fargs)
    M.open(path, input.bang, focus)
  end, { bang = true, nargs = "*", complete = complete_open, desc = "Opens the tree view for the current `cwd`, or the supplied path" })
  api.nvim_create_user_command("YaTreeClose", function()
    M.close()
  end, { desc = "Closes the tree view" })
  api.nvim_create_user_command("YaTreeToggle", function()
    M.toggle()
  end, { desc = "Toggles the tree view" })
  api.nvim_create_user_command("YaTreeFocus", function()
    M.focus()
  end, { desc = "Focuses the tree view, opens it if not open" })
  api.nvim_create_user_command("YaTreeFindFile", function(input)
    if input.args == "" then
      local file = api.nvim_buf_get_name(0)
      input.args = require("ya-tree.utils").is_readable_file(file) and file or nil
    end
    M.open(input.args, input.bang, true)
  end, {
    bang = true,
    nargs = "?",
    complete = "file",
    desc = "Opens the tree and focuses on the file of the current buffer, or the supplied file name",
  })
end

return M

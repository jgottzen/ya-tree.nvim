local void = require("plenary.async").void

local log = require("ya-tree.log")

local api = vim.api
local fn = vim.fn

local M = {}

---@param path? string
---@param switch_root? boolean
---@param focus? boolean
---@param tree_type? YaTreeType|string
function M.open(path, switch_root, focus, tree_type)
  void(require("ya-tree.lib").open_window)({ path = path, switch_root = switch_root, focus = focus, tree_type = tree_type })
end

function M.close()
  void(require("ya-tree.lib").close_window)()
end

function M.toggle()
  void(require("ya-tree.lib").toggle_window)()
end

function M.focus()
  void(require("ya-tree.lib").open_window)({ focus = true })
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
  ---@type string[]
  local splits = vim.split(cmdline, "%s+")
  local i = #splits
  if i > 4 then
    return {}
  end

  local focus_completed = false
  local path_completed = false
  local tree_type_completed = false
  for index = 2, i do
    if vim.startswith(splits[index], "focus=") then
      focus_completed = true
    elseif vim.startswith(splits[index], "path=") then
      path_completed = true
    elseif vim.startswith(splits[index], "tree_type=") then
      tree_type_completed = true
    end
  end

  if not path_completed and vim.startswith(arg_lead, "path=") then
    return fn.getcompletion(arg_lead:sub(6), "file")
  elseif not focus_completed and vim.startswith(arg_lead, "focus=") then
    return { "true", "false" }
  elseif not tree_type_completed and vim.startswith(arg_lead, "tree_type=") then
    return { "files", "buffers", "git" }
  else
    local t = {}
    if not focus_completed then
      t[#t + 1] = "focus="
    end
    if not path_completed then
      t[#t + 1] = "path=./"
    end
    if not tree_type_completed then
      t[#t + 1] = "tree_type="
    end
    return t
  end
end

---@param fargs string[]
---@return string|nil path, boolean focus, string|nil tree_type
local function parse_open_command_input(fargs)
  ---@type string|nil
  local path = nil
  local focus = false
  ---@type string|nil
  local tree_type = nil
  for _, arg in ipairs(fargs) do
    if vim.startswith(arg, "path=") then
      path = arg:sub(6)
    elseif vim.startswith(arg, "focus=") then
      focus = arg:sub(7) == "true"
    elseif vim.startswith(arg, "tree_type=") then
      tree_type = arg:sub(11)
    end
  end

  return path, focus, tree_type
end

---@param opts? YaTreeConfig
function M.setup(opts)
  local config = require("ya-tree.config").setup(opts)

  log.config.level = config.log.level
  log.config.to_console = config.log.to_console
  log.config.to_file = config.log.to_file

  log.trace("using config=%s", config)

  require("ya-tree.trees").setup()
  require("ya-tree.actions").setup()
  require("ya-tree.git").setup()
  require("ya-tree.ui").setup()
  require("ya-tree.diagnostics").setup()
  require("ya-tree.lib").setup()

  api.nvim_create_user_command("YaTreeOpen", function(input)
    local path, focus, tree_type = parse_open_command_input(input.fargs)
    M.open(path, input.bang, focus, tree_type)
  end, { bang = true, nargs = "*", complete = complete_open, desc = "Open the tree view" })
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
    ---@type string?
    local file = input.args
    if not file or file == "" then
      file = api.nvim_buf_get_name(0) --[[@as string]]
      file = fn.filereadable(file) == 1 and file or nil
    end
    M.open(file, input.bang, true)
  end, { bang = true, nargs = "?", complete = "file", desc = "Focus on the current file, or the supplied file name" })
end

return M

local void = require("plenary.async").void

local log = require("ya-tree.log")("ya-tree")
local utils = require("ya-tree.utils")

local api = vim.api
local fn = vim.fn

local M = {}

---@class Yat.OpenWindowArgs
---@field path? string
---@field switch_root? boolean
---@field focus? boolean
---@field tree_type? Yat.Trees.Type
---@field position? Yat.Ui.Canvas.Position

---@param opts Yat.OpenWindowArgs
---  - {opts.path?} `string`
---  - {opts.switch_root?} `boolean`
---  - {opts.focus?} `boolean`
---  - {opts.tree_type?} `Yat.Trees.Type`
---  - {opts.position?} `Yat.Ui.Canvas.Position`
function M.open(opts)
  void(require("ya-tree.lib").open_window)(opts)
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

---@param level Yat.Logger.Level
function M.set_log_level(level)
  require("ya-tree.config").config.log.level = level
  log.config.level = level
end

---@param namespace string
function M.add_logged_namespace(namespace)
  if not vim.tbl_contains(require("ya-tree.config").config.log.namespaces, namespace) then
    require("ya-tree.config").config.log.namespaces[#require("ya-tree.config").config.log.namespaces + 1] = namespace
    log.config.namespaces = require("ya-tree.config").config.log.namespaces
  end
end

---@param namespace string
function M.remove_logged_namespace(namespace)
  utils.tbl_remove(require("ya-tree.config").config.log.namespaces, namespace)
  log.config.namespaces = require("ya-tree.config").config.log.namespaces
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
  local splits = vim.split(cmdline, "%s+") --[=[@as string[]]=]
  local i = #splits
  if i > 5 then
    return {}
  end

  local focus_completed = false
  local path_completed = false
  local tree_type_completed = false
  local position_completed = false
  for index = 2, i - 1 do
    local split = splits[index]
    if vim.startswith(split, "focus=") then
      focus_completed = true
    elseif vim.startswith(split, "path=") then
      path_completed = true
    elseif vim.startswith(split, "tree_type=") then
      tree_type_completed = true
    elseif vim.startswith(split, "position=") then
      position_completed = true
    end
  end

  if not path_completed and vim.startswith(arg_lead, "path=") then
    return fn.getcompletion(arg_lead:sub(6), "file")
  elseif not focus_completed and vim.startswith(arg_lead, "focus=") then
    return { "focus=true", "focus=false" }
  elseif not tree_type_completed and vim.startswith(arg_lead, "tree_type=") then
    return { "tree_type=files", "tree_type=buffers", "tree_type=git" }
  elseif not position_completed and vim.startswith(arg_lead, "position=") then
    return { "position=left", "position=right" }
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
    if not position_completed then
      t[#t + 1] = "position="
    end
    return t
  end
end

---@param fargs string[]
---@return string|nil path
---@return boolean focus
---@return string|nil tree_type
---@return Yat.Ui.Canvas.Position? position
local function parse_open_command_input(fargs)
  ---@type string|nil
  local path = nil
  local focus = false
  ---@type string|nil
  local tree_type = nil
  ---@type Yat.Ui.Canvas.Position?
  local position = nil
  for _, arg in ipairs(fargs) do
    if vim.startswith(arg, "path=") then
      path = arg:sub(6)
    elseif vim.startswith(arg, "focus=") then
      focus = arg:sub(7) == "true"
    elseif vim.startswith(arg, "tree_type=") then
      tree_type = arg:sub(11)
    elseif vim.startswith(arg, "position=") then
      position = arg:sub(10)
    end
  end

  return path, focus, tree_type, position
end

---@param opts? Yat.Config
function M.setup(opts)
  local config = require("ya-tree.config").setup(opts)

  log.config.level = config.log.level
  log.config.to_console = config.log.to_console
  log.config.to_file = config.log.to_file
  log.config.namespaces = config.log.namespaces

  log.trace("using config=%s", config)

  require("ya-tree.trees").setup(config)
  require("ya-tree.actions").setup(config)
  require("ya-tree.git").setup()
  require("ya-tree.ui").setup()
  require("ya-tree.diagnostics").setup()
  require("ya-tree.lib").setup()

  api.nvim_create_user_command("YaTreeOpen", function(input)
    local path, focus, tree_type, position = parse_open_command_input(input.fargs)
    M.open({ path = path, switch_root = input.bang, focus = focus, tree_type = tree_type, position = position })
  end, { bang = true, nargs = "*", complete = complete_open, desc = "Open the tree window" })
  api.nvim_create_user_command("YaTreeClose", M.close, { desc = "Closes the tree window" })
  api.nvim_create_user_command("YaTreeToggle", M.toggle, { desc = "Toggles the tree window" })
  api.nvim_create_user_command("YaTreeFocus", M.focus, { desc = "Focuses the tree window, opens it if not open" })
  api.nvim_create_user_command("YaTreeFindFile", function(input)
    local file = input.args --[[@as string?]]
    if not file or file == "" then
      file = api.nvim_buf_get_name(0) --[[@as string]]
      file = fn.filereadable(file) == 1 and file or nil
    end
    M.open({ path = file, switch_root = input.bang, focus = true })
  end, { bang = true, nargs = "?", complete = "file", desc = "Focus on the current file, or the supplied file name" })
end

return M

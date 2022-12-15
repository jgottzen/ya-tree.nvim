local void = require("plenary.async").void

local utils = require("ya-tree.utils")

local api = vim.api
local fn = vim.fn

local M = {}

-- needed for neodev

---@alias Callback fun()
---@alias Number number

---@class Yat.OpenWindowArgs
---@field path? string The path to open.
---@field focus? boolean Whether to focus the tree window.
---@field tree? Yat.Trees.Type Which type of tree to open, defaults to the current tree, or `"filesystem"` if no current tree exists.
---@field position? Yat.Ui.Position Where the tree window should be positioned.
---@field size? integer The size of the tree window, either width or height depending on position.
---@field tree_args? table<string, any> Any tree specific arguments.

---@param opts? Yat.OpenWindowArgs
---  - {opts.path?} `string` The path to open.
---  - {opts.focus?} `boolean` Whether to focus the tree window.
---  - {opts.tree?} `Yat.Trees.Type` Which type of tree to open, defaults to the current tree, or `"filesystem"` if no current tree exists.
---  - {opts.position?} `Yat.Ui.Position` Where the tree window should be positioned.
---  - {opts.size?} `integer` The size of the tree window, either width or height depending on position.
---  - {opts.tree_args?} `table<string, any>` Any tree specific arguments.
function M.open(opts)
  void(require("ya-tree.lib").open_window)(opts)
end

function M.close()
  void(require("ya-tree.lib").close_window)()
end

function M.toggle()
  void(require("ya-tree.lib").toggle_window)()
end

---@param level Yat.Logger.Level
function M.set_log_level(level)
  require("ya-tree.config").config.log.level = level
  require("ya-tree.log").set_level(level)
end

---@param namespace Yat.Logger.Namespace
function M.add_logged_namespace(namespace)
  local namespaces = require("ya-tree.config").config.log.namespaces
  if not vim.tbl_contains(namespaces, namespace) then
    namespaces[#namespaces + 1] = namespace
    require("ya-tree.log").set_logged_namespaces(namespaces)
  end
end

---@param namespace Yat.Logger.Namespace
function M.remove_logged_namespace(namespace)
  local namespaces = require("ya-tree.config").config.log.namespaces
  utils.tbl_remove(namespaces, namespace)
  require("ya-tree.log").set_logged_namespaces(namespaces)
end

---@param to_console boolean
function M.set_log_to_console(to_console)
  require("ya-tree.config").config.log.to_console = to_console
  require("ya-tree.log").set_log_to_console(to_console)
end

---@param to_file boolean
function M.set_log_to_file(to_file)
  require("ya-tree.config").config.log.to_file = to_file
  require("ya-tree.log").set_log_to_file(to_file)
end

---@param arg_lead string
---@param cmdline string
---@return string[] completions
local function complete_open(arg_lead, cmdline)
  local splits = vim.split(cmdline, "%s+", {}) --[=[@as string[]]=]
  local i = #splits
  if i > 6 then
    return {}
  end

  local focus_completed = false
  local path_completed = false
  local tree_completed = false
  local position_completed = false
  local size_completed = false
  for index = 2, i - 1 do
    local item = splits[index]
    if item == "focus" then
      focus_completed = true
    elseif vim.startswith(item, "path=") then
      path_completed = true
    elseif vim.startswith(item, "tree=") then
      tree_completed = true
    elseif vim.startswith(item, "position=") then
      position_completed = true
    elseif vim.startswith(item, "size=") then
      size_completed = true
    end
  end

  if not path_completed and vim.startswith(arg_lead, "path=") then
    return fn.getcompletion(arg_lead:sub(6), "file")
  elseif not tree_completed and vim.startswith(arg_lead, "tree=") then
    return vim.tbl_map(function(tree_type)
      return "tree=" .. tree_type
    end, require("ya-tree.trees").get_registered_tree_types())
  elseif not position_completed and vim.startswith(arg_lead, "position=") then
    return { "position=left", "position=right", "position=top", "position=bottom" }
  elseif not size_completed and vim.startswith(arg_lead, "size=") then
    return {}
  else
    local t = {}
    if not focus_completed then
      t[#t + 1] = "focus"
    end
    if not path_completed then
      t[#t + 1] = "path=."
    end
    if not tree_completed then
      t[#t + 1] = "tree"
    end
    if not position_completed then
      t[#t + 1] = "position"
    end
    if not size_completed then
      t[#t + 1] = "size"
    end
    return t
  end
end

---@param fargs string[]
---@return Yat.OpenWindowArgs
local function parse_open_command_input(fargs)
  ---@type string|nil
  local path = nil
  local focus = false
  ---@type string|nil
  local tree = nil
  ---@type Yat.Ui.Position?
  local position = nil
  ---@type integer?
  local size = nil
  local tree_args = {}
  for _, arg in ipairs(fargs) do
    if vim.startswith(arg, "path=") then
      path = arg:sub(6)
      if path == "%" then
        path = fn.expand(path)
        path = fn.filereadable(path) == 1 and path or nil
      end
    elseif arg == "focus" then
      focus = true
    elseif vim.startswith(arg, "tree=") then
      tree = arg:sub(6)
    elseif vim.startswith(arg, "position=") then
      position = arg:sub(10)
    elseif vim.startswith(arg, "size=") then
      size = tonumber(arg:sub(6))
    else
      local splits = vim.split(arg, "=", { plain = true })
      if #splits == 2 then
        tree_args[splits[1]] = splits[2]
      end
    end
  end
  if vim.tbl_count(tree_args) == 0 then
    tree_args = nil
  end

  return { path = path, focus = focus, tree = tree, position = position, size = size, tree_args = tree_args }
end

---@param opts? Yat.Config
function M.setup(opts)
  local config = require("ya-tree.config").setup(opts)

  local log = require("ya-tree.log")
  log.set_level(config.log.level)
  log.set_log_to_console(config.log.to_console)
  log.set_log_to_file(config.log.to_file)
  log.set_logged_namespaces(config.log.namespaces)

  require("ya-tree.debounce").setup()
  require("ya-tree.fs.watcher").setup(config)
  require("ya-tree.lsp").setup()
  require("ya-tree.ui").setup(config)
  require("ya-tree.actions").setup(config)
  require("ya-tree.trees").setup(config)
  require("ya-tree.sidebar").setup(config)
  require("ya-tree.git").setup()
  require("ya-tree.diagnostics").setup(config)
  require("ya-tree.lib").setup(config)

  api.nvim_create_user_command("YaTreeOpen", function(input)
    M.open(parse_open_command_input(input.fargs))
  end, { nargs = "*", complete = complete_open, desc = "Open the tree window" })
  api.nvim_create_user_command("YaTreeClose", M.close, { desc = "Close the tree window" })
  api.nvim_create_user_command("YaTreeToggle", M.toggle, { desc = "Toggle the tree window" })
end

return M

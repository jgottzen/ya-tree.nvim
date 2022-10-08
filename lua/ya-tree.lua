local void = require("plenary.async").void

local log = require("ya-tree.log")("ya-tree")
local utils = require("ya-tree.utils")

local api = vim.api
local fn = vim.fn

local M = {}

---@class Yat.OpenWindowArgs
---@field path? string The path to open.
---@field switch_root? boolean Change the root path of the tree to `path`.
---@field focus? boolean Whether to focus the tree window.
---@field tree? Yat.Trees.Type Which type of tree to open, defaults to the current tree, or `"filesystem"` if no current tree exists.
---@field position? Yat.Ui.Canvas.Position Where the tree window should be positioned.
---@field size? integer The size of the tree window, either width or height depending on position.

---@param opts Yat.OpenWindowArgs
---  - {opts.path?} `string` The path to open.
---  - {opts.switch_root?} `boolean` Change the root path of the tree to `path`.
---  - {opts.focus?} `boolean` Whether to focus the tree window.
---  - {opts.tree?} `Yat.Trees.Type` Which type of tree to open, defaults to the current tree, or `"filesystem"` if no current tree exists.
---  - {opts.position?} `Yat.Ui.Canvas.Position` Where the tree window should be positioned.
---  - {opts.size?} `integer` The size of the tree window, either width or height depending on position.
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
    local split = splits[index]
    if vim.startswith(split, "focus=") then
      focus_completed = true
    elseif vim.startswith(split, "path=") then
      path_completed = true
    elseif vim.startswith(split, "tree=") then
      tree_completed = true
    elseif vim.startswith(split, "position=") then
      position_completed = true
    elseif vim.startswith(split, "size=") then
      size_completed = true
    end
  end

  if not path_completed and vim.startswith(arg_lead, "path=") then
    return fn.getcompletion(arg_lead:sub(6), "file")
  elseif not focus_completed and vim.startswith(arg_lead, "focus=") then
    return { "focus=true", "focus=false" }
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
      t[#t + 1] = "focus="
    end
    if not path_completed then
      t[#t + 1] = "path=./"
    end
    if not tree_completed then
      t[#t + 1] = "tree="
    end
    if not position_completed then
      t[#t + 1] = "position="
    end
    if not size_completed then
      t[#t + 1] = "size="
    end
    return t
  end
end

---@param fargs string[]
---@return string|nil path
---@return boolean focus
---@return string|nil tree
---@return Yat.Ui.Canvas.Position? position
---@return integer|nil size
local function parse_open_command_input(fargs)
  ---@type string|nil
  local path = nil
  local focus = false
  ---@type string|nil
  local tree = nil
  ---@type Yat.Ui.Canvas.Position?
  local position = nil
  ---@type number?
  local size = nil
  for _, arg in ipairs(fargs) do
    if vim.startswith(arg, "path=") then
      path = arg:sub(6)
      if path == "%" then
        path = fn.expand(path)
        path = fn.filereadable(path) == 1 and path or nil
      end
    elseif vim.startswith(arg, "focus=") then
      focus = arg:sub(7) == "true"
    elseif vim.startswith(arg, "tree=") then
      tree = arg:sub(6)
    elseif vim.startswith(arg, "position=") then
      position = arg:sub(10)
    elseif vim.startswith(arg, "size=") then
      size = tonumber(arg:sub(6))
    end
  end

  return path, focus, tree, position, size
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
    local path, focus, tree, position, size = parse_open_command_input(input.fargs)
    M.open({ path = path, switch_root = input.bang, focus = focus, tree = tree, position = position, size = size })
  end, { bang = true, nargs = "*", complete = complete_open, desc = "Open the tree window" })
  api.nvim_create_user_command("YaTreeClose", M.close, { desc = "Close the tree window" })
  api.nvim_create_user_command("YaTreeToggle", M.toggle, { desc = "Toggle the tree window" })
end

return M

local utils = require("ya-tree.utils")
local void = require("ya-tree.async").void

local api = vim.api
local fn = vim.fn

local M = {}

-- needed for neodev

---@alias Callback fun()
---@alias Number number

---@class Yat.OpenWindowArgs
---@field path? string The path to expand to.
---@field focus? boolean|Yat.Panel.Type Whether to focus the sidebar, alternatively which panel to focus.

---@param opts? Yat.OpenWindowArgs
---  - {opts.path?} `string` The path to expand to.
---  - {opts.focus?} `boolean|Yat.Panel.Type` Whether to focus the sidebar, alternatively which panel to focus.
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
  for index = 2, i - 1 do
    local item = splits[index]
    if vim.startswith(item, "focus=") then
      focus_completed = true
    elseif vim.startswith(item, "path=") then
      path_completed = true
    end
  end

  if not focus_completed and vim.startswith(arg_lead, "focus") then
    local types = vim.tbl_map(function(panel_type)
      return "focus=" .. panel_type
    end, require("ya-tree.sidebar").get_available_panels())
    table.insert(types, 1, "focus=false")
    return types
  elseif not path_completed and vim.startswith(arg_lead, "path=") then
    return fn.getcompletion(arg_lead:sub(6), "file")
  else
    local t = {}
    if not focus_completed then
      t[#t + 1] = "focus"
    end
    if not path_completed then
      t[#t + 1] = "path=."
    end
    return t
  end
end

---@param fargs string[]
---@return Yat.OpenWindowArgs
local function parse_open_command_input(fargs)
  ---@type string|nil
  local path = nil
  ---@type boolean|Yat.Panel.Type|nil
  local focus = nil
  for _, arg in ipairs(fargs) do
    if vim.startswith(arg, "path=") then
      path = arg:sub(6)
      if path == "%" then
        path = fn.expand(path)
        path = fn.filereadable(path) == 1 and path or nil
      end
    elseif vim.startswith(arg, "focus") then
      if arg == "focus" then
        focus = true
      elseif arg == "focus=false" then
        focus = false
      else
        focus = arg:sub(7)
      end
    end
  end

  return { path = path, focus = focus }
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
  require("ya-tree.git").setup()
  require("ya-tree.diagnostics").setup(config)
  require("ya-tree.lsp").setup()
  require("ya-tree.ui").setup(config)
  require("ya-tree.actions").setup(config)
  require("ya-tree.panels").setup(config)
  require("ya-tree.sidebar").setup(config)
  require("ya-tree.lib").setup(config)

  api.nvim_create_user_command("YaTreeOpen", function(input)
    M.open(parse_open_command_input(input.fargs))
  end, { nargs = "*", complete = complete_open, desc = "Open the sidebar" })
  api.nvim_create_user_command("YaTreeClose", M.close, { desc = "Close the sidebar" })
  api.nvim_create_user_command("YaTreeToggle", M.toggle, { desc = "Toggle the sidebar" })
end

return M

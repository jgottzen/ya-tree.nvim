local lazy = require("ya-tree.lazy")

local async = lazy.require("ya-tree.async") ---@module "ya-tree.async"
local Config = lazy.require("ya-tree.config") ---@module "ya-tree.config"
local Logger = lazy.require("ya-tree.log") ---@module "ya-tree.log"
local Sidebar = lazy.require("ya-tree.sidebar") ---@module "ya-tree.sidebar"
local utils = lazy.require("ya-tree.utils") ---@module "ya-tree.utils"

local api = vim.api

local M = {
  ---@private
  _loading = false,
}

---@class Yat.OpenWindowArgs
---@field focus? boolean Whether to focus the sidebar.
---@field panel? Yat.Panel.Type A specific panel to open, and/or focus.
---@field panel_args? table<string, string>  Any panel specific arguments for `panel`.

---@async
---@param opts? Yat.OpenWindowArgs
---  - {opts.focus?} `boolean` Whether to focus the sidebar.
---  - {opts.panel?} `Yat.Panel.Type` The panel to open.
---  - {opts.panel_args}? `table<string, string>` The panel specific arguments.
local function open(opts)
  local log = Logger.get("ya-tree")
  if M._loading then
    local function open_window()
      open(opts)
    end
    log.info("deferring open")
    vim.defer_fn(async.void(open_window), 100)
    return
  end
  opts = opts or {}
  log.debug("opening sidebar with %s", opts)

  local sidebar = Sidebar.get_or_create_sidebar(api.nvim_get_current_tabpage())
  sidebar:open({ focus = opts.focus, panel = opts.panel, panel_args = opts.panel_args })
end

---@param opts? Yat.OpenWindowArgs
---  - {opts.focus?} `boolean` Whether to focus the sidebar.
---  - {opts.panel?} `Yat.Panel.Type` The panel to open.
---  - {opts.panel_args}? `table<string, string>` The panel specific arguments.
function M.open(opts)
  async.run(function()
    open(opts)
  end)
end

function M.close()
  async.run(function()
    local sidebar = Sidebar.get_sidebar(api.nvim_get_current_tabpage())
    if sidebar and sidebar:is_open() then
      sidebar:close()
    end
  end)
end

function M.toggle()
  async.run(function()
    local sidebar = Sidebar.get_sidebar(api.nvim_get_current_tabpage())
    if sidebar and sidebar:is_open() then
      sidebar:close()
    else
      open()
    end
  end)
end

---@param level Yat.Logger.Level
function M.set_log_level(level)
  Config.config.log.level = level
  Logger.set_level(level)
end

---@param namespace Yat.Logger.Namespace
function M.add_logged_namespace(namespace)
  local namespaces = Config.config.log.namespaces
  if not vim.tbl_contains(namespaces, namespace) then
    namespaces[#namespaces + 1] = namespace
    Logger.set_logged_namespaces(namespaces)
  end
end

---@param namespace Yat.Logger.Namespace
function M.remove_logged_namespace(namespace)
  local namespaces = Config.config.log.namespaces
  utils.tbl_remove(namespaces, namespace)
  Logger.set_logged_namespaces(namespaces)
end

---@param to_console boolean
function M.set_log_to_console(to_console)
  Config.config.log.to_console = to_console
  Logger.set_log_to_console(to_console)
end

---@param to_file boolean
function M.set_log_to_file(to_file)
  Config.config.log.to_file = to_file
  Logger.set_log_to_file(to_file)
end

---@param arg_lead string
---@param cmdline string
---@return string[] completions
local function complete_open_command(arg_lead, cmdline)
  local splits = vim.split(cmdline, "%s+")
  if splits[1] == "" then
    table.remove(splits, 1)
  end
  if #splits == 2 then
    local items = Sidebar.complete_command(arg_lead, nil, {})
    table.insert(items, 1, "no-focus")
    return vim.tbl_filter(function(item)
      return vim.startswith(item, arg_lead)
    end, items)
  end

  local panel_pos = splits[2] == "no-focus" and 3 or 2
  local panel_type = splits[panel_pos]
  local args = { unpack(splits, panel_pos + 1) }
  return Sidebar.complete_command(arg_lead, panel_type, args)
end

---@param fargs string[]
---@return Yat.OpenWindowArgs
local function parse_open_command_input(fargs)
  local focus = fargs[1] ~= "no-focus"
  local panel_pos = focus and 1 or 2
  local panel_type = fargs[panel_pos]
  local args = panel_pos < #fargs and { unpack(fargs, panel_pos + 1) } or nil
  local panel_args = Sidebar.parse_command_arguments(panel_type, args)
  ---@type Yat.OpenWindowArgs
  local open_args = { focus = focus, panel = panel_type, panel_args = panel_args }
  return open_args
end

---@param opts? Yat.Config
function M.setup(opts)
  local config = Config.setup(opts)

  Logger.set_level(config.log.level)
  Logger.set_log_to_console(config.log.to_console)
  Logger.set_log_to_file(config.log.to_file)
  Logger.set_logged_namespaces(config.log.namespaces)

  require("ya-tree.diagnostics").setup(config)
  require("ya-tree.ui").setup(config)
  require("ya-tree.actions").setup(config)
  Sidebar.setup(config)

  if config.hijack_netrw then
    vim.cmd([[silent! autocmd! FileExplorer *]])
    vim.cmd([[autocmd VimEnter * ++once silent! autocmd! FileExplorer *]])
  end

  local autocmd_will_open = config.hijack_netrw and utils.is_current_buffer_directory()
  if not autocmd_will_open and config.auto_open.on_setup then
    M._loading = true
    async.run(function()
      Sidebar.get_or_create_sidebar(api.nvim_get_current_tabpage())
      M._loading = false
      open({ focus = config.auto_open.focus_sidebar })
    end)
  end

  api.nvim_create_user_command("YaTreeOpen", function(input)
    M.open(parse_open_command_input(input.fargs))
  end, { nargs = "*", complete = complete_open_command, desc = "Open the sidebar" })
  api.nvim_create_user_command("YaTreeClose", M.close, { desc = "Close the sidebar" })
  api.nvim_create_user_command("YaTreeToggle", M.toggle, { desc = "Toggle the sidebar" })
end

return M

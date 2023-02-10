local run = require("ya-tree.async").run
local utils = require("ya-tree.utils")

local api = vim.api

local M = {
  ---@private
  _loading = false,
}

-- needed for neodev

---@alias Callback fun()
---@alias Number number

---@class Yat.OpenWindowArgs
---@field focus? boolean Whether to focus the sidebar.
---@field panel? Yat.Panel.Type The panel to open.
---@field panel_args? table<string, string> The panel specific arguments.

---@async
---@param opts? Yat.OpenWindowArgs
---  - {opts.focus?} `boolean` Whether to focus the sidebar.
---  - {opts.panel?} `Yat.Panel.Type` The panel to open.
---  - {opts.panel_args}? `table<string, string>` The panel specific arguments.
local function open(opts)
  local log = require("ya-tree.log").get("ya-tree")
  if M._loading then
    local function open_window()
      open(opts)
    end
    log.info("deferring open")
    vim.defer_fn(require("ya-tree.async").void(open_window), 100)
    return
  end
  opts = opts or {}
  log.debug("opening sidebar with %s", opts)

  local sidebar = require("ya-tree.sidebar").get_or_create_sidebar(api.nvim_get_current_tabpage())
  sidebar:open({ focus = opts.focus, panel = opts.panel, panel_args = opts.panel_args })
end

---@param opts? Yat.OpenWindowArgs
---  - {opts.focus?} `boolean` Whether to focus the sidebar.
---  - {opts.panel?} `Yat.Panel.Type` The panel to open.
---  - {opts.panel_args}? `table<string, string>` The panel specific arguments.
function M.open(opts)
  run(function()
    open(opts)
  end)
end

function M.close()
  run(function()
    local sidebar = require("ya-tree.sidebar").get_sidebar(api.nvim_get_current_tabpage())
    if sidebar and sidebar:is_open() then
      sidebar:close()
    end
  end)
end

function M.toggle()
  run(function()
    local sidebar = require("ya-tree.sidebar").get_sidebar(api.nvim_get_current_tabpage())
    if sidebar and sidebar:is_open() then
      sidebar:close()
    else
      open()
    end
  end)
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
local function complete_open_command(arg_lead, cmdline)
  local splits = vim.split(cmdline, "%s+")
  if splits[1] == "" then
    table.remove(splits, 1)
  end
  if #splits == 2 then
    local items = require("ya-tree.sidebar").complete_command(arg_lead, nil, {})
    table.insert(items, 1, "no-focus")
    return vim.tbl_filter(function(item)
      return vim.startswith(item, arg_lead)
    end, items)
  end

  local panel_pos = splits[2] == "no-focus" and 3 or 2
  local panel_type = splits[panel_pos]
  local args = { unpack(splits, panel_pos + 1) }
  return require("ya-tree.sidebar").complete_command(arg_lead, panel_type, args)
end

---@param fargs string[]
---@return Yat.OpenWindowArgs
local function parse_open_command_input(fargs)
  local focus = fargs[1] == "no-focus" and false or true
  local panel_pos = focus and 1 or 2
  local panel_type = fargs[panel_pos]
  local args = panel_pos < #fargs and { unpack(fargs, panel_pos + 1) } or nil
  local panel_args
  if panel_type and args then
    panel_args = require("ya-tree.sidebar").parse_command_arguments(panel_type, args)
  end
  return { focus = focus, panel = panel_type, panel_args = panel_args }
end

---@param opts? Yat.Config
function M.setup(opts)
  local config = require("ya-tree.config").setup(opts)

  local log = require("ya-tree.log")
  log.set_level(config.log.level)
  log.set_log_to_console(config.log.to_console)
  log.set_log_to_file(config.log.to_file)
  log.set_logged_namespaces(config.log.namespaces)

  require("ya-tree.diagnostics").setup(config)
  require("ya-tree.ui").setup(config)
  require("ya-tree.actions").setup(config)
  require("ya-tree.sidebar").setup(config)

  if config.hijack_netrw then
    vim.cmd([[silent! autocmd! FileExplorer *]])
    vim.cmd([[autocmd VimEnter * ++once silent! autocmd! FileExplorer *]])
  end

  local autocmd_will_open = utils.is_buffer_directory() and config.hijack_netrw
  if not autocmd_will_open and config.auto_open.on_setup then
    M._loading = true
    run(function()
      require("ya-tree.sidebar").get_or_create_sidebar(api.nvim_get_current_tabpage())
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

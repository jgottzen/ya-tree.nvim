local Path = require("ya-tree.path")
local run = require("ya-tree.async").run
local utils = require("ya-tree.utils")

local api = vim.api
local fn = vim.fn

local M = {
  ---@private
  _loading = false,
}

-- needed for neodev

---@alias Callback fun()
---@alias Number number

---@param path string
---@return string|nil path the fully resolved path, or `nil`
local function resolve_path(path)
  local p = Path:new(path)
  return p:exists() and p:absolute() or nil
end

---@class Yat.OpenWindowArgs
---@field path? string The path to expand to.
---@field focus? boolean|Yat.Panel.Type Whether to focus the sidebar, alternatively which panel to focus.

---@async
---@param opts? Yat.OpenWindowArgs
---  - {opts.path?} `string` The path to expand to.
---  - {opts.focus?} `boolean|Yat.Panel.Type` Whether to focus the sidebar, alternatively which panel to focus.
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

  local config = require("ya-tree.config").config
  local path
  if opts.path then
    path = resolve_path(opts.path)
  elseif config.follow_focused_file then
    local bufnr = api.nvim_get_current_buf()
    if api.nvim_buf_get_option(bufnr, "buftype") == "" then
      path = api.nvim_buf_get_name(bufnr)
    end
  end

  local sidebar = require("ya-tree.sidebar").get_or_create_sidebar(api.nvim_get_current_tabpage())
  sidebar:open({ focus = opts.focus })

  if path then
    local panel = sidebar:files_panel(opts.focus ~= false)
    if panel then
      local node = panel.root:expand({ to = path })
      local do_tcd = false
      if node then
        local hidden, reason = node:is_hidden(config)
        if hidden and reason then
          if reason == "filter" then
            config.filters.enable = false
          elseif reason == "git" then
            config.git.show_ignored = true
          end
        end
        log.info("navigating to %q", path)
      else
        log.info('cannot expand to path %q in the "files" panel, changing root', path)
        panel:change_root_node(path)
        node = panel.root:expand({ to = path })
        do_tcd = true
      end
      panel:draw(node)
      if do_tcd and config.cwd.update_from_panel then
        path = Path:new(path)
        path = path:is_dir() and path.filename or path:parent().filename
        log.debug("issueing tcd autocmd to %q", path)
        vim.cmd.tcd(fn.fnameescape(path))
      end
    else
      log.error("no files panel")
    end
  end
end

---@param opts? Yat.OpenWindowArgs
---  - {opts.path?} `string` The path to expand to.
---  - {opts.focus?} `boolean|Yat.Panel.Type` Whether to focus the sidebar, alternatively which panel to focus.
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

  require("ya-tree.diagnostics").setup(config)
  require("ya-tree.ui").setup(config)
  require("ya-tree.actions").setup(config)
  require("ya-tree.panels").setup(config)
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
  end, { nargs = "*", complete = complete_open, desc = "Open the sidebar" })
  api.nvim_create_user_command("YaTreeClose", M.close, { desc = "Close the sidebar" })
  api.nvim_create_user_command("YaTreeToggle", M.toggle, { desc = "Toggle the sidebar" })
end

return M

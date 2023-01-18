local log = require("ya-tree.log").get("lib")
local Path = require("ya-tree.path")
local Sidebar = require("ya-tree.sidebar")
local utils = require("ya-tree.utils")
local void = require("ya-tree.async").void

local api = vim.api
local fn = vim.fn

local M = {
  ---@private
  _loading = false,
}

---@param path string
---@return string|nil path the fully resolved path, or `nil`
local function resolve_path(path)
  local p = Path:new(path)
  return p:exists() and p:absolute() or nil
end

---@async
---@param opts? Yat.OpenWindowArgs
---  - {opts.path?} `string` The path to expand to.
---  - {opts.focus?} `boolean|Yat.Panel.Type` Whether to focus the sidebar, alternatively which panel to focus.
function M.open_window(opts)
  if M._loading then
    local function open_window()
      M.open_window(opts)
    end
    log.info("deferring open")
    vim.defer_fn(void(open_window), 100)
    return
  end
  opts = opts or {}
  log.debug("opening window with %s", opts)

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

  local sidebar = Sidebar.get_or_create_sidebar(api.nvim_get_current_tabpage())
  sidebar:open({ focus = opts.focus })

  if path then
    local panel = sidebar:files_panel(opts.focus ~= false)
    if panel then
      local node = panel.root:expand({ to = path })
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
        log.info("cannot expand to node %q in tree type %q", path, panel.TYPE)
        utils.warn(string.format("Path %q is not available in the %q tree", path, panel.TYPE))
      end
      panel:draw(node)
    else
      log.error("no files panel")
    end
  end
end

function M.close_window()
  local sidebar = Sidebar.get_sidebar(api.nvim_get_current_tabpage())
  if sidebar and sidebar:is_open() then
    sidebar:close()
  end
end

---@async
function M.toggle_window()
  local sidebar = Sidebar.get_sidebar(api.nvim_get_current_tabpage())
  if sidebar and sidebar:is_open() then
    sidebar:close()
  else
    M.open_window()
  end
end

---@async
---@param panel Yat.Panel.Tree
---@param new_root string
local function change_root(panel, new_root)
  local config = require("ya-tree.config").config
  if config.cwd.update_from_panel then
    vim.cmd.tcd(fn.fnameescape(new_root))
  else
    panel.sidebar:change_cwd(new_root)
  end
end

---@async
---@param panel Yat.Panel.Tree
---@param node Yat.Node
function M.cd_to(panel, node)
  if not node:is_directory() then
    if not node.parent then
      return
    end
    node = node.parent --[[@as Yat.Node]]
  end
  log.debug("cd to %q", node.path)
  change_root(panel, node.path)
end

---@async
---@param panel Yat.Panel.Tree
function M.cd_up(panel)
  local new_cwd = panel.root.parent and panel.root.parent.path or Path:new(panel.root.path):parent().filename
  log.debug("changing root directory one level up from %q to %q", panel.root.path, new_cwd)

  change_root(panel, new_cwd)
end

---@async
---@param panel Yat.Panel.Tree
function M.toggle_ignored(panel)
  local config = require("ya-tree.config").config
  config.git.show_ignored = not config.git.show_ignored
  log.debug("toggling git ignored to %s", config.git.show_ignored)
  panel.sidebar:draw()
end

---@async
---@param panel Yat.Panel.Tree
function M.toggle_filter(panel)
  local config = require("ya-tree.config").config
  config.filters.enable = not config.filters.enable
  log.debug("toggling filter to %s", config.filters.enable)
  panel.sidebar:draw()
end

---@param config Yat.Config
local function setup_netrw(config)
  if config.hijack_netrw then
    vim.cmd([[silent! autocmd! FileExplorer *]])
    vim.cmd([[autocmd VimEnter * ++once silent! autocmd! FileExplorer *]])
  end
end

---@param config Yat.Config
function M.setup(config)
  setup_netrw(config)

  local autocmd_will_open = utils.is_buffer_directory() and config.hijack_netrw
  if not autocmd_will_open and config.auto_open.on_setup then
    M._loading = true
    log.info("auto opening sidebar on setup")
    void(function()
      Sidebar.get_or_create_sidebar(api.nvim_get_current_tabpage())
      M._loading = false
      M.open_window({ focus = config.auto_open.focus_sidebar })
    end)()
  end
end

return M

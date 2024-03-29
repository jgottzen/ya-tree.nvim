local lazy = require("ya-tree.lazy")

local async = lazy.require("ya-tree.async") ---@module "ya-tree.async"
local Config = lazy.require("ya-tree.config") ---@module "ya-tree.config"
local fs = lazy.require("ya-tree.fs") ---@module "ya-tree.fs"
local git = lazy.require("ya-tree.git") ---@module "ya-tree.git"
local Logger = lazy.require("ya-tree.log") ---@module "ya-tree.log"
local meta = require("ya-tree.meta")
local Panels = lazy.require("ya-tree.panels") ---@module "ya-tree.panels"
local ui = lazy.require("ya-tree.ui") ---@module "ya-tree.ui"
local utils = lazy.require("ya-tree.utils") ---@module "ya-tree.utils"

local api = vim.api

local M = {
  ---@private
  ---@type table<integer, Yat.Sidebar>
  _sidebars = {},
}

---@class Yat.Sidebar.Layout.Panel
---@field panel Yat.Panel
---@field show boolean
---@field height? integer

---@class Yat.Sidebar.Layout
---@field panels Yat.Sidebar.Layout.Panel[]
---@field width integer

---@class Yat.Sidebar : Yat.Object
---@field new async fun(self: Yat.Sidebar, tabpage: integer): Yat.Sidebar
---
---@field private _tabpage integer
---@field private layout { left: Yat.Sidebar.Layout, right: Yat.Sidebar.Layout }
---@field private _edit_winid? integer
local Sidebar = meta.create_class("Yat.Sidebar")

function Sidebar.__tostring(self)
  ---@param panel_layout Yat.Sidebar.Layout
  local function panel_layout_tostring(panel_layout)
    return table.concat(
      ---@param panel Yat.Sidebar.Layout.Panel
      vim.tbl_map(function(panel)
        return panel.panel.TYPE
      end, panel_layout.panels),
      ", "
    )
  end

  return string.format(
    "<%s(tabpage=%s, left=[%s], right=[%s])>",
    self.class.name,
    self._tabpage,
    panel_layout_tostring(self.layout.left),
    panel_layout_tostring(self.layout.right)
  )
end

---@async
---@private
---@param tabpage integer
function Sidebar:init(tabpage)
  local config = Config.config
  self._tabpage = tabpage
  self.layout = {
    left = {
      panels = {},
      width = config.sidebar.layout.left.width,
    },
    right = {
      panels = {},
      width = config.sidebar.layout.right.width,
    },
  }
  for _, panel_layout in ipairs(config.sidebar.layout.left.panels) do
    local panel = Panels.create_panel(self, panel_layout.panel, config)
    if panel then
      self.layout.left.panels[#self.layout.left.panels + 1] = {
        panel = panel,
        show = panel_layout.show == nil or panel_layout.show == true,
        height = panel_layout.height and ui.normalize_height(panel_layout.height),
      }
    end
  end
  for _, panel_layout in ipairs(config.sidebar.layout.right.panels) do
    local panel = Panels.create_panel(self, panel_layout.panel, config)
    if panel then
      self.layout.right.panels[#self.layout.right.panels + 1] = {
        panel = panel,
        show = panel_layout.show == nil or panel_layout.show == true,
        height = panel_layout.height and ui.normalize_height(panel_layout.height),
      }
    end
  end

  async.scheduler()
  Logger.get("sidebar").info("created new sidebar %s", tostring(self))
end

function Sidebar:delete()
  Logger.get("sidebar").info("deleting sidebar %s", tostring(self))
  self:for_each_panel(function(panel)
    panel:delete()
  end)
end

---@return integer
function Sidebar:tabpage()
  return self._tabpage
end

---@param callback fun(panel: Yat.Panel)
function Sidebar:for_each_panel(callback)
  for _, panel_layout in ipairs(self.layout.left.panels) do
    callback(panel_layout.panel)
  end
  for _, panel_layout in ipairs(self.layout.right.panels) do
    callback(panel_layout.panel)
  end
end

---@param panel_layout Yat.Sidebar.Layout.Panel[]
---@return Yat.Panel?
local function first_open_panel(panel_layout)
  for _, layout in ipairs(panel_layout) do
    if layout.panel:is_open() then
      return layout.panel
    end
  end
end

---@alias Yat.Sidebar.Side "left"|"right"

---@param side? Yat.Sidebar.Side
---@return boolean
function Sidebar:is_open(side)
  if side == "left" then
    return first_open_panel(self.layout.left.panels) ~= nil
  elseif side == "right" then
    return first_open_panel(self.layout.right.panels) ~= nil
  else
    return first_open_panel(self.layout.left.panels) ~= nil or first_open_panel(self.layout.right.panels) ~= nil
  end
end

---@param opts? Yat.OpenWindowArgs
---  - {opts.focus?} `boolean` Whether to focus the sidebar.
---  - {opts.panel?} `Yat.Panel.Type` A specific panel to open.
---  - {opts.panel_args?} `table<string, string>` Any panel specific arguments for `opts.panel`.
function Sidebar:open(opts)
  Logger.get("sidebar").debug("sidebar opened with %s", opts)
  opts = opts or {}
  local edit_win = self:edit_win()
  self:open_side("right", opts.panel, opts.panel_args)
  self:open_side("left", opts.panel, opts.panel_args)

  if opts.focus == false then
    api.nvim_set_current_win(edit_win)
  else
    local panel = opts.panel and self:get_panel(opts.panel)
      or first_open_panel(self.layout.left.panels)
      or first_open_panel(self.layout.right.panels)
    if panel then
      panel:focus()
    end
  end
end

---@private
---@param side Yat.Sidebar.Side
---@param panel_type? Yat.Panel.Type
---@param panel_args? table<string, string>
function Sidebar:open_side(side, panel_type, panel_args)
  -- we need to focus the edit window so the split is done correctly,
  -- otherwise the sides will grow in width each time a side opened
  api.nvim_set_current_win(self:edit_win())

  local layout = side == "left" and self.layout.left or self.layout.right
  local side_was_open = false
  ---@type Yat.Sidebar.Side|"below"
  local direction = side
  for _, panel_layout in ipairs(layout.panels) do
    local panel = panel_layout.panel
    if panel:is_open() then
      panel:focus()
      side_was_open = true
      direction = "below"
      break
    end
  end

  for _, panel_layout in ipairs(layout.panels) do
    local panel = panel_layout.panel
    if panel:is_open() then
      -- focus the panel so the new panel is opened below it,
      -- this ensures that the panels are opened in the correct order,
      -- if the panel has been closed and is now opened again
      panel:focus()
      if panel_type == panel.TYPE and panel_args then
        panel:command_arguments(panel_args)
      end
    elseif panel_layout.show or panel.TYPE == panel_type then
      panel_layout.show = true
      panel:open(direction, direction ~= "below" and layout.width or nil)
      if panel.TYPE == panel_type and panel_args then
        panel:command_arguments(panel_args)
      end
      if direction ~= "below" then
        direction = "below"
      end
    end
  end

  if side_was_open then
    self:reorder_panels(side)
  end
  self:set_panel_heights(side)
end

---@private
---@param side Yat.Sidebar.Side
function Sidebar:reorder_panels(side)
  local log = Logger.get("sidebar")
  local layout = side == "left" and self.layout.left or self.layout.right
  local pos = 1
  if #layout.panels > 1 then
    for i = 1, #layout.panels - 1 do
      local panel_layout = layout.panels[i]
      local panel = panel_layout.panel
      if panel:is_open() then
        panel:focus()
        log.debug("setting panel %q to position %s", panel.TYPE, pos)
        vim.cmd.wincmd({ "x", count = pos, mods = { noautocmd = true } })
        pos = pos + 1
      end
    end
  end
end

---@private
---@param side Yat.Sidebar.Side
function Sidebar:set_panel_heights(side)
  local layout = side == "left" and self.layout.left or self.layout.right
  ---@param panel_layout Yat.Sidebar.Layout.Panel
  local open_panels = vim.tbl_filter(function(panel_layout)
    return panel_layout.panel:is_open()
  end, layout.panels) --[=[@as Yat.Sidebar.Layout.Panel[]]=]
  if #open_panels > 1 then
    for _, panel_layout in ipairs(open_panels) do
      local panel = panel_layout.panel
      if panel:is_open() and panel_layout.height then
        panel:set_height(panel_layout.height)
      end
    end
  end
end

function Sidebar:close()
  self:for_each_panel(function(panel)
    ---@diagnostic disable-next-line:invisible
    panel:close()
  end)
end

---@param panel_type Yat.Panel.Type
---@return Yat.Panel? panel
function Sidebar:get_panel(panel_type)
  for _, panel_layout in ipairs(self.layout.left.panels) do
    if panel_type == panel_layout.panel.TYPE then
      return panel_layout.panel
    end
  end
  for _, panel_layout in ipairs(self.layout.right.panels) do
    if panel_type == panel_layout.panel.TYPE then
      return panel_layout.panel
    end
  end
end

---@return Yat.Panel? panel
function Sidebar:current_panel()
  local winid = api.nvim_get_current_win()
  for _, panel_layout in ipairs(self.layout.left.panels) do
    if winid == panel_layout.panel:winid() then
      return panel_layout.panel
    end
  end
  for _, panel_layout in ipairs(self.layout.right.panels) do
    if winid == panel_layout.panel:winid() then
      return panel_layout.panel
    end
  end
end

---@async
---@param panel_type Yat.Panel.Type
---@param focus boolean
---@return Yat.Panel|nil panel
function Sidebar:open_panel(panel_type, focus)
  local side, panel_layout = self:get_side_and_layout_for_panel(panel_type)
  if side and panel_layout then
    self:open_side(side, panel_type)
    local panel = panel_layout.panel
    if not focus then
      api.nvim_set_current_win(self:edit_win())
    else
      panel:focus()
    end
    return panel
  end
end

---@private
---@param panel_type Yat.Panel.Type
---@return Yat.Sidebar.Side|nil side
---@return Yat.Sidebar.Layout.Panel|nil layout
function Sidebar:get_side_and_layout_for_panel(panel_type)
  for _, panel_layout in ipairs(self.layout.left.panels) do
    if panel_layout.panel.TYPE == panel_type then
      return "left", panel_layout
    end
  end
  for _, panel_layout in ipairs(self.layout.right.panels) do
    if panel_layout.panel.TYPE == panel_type then
      return "right", panel_layout
    end
  end
end

---@async
---@param focus boolean
---@return Yat.Panel.Files? panel
function Sidebar:files_panel(focus)
  return self:open_panel("files", focus) --[[@as Yat.Panel.Files?]]
end

---@async
---@param focus boolean
---@param path? string
---@return Yat.Panel.Symbols? panel
function Sidebar:symbols_panel(focus, path)
  local panel = self:open_panel("symbols", focus) --[[@as Yat.Panel.Symbols?]]
  if panel and path then
    panel:change_root_node(path)
  end
  return panel
end

---@async
---@param focus boolean
---@param direction? Yat.CallHierarchy.Direction
---@return Yat.Panel.CallHierarchy? panel
function Sidebar:call_hierarchy(focus, direction)
  local panel = self:open_panel("call_hierarchy", focus) --[[@as Yat.Panel.CallHierarchy?]]
  if panel and direction then
    panel:set_direction(direction)
  end
  return panel
end

---@async
---@param focus boolean
---@param repo? Yat.Git.Repo
---@return Yat.Panel.GitStatus? panel
function Sidebar:git_status_panel(focus, repo)
  local panel = self:open_panel("git_status", focus) --[[@as Yat.Panel.GitStatus?]]
  if panel and repo then
    panel:change_root_node(repo)
  end
  return panel
end

---@async
---@param focus boolean
---@return Yat.Panel.Buffers? panel
function Sidebar:buffers_panel(focus)
  return self:open_panel("buffers", focus) --[[@as Yat.Panel.Buffers?]]
end

---@param panel Yat.Panel
function Sidebar:close_panel(panel)
  local side, panel_layout = self:get_side_and_layout_for_panel(panel.TYPE)
  if side and panel_layout then
    panel_layout.show = false
    ---@diagnostic disable-next-line:invisible
    panel:close()
    self:set_panel_heights("left")
    self:set_panel_heights("right")
  end
end

function Sidebar:draw()
  local TreePanel = require("ya-tree.panels.tree_panel")
  self:for_each_panel(function(panel)
    if panel:is_open() then
      if panel:instance_of(TreePanel) then
        ---@cast panel Yat.Panel.Tree
        panel:draw(panel:get_current_node())
      else
        panel:draw()
      end
    end
  end)
end

---@param winid integer
---@return boolean
local function is_likely_edit_window(winid)
  if not api.nvim_win_is_valid(winid) then
    return false
  end
  local bufnr = api.nvim_win_get_buf(winid)
  return vim.bo[bufnr].buftype == ""
end

---@param tabpage integer
---@return integer winid
local function get_edit_win_candidate(tabpage)
  local log = Logger.get("sidebar")
  local winid = api.nvim_tabpage_get_win(tabpage)
  if not is_likely_edit_window(winid) then
    for _, win in ipairs(api.nvim_tabpage_list_wins(tabpage)) do
      if win ~= winid and is_likely_edit_window(win) then
        winid = win
        break
      end
    end
    log.warn("cannot find a window to use an edit window, using current window")
  else
    log.debug("current winid %s is a edit window", winid)
  end
  return winid
end

---@return integer edit_winid
function Sidebar:edit_win()
  if not self._edit_winid then
    self._edit_winid = get_edit_win_candidate(self._tabpage)
  end
  return self._edit_winid
end

---@param winid integer
function Sidebar:set_edit_winid(winid)
  self._edit_winid = winid
end

---@async
---@param new_cwd string
function Sidebar:change_cwd(new_cwd)
  self:for_each_panel(function(panel)
    panel:on_cwd_changed(new_cwd)
  end)
end

---@async
---@param path string
---@param repo Yat.Git.Repo
function Sidebar:set_git_repo_for_path(path, repo)
  M.for_each_sidebar_and_panel(function(panel)
    panel:set_git_repo_for_path(repo, path)
  end)
end

function Sidebar:remove_unused_git_repos()
  M.remove_unused_git_repos()
end

---@param tabpage integer
---@return Yat.Sidebar?
function M.get_sidebar(tabpage)
  return M._sidebars[tabpage]
end

---@async
---@param tabpage integer
---@return Yat.Sidebar sidebar
function M.get_or_create_sidebar(tabpage)
  local sidebar = M._sidebars[tabpage]
  if not sidebar then
    sidebar = Sidebar:new(tabpage)
    M._sidebars[tabpage] = sidebar
  end
  return sidebar
end

---@param callback fun(panel: Yat.Panel)
function M.for_each_sidebar_and_panel(callback)
  for _, sidebar in pairs(M._sidebars) do
    sidebar:for_each_panel(callback)
  end
end

function M.remove_unused_git_repos()
  ---@type table<string, boolean>
  local found_toplevels = {}
  for _, sidebar in pairs(M._sidebars) do
    sidebar:for_each_panel(function(panel)
      for _, repo in pairs(panel:get_git_repos() or {}) do
        found_toplevels[repo.toplevel] = true
      end
    end)
  end

  for toplevel, repo in pairs(git.repos) do
    if not found_toplevels[toplevel] then
      git.remove_repo(repo)
    end
  end
end

function M.delete_sidebars_for_nonexisting_tabpages()
  local log = Logger.get("sidebar")
  ---@type integer[]
  local tabpages = api.nvim_list_tabpages()
  for tabpage, sidebar in pairs(M._sidebars) do
    if not vim.tbl_contains(tabpages, tabpage) then
      log.info("deleting sidebar for tabpage %s", tabpage)
      M._sidebars[tabpage] = nil
      sidebar:delete()
    end
  end

  M.remove_unused_git_repos()
end

local WIN_AND_TAB_CLOSED_DEFER_TIME = 100

---@param bufnr integer
---@param winid integer
local function on_win_closed(bufnr, winid)
  -- the tabpage for the closed window
  local tabpage = api.nvim_win_get_tabpage(winid)
  local sidebar = M.get_sidebar(tabpage)
  if ui.is_window_floating(winid) or vim.bo[bufnr].filetype == "ya-tree-panel" or not (sidebar and sidebar:is_open()) then
    return
  end

  -- defer until the window in question - and any other temporary window - has closed, so that we can check only the remaining windows
  vim.defer_fn(function()
    -- if the tabpage no longer exists, then all windows in it have already closed, there is nothing to do
    if not api.nvim_tabpage_is_valid(tabpage) then
      return
    end
    -- the tabpage still exists and a sidebar is open in it
    local open_panels = 0
    sidebar:for_each_panel(function(panel)
      if panel:is_open() then
        open_panels = open_panels + 1
      end
    end)
    -- check that the only windows in the tabpage are the sidebar windows
    if #api.nvim_tabpage_list_wins(tabpage) == open_panels then
      -- check that there are no buffers with unsaved modifications,
      -- if so, just return
      for _, _bufnr in ipairs(api.nvim_list_bufs()) do
        if api.nvim_buf_is_loaded(_bufnr) and vim.bo[_bufnr].modified then
          return
        end
      end
      Logger.get("sidebar").info("sidebar is last window(s), closing")
      sidebar:close()
      -- all windows in the tabpage has closed, the TabClosed event fires here
    end
  end, WIN_AND_TAB_CLOSED_DEFER_TIME)
end

---@return boolean
local function can_switch_to_previous_buffer()
  local buffers = 0
  for _, bufnr in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_is_loaded(bufnr) and vim.bo[bufnr].buflisted then
      buffers = buffers + 1
      if buffers >= 2 then
        return true
      end
    end
  end
  return false
end

---@async
---@param bufnr integer
---@param file string
local function on_buf_enter(bufnr, file)
  local buftype = vim.bo[bufnr].buftype
  if buftype ~= "" or file == "" then
    return
  end
  local tabpage = api.nvim_get_current_tabpage()
  local current_winid = api.nvim_get_current_win()
  local sidebar = M.get_sidebar(tabpage)

  local log = Logger.get("sidebar")
  if Config.config.hijack_netrw and fs.is_directory(file) then
    log.debug("the opened buffer is a directory with path %q", file)

    if not sidebar then
      sidebar = M.get_or_create_sidebar(tabpage)
    end
    local panel = sidebar:current_panel()
    if panel and panel:winid() == current_winid then
      panel:restore()
    else
      -- make sure that when the dir buffer is closed, the window isn't closed as well
      if can_switch_to_previous_buffer() then
        log.info("switching to previous buffer")
        vim.cmd.bprevious()
      else
        log.info("creating replacement buffer")
        local buffer = api.nvim_create_buf(true, false)
        api.nvim_win_set_buf(current_winid, buffer)
      end
    end
    log.debug("deleting buffer %s with path %q", bufnr, file)
    api.nvim_buf_delete(bufnr, { force = true })

    if not sidebar:is_open() then
      sidebar:open()
    end
    panel = sidebar:files_panel(true)
    if panel then
      local node = panel.root:expand({ to = file })
      if not node then
        panel:change_root_node(file)
        if Config.config.cwd.update_from_panel then
          log.debug("issueing tcd autocmd to %q", file)
          vim.cmd.tcd(vim.fn.fnameescape(file))
        end
      else
        panel:draw(node)
      end
    end
  elseif sidebar and Config.config.move_buffers_from_sidebar_window then
    local panel = sidebar:current_panel()
    if panel and panel:winid() == current_winid then
      local edit_winid = sidebar:edit_win()
      log.debug("moving buffer %s from panel %s to window %s", bufnr, panel.TYPE, edit_winid)

      api.nvim_set_current_win(edit_winid)
      api.nvim_win_set_buf(edit_winid, bufnr)
      panel:restore()
    end
  end
end

local function on_tab_enter()
  local sidebar = M.get_sidebar(api.nvim_get_current_tabpage())
  if sidebar and sidebar:is_open() then
    sidebar:draw()
  end
end

---@async
---@param focus boolean
local function on_tab_new_enter(focus)
  local sidebar = M.get_or_create_sidebar(api.nvim_get_current_tabpage())
  sidebar:open({ focus = focus })
end

---@param bufnr integer
local function on_win_leave(bufnr)
  local winid = api.nvim_get_current_win()
  if ui.is_window_floating(winid) then
    return
  end
  local ok, buftype = pcall(function()
    return vim.bo[bufnr].buftype
  end)
  if not ok or buftype ~= "" then
    return
  end

  local sidebar = M.get_sidebar(api.nvim_get_current_tabpage())
  if sidebar then
    sidebar:set_edit_winid(winid)
  end
end

---@type Yat.Panel.Type[]
local available_panels = {}

function M.available_panels()
  return vim.deepcopy(available_panels)
end

---@param current string
---@param panel_type? Yat.Panel.Type
---@param args string[]
---@return string[] completions
function M.complete_command(current, panel_type, args)
  if not panel_type or panel_type == "" then
    return vim.tbl_filter(function(_panel_type)
      return vim.startswith(_panel_type, current)
    end, available_panels)
  else
    return Panels.complete_command(panel_type, current, args)
  end
end

---@param panel_type? Yat.Panel.Type
---@param args? string[]
---@return table<string, string>|nil panel_args
function M.parse_command_arguments(panel_type, args)
  if panel_type and args then
    return Panels.parse_command_arguments(panel_type, args)
  end
end

---@param config Yat.Config
function M.setup(config)
  ---@param layout Yat.Config.Sidebar.PanelLayout.Panel
  local left = vim.tbl_map(function(layout)
    return layout.panel
  end, config.sidebar.layout.left.panels) --[=[@as Yat.Panel.Type[]]=]
  ---@param layout Yat.Config.Sidebar.PanelLayout.Panel
  local right = vim.tbl_map(function(layout)
    return layout.panel
  end, config.sidebar.layout.right.panels) --[=[@as Yat.Panel.Type[]]=]
  vim.list_extend(left, right)

  available_panels = Panels.setup(config, utils.tbl_unique(left))

  local group = api.nvim_create_augroup("YaTreeSidebar", { clear = true })
  if config.close_if_last_window then
    api.nvim_create_autocmd("WinClosed", {
      group = group,
      callback = function(input)
        local winid = tonumber(input.match) --[[@as integer]]
        on_win_closed(input.buf, winid)
      end,
      desc = "Closing the sidebar if it is the last window in the tabpage",
    })
  end
  api.nvim_create_autocmd("BufEnter", {
    group = group,
    callback = async.void(function(input)
      on_buf_enter(input.buf, input.file)
    end),
    desc = "Handle buffers opened in a panel, and opening directory buffers",
  })
  api.nvim_create_autocmd("TabEnter", {
    group = group,
    callback = on_tab_enter,
    desc = "Redraw sidebar on tabpage switch",
  })
  if config.auto_open.on_new_tab then
    api.nvim_create_autocmd("TabNewEntered", {
      group = group,
      callback = async.void(function()
        on_tab_new_enter(config.auto_open.focus_sidebar)
      end),
      desc = "Open sidebar on new tab",
    })
  end
  api.nvim_create_autocmd("TabClosed", {
    group = group,
    callback = function()
      vim.defer_fn(M.delete_sidebars_for_nonexisting_tabpages, WIN_AND_TAB_CLOSED_DEFER_TIME)
    end,
    desc = "Clean up after closing tabpage",
  })
  api.nvim_create_autocmd("WinLeave", {
    group = group,
    callback = function(input)
      on_win_leave(input.buf)
    end,
    desc = "Save the last used window id",
  })
end

return M

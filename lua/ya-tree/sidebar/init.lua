local fs = require("ya-tree.fs")
local git = require("ya-tree.git")
local log = require("ya-tree.log").get("sidebar")
local meta = require("ya-tree.meta")
local Panels = require("ya-tree.panels")
local scheduler = require("ya-tree.async").scheduler
local ui = require("ya-tree.ui")
local utils = require("ya-tree.utils")
local void = require("ya-tree.async").void

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
---@overload async fun(tabpage: integer): Yat.Sidebar
---@field class fun(self: Yat.Sidebar): Yat.Class
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
    "<class %s(%s, left=[%s], right=[%s])>",
    self:class():name(),
    self._tabpage,
    panel_layout_tostring(self.layout.left),
    panel_layout_tostring(self.layout.right)
  )
end

---@async
---@private
---@param tabpage integer
function Sidebar:init(tabpage)
  local config = require("ya-tree.config").config
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
        show = (panel_layout.show == nil or panel_layout.show == true) and true or false,
        height = panel_layout.height and ui.normalize_height(panel_layout.height),
      }
    end
  end
  for _, panel_layout in ipairs(config.sidebar.layout.right.panels) do
    local panel = Panels.create_panel(self, panel_layout.panel, config)
    if panel then
      self.layout.right.panels[#self.layout.right.panels + 1] = {
        panel = panel,
        show = (panel_layout.show == nil or panel_layout.show == true) and true or false,
        height = panel_layout.height and ui.normalize_height(panel_layout.height),
      }
    end
  end

  scheduler()
  log.info("created new sidebar %s", tostring(self))
end

function Sidebar:delete()
  log.info("deleting sidebar %s", tostring(self))
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
---@return boolean
local function is_any_panel_open(panel_layout)
  for _, layout in ipairs(panel_layout) do
    if layout.panel:is_open() then
      return true
    end
  end
  return false
end

---@alias Yat.Sidebar.Side "left"|"right"

---@param side? Yat.Sidebar.Side
---@return boolean
function Sidebar:is_open(side)
  if side == "left" then
    return is_any_panel_open(self.layout.left.panels)
  elseif side == "right" then
    return is_any_panel_open(self.layout.right.panels)
  else
    return is_any_panel_open(self.layout.left.panels) or is_any_panel_open(self.layout.right.panels)
  end
end

---@class Yat.Sidebar.OpenArgs
---@field focus? boolean|Yat.Panel.Type

---@param opts? Yat.Sidebar.OpenArgs
function Sidebar:open(opts)
  log.debug("sidebar opened with %s", opts)
  opts = opts or {}
  local edit_win = self:edit_win()
  self:open_side("right")
  self:open_side("left")

  local focus = opts.focus
  if focus == false then
    api.nvim_set_current_win(edit_win)
  elseif type(focus) == "string" then
    local panel = self:get_panel(focus)
    if panel then
      panel:focus()
    end
  end
end

---@private
---@param side Yat.Sidebar.Side
function Sidebar:open_side(side)
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

  local first_panel
  for _, panel_layout in ipairs(layout.panels) do
    local panel = panel_layout.panel
    if panel:is_open() then
      -- focus the panel so the new panel is opened below it,
      -- this ensures that the panels are opened in the correct order,
      -- if the panel has been closed and is now opened again
      panel:focus()
      if not first_panel then
        first_panel = panel
      end
    elseif panel_layout.show then
      panel:open(direction, direction ~= "below" and layout.width or nil)
      if direction ~= "below" then
        direction = "below"
      end
      if not first_panel then
        first_panel = panel
      end
    end
  end

  if side_was_open then
    self:reorder_panels(side)
  end
  self:set_panel_heights(side)

  if first_panel then
    first_panel:focus()
  end
end

---@private
---@param side Yat.Sidebar.Side
function Sidebar:reorder_panels(side)
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
  if side then
    panel_layout.show = true
    self:open_side(side)
    local panel = self:get_panel(panel_type)
    if not focus then
      api.nvim_set_current_win(self:edit_win())
    elseif panel then
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
---@param path? string
---@param focus boolean
---@return Yat.Panel.Symbols? panel
function Sidebar:symbols_panel(path, focus)
  local panel = self:open_panel("symbols", focus) --[[@as Yat.Panel.Symbols?]]
  if panel and path then
    panel:change_root_node(path)
  end
  return panel
end

---@async
---@param repo Yat.Git.Repo
---@param focus boolean
---@return Yat.Panel.GitStatus? panel
function Sidebar:git_status_panel(repo, focus)
  local panel = self:open_panel("git_status", focus) --[[@as Yat.Panel.GitStatus?]]
  if panel then
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
  local _, panel_layout = self:get_side_and_layout_for_panel(panel.TYPE)
  if panel_layout then
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
  local name = api.nvim_buf_get_name(bufnr)
  if name == "" or name:find("YaTree://YaTree", 1, true) ~= nil then
    return false
  end
  return api.nvim_buf_get_option(bufnr, "buftype") == ""
end

---@param tabpage integer
---@return integer winid
local function get_edit_win_candidate(tabpage)
  local winid = api.nvim_tabpage_get_win(tabpage)
  if not is_likely_edit_window(winid) then
    for _, win in ipairs(api.nvim_tabpage_list_wins(tabpage)) do
      if win ~= winid and is_likely_edit_window(win) then
        winid = win
        break
      end
    end
    log.info("cannot find a window to use an edit window, using current window")
  else
    log.info("current winid %s is a edit window", winid)
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

---@param path string
---@param repo Yat.Git.Repo
function Sidebar:set_git_repo_for_path(path, repo)
  local TreePanel = require("ya-tree.panels.tree_panel")
  M.for_each_sidebar_and_panel(function(panel)
    if panel:instance_of(TreePanel) then
      ---@cast panel Yat.Panel.Tree
      panel:set_git_repo_for_path(repo, path)
    end
  end)
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
  for _, sidebar in ipairs(M._sidebars) do
    sidebar:for_each_panel(callback)
  end
end

function M.delete_sidebars_for_nonexisting_tabpages()
  local TreePanel = require("ya-tree.panels.tree_panel")
  ---@type table<string, boolean>, integer[]
  local found_toplevels, tabpages = {}, api.nvim_list_tabpages()

  for tabpage, sidebar in pairs(M._sidebars) do
    if not vim.tbl_contains(tabpages, tabpage) then
      M._sidebars[tabpage] = nil
      sidebar:delete()
    else
      sidebar:for_each_panel(function(panel)
        if panel:instance_of(TreePanel) then
          ---@cast panel Yat.Panel.Tree
          panel.root:walk(function(node)
            if node.repo then
              if not found_toplevels[node.repo.toplevel] then
                found_toplevels[node.repo.toplevel] = true
              end
              if not node.repo:is_yadm() then
                return true
              end
            end
          end)
        end
      end)
    end
  end

  for toplevel, repo in pairs(git.repos) do
    if not found_toplevels[toplevel] then
      git.remove_repo(repo)
    end
  end
end

---@param winid integer
local function on_win_closed(winid)
  local sidebar = M.get_sidebar(api.nvim_get_current_tabpage())
  if ui.is_window_floating(winid) or not (sidebar and sidebar:is_open()) then
    return
  end

  -- defer until the window in question has closed, so that we can check only the remaining windows
  vim.defer_fn(function()
    local open_panels = 0
    sidebar:for_each_panel(function(panel)
      if panel:is_open() then
        open_panels = open_panels + 1
      end
    end)
    if #api.nvim_tabpage_list_wins(0) == open_panels and vim.bo.filetype == "ya-tree-panel" then
      -- check that there are no buffers with unsaved modifications,
      -- if so, just return
      for _, bufnr in ipairs(api.nvim_list_bufs()) do
        if api.nvim_buf_is_loaded(bufnr) and api.nvim_buf_get_option(bufnr, "modified") then
          return
        end
      end
      sidebar:close()
      log.debug("is last window, closing it")
      vim.cmd("silent q!")
    end
  end, 100)
end

---@return boolean
local function can_switch_to_previous_buffer()
  local buffers = 0
  for _, bufnr in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_is_loaded(bufnr) and api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].buflisted then
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
  local buftype = api.nvim_buf_get_option(bufnr, "buftype")
  if buftype ~= "" or file == "" then
    return
  end
  local config = require("ya-tree.config").config
  local tabpage = api.nvim_get_current_tabpage()
  local current_winid = api.nvim_get_current_win()
  local sidebar = M.get_sidebar(tabpage)

  if config.hijack_netrw and fs.is_directory(file) then
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
      local do_tcd = false
      if not node then
        panel:change_root_node(file)
        do_tcd = true
      end
      panel:draw(node)
      if do_tcd and config.cwd.update_from_panel then
        log.debug("issueing tcd autocmd to %q", file)
        vim.cmd.tcd(vim.fn.fnameescape(file))
      end
    end
  elseif sidebar and config.move_buffers_from_sidebar_window then
    local panel = sidebar:current_panel()
    if panel and panel:winid() == current_winid then
      local edit_winid = sidebar:edit_win()
      log.debug("moving buffer %s from panel %s to window %s", bufnr, panel.TYPE, edit_winid)

      api.nvim_set_current_win(edit_winid)
      --- moving the buffer to the edit window retains the number/relativenumber/signcolumn settings
      -- from the tree window...
      -- save them and apply them after switching
      local number = vim.wo.number
      local relativenumber = vim.wo.relativenumber
      local signcolumn = vim.wo.signcolumn
      api.nvim_win_set_buf(edit_winid, bufnr)
      vim.wo.number = number
      vim.wo.relativenumber = relativenumber
      vim.wo.signcolumn = signcolumn
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
  if ui.is_window_floating() then
    return
  end
  local ok, buftype = pcall(api.nvim_buf_get_option, bufnr, "buftype")
  if not ok or buftype ~= "" then
    return
  end

  local sidebar = M.get_sidebar(api.nvim_get_current_tabpage())
  if sidebar then
    local winid = api.nvim_get_current_win()
    if is_likely_edit_window(winid) then
      sidebar:set_edit_winid(winid)
    end
  end
end

---@type Yat.Panel[]
local available_panels = {}

function M.get_available_panels()
  return available_panels
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
  vim.list_extend(left, right, 1, #right)
  available_panels = utils.tbl_unique(left)

  Panels.setup(config, available_panels)

  local group = api.nvim_create_augroup("YaTreeSidebar", { clear = true })
  if config.close_if_last_window then
    api.nvim_create_autocmd("WinClosed", {
      group = group,
      callback = function(input)
        local winid = tonumber(input.match) --[[@as integer]]
        on_win_closed(winid)
      end,
      desc = "Closing the sidebar if it is the last window in the tabpage",
    })
  end
  api.nvim_create_autocmd("BufEnter", {
    group = group,
    callback = void(function(input)
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
      callback = void(function()
        on_tab_new_enter(config.auto_open.focus_sidebar)
      end),
      desc = "Open sidebar on new tab",
    })
  end
  api.nvim_create_autocmd("TabClosed", {
    group = group,
    callback = M.delete_sidebars_for_nonexisting_tabpages,
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

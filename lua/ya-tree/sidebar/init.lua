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
---@field height? integer

---@class Yat.Sidebar.Layout
---@field panels Yat.Sidebar.Layout.Panel[]
---@field width integer
---@field auto_open boolean

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
      auto_open = config.sidebar.layout.left.auto_open,
    },
    right = {
      panels = {},
      width = config.sidebar.layout.right.width,
      auto_open = config.sidebar.layout.right.auto_open,
    },
  }
  for _, panel_layout in ipairs(config.sidebar.layout.left.panels) do
    local panel = Panels.create_panel(self, panel_layout.panel, config)
    if panel then
      self.layout.left.panels[#self.layout.left.panels + 1] = {
        panel = panel,
        height = panel_layout.height and ui.normalize_height(panel_layout.height),
      }
    end
  end
  for _, panel_layout in ipairs(config.sidebar.layout.right.panels) do
    local panel = Panels.create_panel(self, panel_layout.panel, config)
    if panel then
      self.layout.right.panels[#self.layout.right.panels + 1] = {
        panel = panel,
        height = panel_layout.height and ui.normalize_height(panel_layout.height),
      }
    end
  end

  scheduler()
  log.info("created new sidebar %s", tostring(self))
end

---@async
function Sidebar:delete()
  self:for_each_panel(function(panel)
    panel:delete()
  end)
end

---@return integer
function Sidebar:tabpage()
  return self._tabpage
end

---@async
---@param callback async fun(panel: Yat.Panel)
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

---@param side? Yat.Sidebar.Side|"both"
function Sidebar:is_open(side)
  if side == "left" then
    return is_any_panel_open(self.layout.left.panels)
  elseif side == "right" then
    return is_any_panel_open(self.layout.right.panels)
  elseif side == "both" then
    return is_any_panel_open(self.layout.left.panels) and is_any_panel_open(self.layout.right.panels)
  else
    return is_any_panel_open(self.layout.left.panels) or is_any_panel_open(self.layout.right.panels)
  end
end

---@class Yat.Sidebar.OpenArgs
---@field side? Yat.Sidebar.Side
---@field focus? boolean|Yat.Panel.Type

---@param opts? Yat.Sidebar.OpenArgs
function Sidebar:open(opts)
  log.debug("sidebar opened with %s", opts)
  opts = opts or {}
  local side = opts.side
  self:set_edit_win_candidate()
  local opened_right_side = false
  if side == "right" or side == "both" or self.layout.right.auto_open then
    self:open_side("right")
    opened_right_side = true
  end
  if side == "left" or side == "both" or self.layout.left.auto_open then
    if opened_right_side then
      -- we need to focus the edit window so the split is done correctly
      api.nvim_set_current_win(self:edit_win())
    end
    self:open_side("left")
  end
  local focus = opts.focus
  if focus == false then
    api.nvim_set_current_win(self:edit_win())
  elseif type(focus) == "string" then
    local panel = self:get_panel(focus)
    if panel then
      panel:focus()
    end
  end
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

---@private
function Sidebar:set_edit_win_candidate()
  local winid = api.nvim_get_current_win()
  if not is_likely_edit_window(winid) then
    for _, win in ipairs(api.nvim_list_wins()) do
      if win ~= winid and is_likely_edit_window(win) then
        winid = win
        break
      end
    end
    log.info("cannot find a window to use an edit window, using current window")
  else
    log.info("current winid %s is a edit window", winid)
  end
  self._edit_winid = winid
end

---@private
---@param side Yat.Sidebar.Side
function Sidebar:open_side(side)
  local layout = side == "left" and self.layout.left or self.layout.right
  for i, panel_layout in ipairs(layout.panels) do
    local panel = panel_layout.panel
    if not panel:is_open() then
      local direction = i == 1 and side or "below"
      panel:open(direction, (direction == "left" or direction == "right") and layout.width or panel_layout.height)
    end
  end

  self:set_panel_heights(side)
  local panel_layout = layout.panels[1]
  if panel_layout then
    local panel = panel_layout.panel
    panel:focus()
  end
end

---@private
---@param side Yat.Sidebar.Side
function Sidebar:set_panel_heights(side)
  local layout = side == "left" and self.layout.left or self.layout.right
  if #layout.panels > 1 then
    for i = #layout.panels, 1, -1 do
      local panel_layout = layout.panels[i]
      local panel = panel_layout.panel
      if panel:is_open() and panel_layout.height then
        panel:set_height(panel_layout.height)
      end
    end
  end
end

---@async
function Sidebar:close()
  self:for_each_panel(function(panel)
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
function Sidebar:get_current_panel()
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

function Sidebar:close_panel()
  local panel = self:get_current_panel()
  if panel then
    panel:close()
  end
end

---@param panel_type Yat.Panel.Type
---@param focus boolean
---@return Yat.Panel|nil panel
function Sidebar:open_panel(panel_type, focus)
  ---@param side Yat.Sidebar.Side
  ---@return Yat.Panel|nil panel
  local function open_panel_side(side)
    local layout = side == "left" and self.layout.left or self.layout.right
    local side_is_open = self:is_open(side)
    local reorder = true
    for _, panel_layout in pairs(layout.panels) do
      local panel = panel_layout.panel
      if panel:is_open() then
        -- focus the panel so the new panel is opened below it,
        -- this ensures that the panels are opened in the correct order
        panel:focus()
        reorder = false
      end
      if panel.TYPE == panel_type then
        if not panel:is_open() then
          local direction = side_is_open and "below" or side
          local size = side_is_open and panel_layout.height or layout.width
          panel:open(direction, size)
          self:set_panel_heights(side)
          if reorder then
            self:reorder_panels(side)
            panel:focus()
          end
        else
          panel:draw()
        end
        return panel
      end
    end
  end

  local panel = open_panel_side("left")
  if not panel then
    panel = open_panel_side("right")
  end
  if not focus and panel then
    api.nvim_set_current_win(self:edit_win())
  end
  return panel
end

---@private
---@param side Yat.Sidebar.Side
function Sidebar:reorder_panels(side)
  local layout = side == "left" and self.layout.left or self.layout.right
  local pos = 0
  for _, panel_layout in ipairs(layout.panels) do
    local panel = panel_layout.panel
    if panel:is_open() then
      pos = pos + 1
      panel:focus()
      log.debug("setting panel %q to position %s", panel.TYPE, pos)
      vim.cmd.wincmd({ "x", count = pos, { mods = { noautocmd = true } } })
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

---@async
function Sidebar:draw()
  local TreePanel = require("ya-tree.panels.tree_panel")
  self:for_each_panel(function(panel)
    if panel:is_open() then
      if panel:class():isa(TreePanel) then
        ---@cast panel Yat.Panel.Tree
        local node = panel:get_current_node()
        panel:draw(node)
      else
        panel:draw()
      end
    end
  end)
end

---@return integer edit_winid
function Sidebar:edit_win()
  if not self._edit_winid then
    self:set_edit_win_candidate()
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
  local TreePanel = require("ya-tree.panels.tree_panel")
  M.for_each_sidebar_and_panel(function(panel)
    if panel:class():isa(TreePanel) then
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

---@async
---@param callback fun(panel: Yat.Panel)
function M.for_each_sidebar_and_panel(callback)
  for _, sidebar in ipairs(M._sidebars) do
    sidebar:for_each_panel(callback)
  end
end

---@async
function M.delete_sidebars_for_nonexisting_tabpages()
  local TreePanel = require("ya-tree.panels.tree_panel")
  ---@type table<string, boolean>
  local found_toplevels = {}
  local tabpages = api.nvim_list_tabpages() --[=[@as integer[]]=]

  for tabpage, sidebar in pairs(M._sidebars) do
    if not vim.tbl_contains(tabpages, tabpage) then
      M._sidebars[tabpage] = nil
      sidebar:delete()
    else
      sidebar:for_each_panel(function(panel)
        if panel:class():isa(TreePanel) then
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

---@return integer[]
local function get_file_buffers()
  local buffers = {}
  for _, bufnr in ipairs(api.nvim_list_bufs()) do
    local buftype = api.nvim_buf_get_option(bufnr, "buftype")
    local bufname = api.nvim_buf_get_name(bufnr)
    if buftype == "" and bufname ~= "" and api.nvim_buf_is_loaded(bufnr) and api.nvim_buf_is_valid(bufnr) then
      buffers[#buffers + 1] = bufnr
    end
  end
  return buffers
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
    local panel = sidebar:get_current_panel()
    if panel and panel:winid() == current_winid then
      panel:restore()
    end
    -- switch back to the previous buffer so the window isn't closed
    if sidebar:is_open() or #get_file_buffers() > 1 then
      log.info("switching to previous buffer")
      vim.cmd.bprevious()
    else
      log.info("creating new buffer")
      local buf = vim.api.nvim_create_buf(true, false)
      api.nvim_win_set_buf(sidebar:edit_win(), buf)
    end
    sidebar:open()
    log.debug("deleting buffer %s with path %q", bufnr, file)
    api.nvim_buf_delete(bufnr, { force = true })

    panel = sidebar:open_panel("files", true) --[[@as Yat.Panel.Files]]
    local node = panel.root:expand({ to = file })
    panel:draw(node)
  elseif sidebar and config.move_buffers_from_sidebar_window then
    local panel = sidebar:get_current_panel()
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

---@async
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

  local group = api.nvim_create_augroup("YaTreeSidebar", { clear = true })
  if config.close_if_last_window then
    api.nvim_create_autocmd("WinClosed", {
      group = group,
      callback = function(input)
        local winid = tonumber(input.match) --[[@as integer]]
        on_win_closed(winid)
      end,
      desc = "Closing the sidebar if it is the last in the tabpage",
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
    callback = void(on_tab_enter),
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
    callback = void(M.delete_sidebars_for_nonexisting_tabpages),
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

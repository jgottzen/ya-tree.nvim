local lazy = require("ya-tree.lazy")

local events = lazy.require("ya-tree.events") ---@module "ya-tree.events"
local hl = lazy.require("ya-tree.ui.highlights") ---@module "ya-tree.ui.highlights"
local Logger = lazy.require("ya-tree.log") ---@module "ya-tree.log"
local meta = require("ya-tree.meta")

local api = vim.api
local fn = vim.fn

local BUF_OPTIONS = {
  bufhidden = "hide", -- must be hide and not wipe for Canvas:restore and particularly Canvas:move_buffer_to_edit_window to work
  buflisted = false,
  filetype = "ya-tree-panel",
  buftype = "nofile",
  modifiable = false,
  swapfile = false,
}

local WIN_OPTIONS = {
  number = false,
  relativenumber = false,
  list = false,
  winfixwidth = true,
  foldenable = false,
  spell = false,
  signcolumn = "no",
  foldmethod = "manual",
  foldcolumn = "0",
  cursorcolumn = false,
  cursorlineopt = "line",
  wrap = false,
  winhl = table.concat({
    "Normal:YaTreeNormal",
    "NormalNC:YaTreeNormalNC",
    "CursorLine:YaTreeCursorLine",
    "WinSeparator:YaTreeWinSeparator",
    "StatusLine:YaTreeStatusLine",
    "StatusLineNC:YaTreeStatuslineNC",
  }, ","),
}

---@abstract
---@class Yat.Panel : Yat.Object
---
---@field public TYPE Yat.Panel.Type
---@field public sidebar Yat.Sidebar
---@field protected tabpage integer
---@field protected refreshing boolean
---@field protected title string
---@field protected icon string
---@field protected keymap table<string, Yat.Action>
---@field private _winid? integer
---@field private _bufnr? integer
---@field protected window_augroup? integer
---@field private pos_after_win_leave? integer[]
---@field private registered_events { autocmd: table<Yat.Events.AutocmdEvent, string?>, git: table<Yat.Events.GitEvent, string?>, yatree: table<Yat.Events.YaTreeEvent, string?> }
local Panel = meta.create_class("Yat.Panel")

function Panel.__tostring(self)
  return string.format("<%s(TYPE=%s, winid=%s, bufnr=%s)>", self.class.name, self.TYPE, self._winid, self._bufnr)
end

---@protected
---@param _type Yat.Panel.Type
---@param sidebar Yat.Sidebar
---@param title string
---@param icon string
---@param keymap table<string, Yat.Action>
function Panel:init(_type, sidebar, title, icon, keymap)
  self.TYPE = _type
  self.sidebar = sidebar
  self.tabpage = sidebar:tabpage()
  self.refreshing = false
  self.title = title
  self.icon = icon
  self.keymap = keymap
  self.registered_events = { autocmd = {}, git = {}, yatree = {} }
end

function Panel:delete()
  Logger.get("panels").info("deleting panel %s", tostring(self))
  self:close()
  self:remove_all_autocmd_events()
  self:remove_all_git_events()
  self:remove_all_yatree_events()
  self.sidebar = nil
end

-- selene: allow(unused_variable)

---@async
---@abstract
---@param repo Yat.Git.Repo
---@param path string
---@diagnostic disable-next-line:unused-local
function Panel:set_git_repo_for_path(repo, path) end

---@abstract
---@return Yat.Git.Repo[]|nil
function Panel:get_git_repos() end

---@return integer? winid
function Panel:winid()
  return self._winid
end

---@return integer? bufnr
function Panel:bufnr()
  return self._bufnr
end

---@return integer? height, integer? width
function Panel:size()
  if self._winid then
    return api.nvim_win_get_height(self._winid), api.nvim_win_get_width(self._winid)
  end
end

---@return boolean is_open
function Panel:is_open()
  return self._winid ~= nil
end

---@alias Yat.Ui.Position "left"|"right"|"below"

---@param direction Yat.Ui.Position
---@param width? integer
function Panel:open(direction, width)
  if not self:is_open() then
    self:create_buffer()
    self:create_window(direction, width)
  end

  self:draw()
  if self.pos_after_win_leave then
    pcall(api.nvim_win_set_cursor, self._winid, self.pos_after_win_leave)
  end
  self:on_win_opened()
end

---@private
function Panel:create_buffer()
  self._bufnr = api.nvim_create_buf(false, false)
  Logger.get("panels").debug("created buffer %s", self._bufnr)
  api.nvim_buf_set_name(self._bufnr, "YaTree://YaTree" .. self._bufnr)

  for k, v in pairs(BUF_OPTIONS) do
    vim.bo[self._bufnr][k] = v
  end
  self:apply_mappings()
end

---@private
function Panel:apply_mappings()
  local log = Logger.get("panels")
  local opts = { buffer = self:bufnr(), silent = true, nowait = true }
  for key, action in pairs(self.keymap) do
    local rhs = self:create_keymap_function(action)
    if rhs then
      opts.desc = action.desc
      for _, mode in ipairs(action.modes) do
        if not pcall(vim.keymap.set, mode, key, rhs, opts) then
          log.error("couldn't construct mapping for key %q to action %q", key, action.name)
        end
      end
    end
  end
end

-- selene: allow(unused_variable)

---@abstract
---@protected
---@param action Yat.Action
---@return function|string handler
---@diagnostic disable-next-line:unused-local
function Panel:create_keymap_function(action)
  error("create_keymap_function must be implemented by subclasses")
end

do
  local POSITIONS_TO_WINCMD = { left = "H", right = "L" }

  ---@private
  ---@param position Yat.Ui.Position
  ---@param width? integer
  function Panel:create_window(position, width)
    local log = Logger.get("panels")
    if position == "left" or position == "right" then
      vim.cmd.vsplit({ mods = { noautocmd = true } })
      vim.cmd.wincmd({ POSITIONS_TO_WINCMD[position], mods = { noautocmd = true } })
    else
      vim.cmd.split({ mods = { noautocmd = true } })
    end
    self._winid = api.nvim_get_current_win()
    if width and (position == "left" or position == "right") then
      log.info("setting width for panel %q and winid %s to %q", self.TYPE, self._winid, width)
      api.nvim_win_set_width(self._winid, width)
    end
    log.debug("created window %s", self._winid)
    self:set_win_options()
  end
end

---@param winid integer
---@param bufnr integer
local function win_set_buf_noautocmd(winid, bufnr)
  local eventignore = vim.o.eventignore
  vim.o.eventignore = "all"
  api.nvim_win_set_buf(winid, bufnr)
  vim.o.eventignore = eventignore
end

---@private
function Panel:set_win_options()
  win_set_buf_noautocmd(self._winid, self._bufnr)

  for k, v in pairs(WIN_OPTIONS) do
    -- vim.wo is in fact 'window global', to properly set a window local option, i.e. 'setlocal winopt',
    -- nvim_set_option_value with 'local' scope has to be used.
    -- otherwise window options leak into other windows, especially if a buffer is moved from one window to another,
    -- i.e. when a file buffer is opened in the panels window and then moved to the 'edit window' by the sidebar.
    -- TODO: replace with double-indexing on vim.wo https://github.com/neovim/neovim/pull/20288 is merged
    api.nvim_set_option_value(k, v, { scope = "local", win = self._winid })
  end

  api.nvim_win_set_hl_ns(self._winid, hl.NS)

  self.window_augroup = api.nvim_create_augroup("YaTree_Window_" .. self._winid, { clear = true })
  api.nvim_create_autocmd("WinLeave", {
    group = self.window_augroup,
    buffer = self._bufnr,
    callback = function()
      self.pos_after_win_leave = api.nvim_win_get_cursor(self._winid)
    end,
    desc = "Storing window size",
  })
  api.nvim_create_autocmd("WinClosed", {
    group = self.window_augroup,
    pattern = tostring(self._winid),
    callback = function()
      self:_on_win_closed()
    end,
    desc = "Cleaning up window specific settings",
  })
end

---@private
function Panel:_on_win_closed()
  local log = Logger.get("panels")
  log.debug("window %s was closed", self._winid)

  local ok, result = pcall(api.nvim_del_augroup_by_id, self.window_augroup)
  if not ok then
    log.error("error deleting window local augroup: %s", result)
  end

  self.window_augroup = nil
  self._winid = nil
  if self._bufnr then
    -- Deleting the buffer will inhibit TabClosed autocmds from firing...
    -- Deferring it works
    local bufnr = self._bufnr
    vim.defer_fn(function()
      pcall(api.nvim_buf_delete, bufnr, { force = true })
    end, 100)
    self._bufnr = nil
  end
  self:on_win_closed()
end

---@protected
function Panel:on_win_opened() end

---@protected
function Panel:on_win_closed() end

function Panel:restore()
  if self._winid and self._bufnr then
    Logger.get("panels").info("restoring canvas buffer to buffer %s", self._bufnr)
    win_set_buf_noautocmd(self._winid, self._bufnr)
  end
end

function Panel:focus()
  if self._winid then
    api.nvim_set_current_win(self._winid)
  end
end

---@param row integer
function Panel:focus_row(row)
  -- avoids the cursor moving left when switching to the panel window and then back,
  -- happens with floating windows
  api.nvim_win_call(self._winid, function()
    local column = api.nvim_win_get_cursor(self._winid)[2]
    local ok = pcall(api.nvim_win_set_cursor, self._winid, { row, column })
    if ok then
      local win_height = api.nvim_win_get_height(self._winid)
      if win_height > row then
        pcall(vim.cmd.normal, { "zb", bang = true })
      elseif row < (win_height / 2) then
        pcall(vim.cmd.normal, { "zz", bang = true })
      end
    end
  end)
end

---@param height integer
function Panel:set_height(height)
  if self._winid then
    Logger.get("panels").debug("setting window height to %q for panel %q", height, self.TYPE)
    api.nvim_win_set_height(self._winid, height)
  end
end

---@protected
function Panel:close()
  if self._winid then
    local ok = pcall(api.nvim_win_close, self._winid, true)
    if not ok then
      -- this only happens if the panel is the last window,
      -- meaning that it's the current window and ok to force close
      Logger.get("panels").info("last window, force closing")
      vim.cmd.quit({ bang = true, mods = { silent = true } })
    end
  end
end

do
  local ESC_TERM_CODES = api.nvim_replace_termcodes("<ESC>", true, false, true)

  ---@return integer from, integer to
  function Panel:get_selected_rows()
    local mode = api.nvim_get_mode().mode
    if mode == "v" or mode == "V" then
      local from = fn.getpos("v")[2] --[[@as integer]]
      local to = api.nvim_win_get_cursor(self._winid)[1]
      if from > to then
        from, to = to, from
      end

      api.nvim_feedkeys(ESC_TERM_CODES, "n", false)
      return from, to
    else
      local row = api.nvim_win_get_cursor(self._winid)[1]
      return row, row
    end
  end
end

---@async
function Panel:refresh() end

-- selene: allow(unused_variable)

---@async
---@param args table<string, string>
---@diagnostic disable-next-line:unused-local
function Panel:command_arguments(args) end

---@return string line
---@return Yat.Ui.HighlightGroup[][] highlights
function Panel:render_header()
  return self.icon .. "  " .. self.title, { { name = hl.SECTION_ICON, from = 0, to = 3 }, { name = hl.SECTION_NAME, from = 3, to = -1 } }
end

-- selene: allow(unused_variable)

---@abstract
---@param ... any
---@diagnostic disable-next-line:unused-vararg
function Panel:draw(...)
  error("draw must be implemented by subclasses")
end

---@param lines string[]
---@param highlights Yat.Ui.HighlightGroup[][]
function Panel:set_content(lines, highlights)
  vim.bo[self._bufnr].modifiable = true
  api.nvim_buf_clear_namespace(self._bufnr, hl.NS, 0, -1)
  api.nvim_buf_set_lines(self._bufnr, 0, -1, false, lines)
  for linenr, line_highlights in ipairs(highlights) do
    for _, highlight in ipairs(line_highlights) do
      -- guard against bugged out renderer highlights, which will cause an avalanche of errors...
      if not highlight.name then
        Logger.get("panels").error("missing highlight name for line=%s, hl=%s", tostring(lines[linenr]), highlight)
      else
        api.nvim_buf_add_highlight(self._bufnr, hl.NS, highlight.name, linenr - 1, highlight.from, highlight.to)
      end
    end
  end
  vim.bo[self._bufnr].modifiable = false
end

do
  local counter = 0

  ---@param event integer
  ---@return string id
  function Panel:create_event_id(event)
    counter = counter + 1
    return string.format("YA_TREE_PANEL_%s%s_%s", self.TYPE, counter, events.get_event_name(event))
  end
end

---@protected
---@param event Yat.Events.AutocmdEvent
---@param callback async fun(bufnr: integer, file: string, match: string)
function Panel:register_autocmd_event(event, callback)
  if not self.registered_events.autocmd[event] then
    local id = self:create_event_id(event)
    self.registered_events.autocmd[event] = id
    events.on_autocmd_event(event, id, true, callback)
  end
end

---@protected
---@param event Yat.Events.AutocmdEvent
function Panel:remove_autocmd_event(event)
  local id = self.registered_events.autocmd[event]
  if id then
    self.registered_events.autocmd[event] = nil
    events.remove_autocmd_event(event, id)
  end
end

---@protected
function Panel:remove_all_autocmd_events()
  for event in pairs(self.registered_events.autocmd) do
    self:remove_autocmd_event(event)
  end
end

---@protected
---@param event Yat.Events.GitEvent
---@param callback Yat.Events.GitEvent.CallbackFn
function Panel:register_git_event(event, callback)
  if not self.registered_events.git[event] then
    local id = self:create_event_id(event)
    self.registered_events.git[event] = id
    events.on_git_event(event, id, callback)
  end
end

---@protected
---@param event Yat.Events.AutocmdEvent
function Panel:remove_git_event(event)
  local id = self.registered_events.git[event]
  if id then
    self.registered_events.git[event] = nil
    events.remove_git_event(event, id)
  end
end

---@protected
function Panel:remove_all_git_events()
  for event in pairs(self.registered_events.git) do
    self:remove_git_event(event)
  end
end

---@protected
---@param event Yat.Events.YaTreeEvent
---@param callback async fun(...)
function Panel:register_ya_tree_event(event, callback)
  if not self.registered_events.yatree[event] then
    local id = self:create_event_id(event)
    self.registered_events.yatree[event] = id
    events.on_yatree_event(event, id, true, callback)
  end
end

---@protected
---@param event Yat.Events.AutocmdEvent
function Panel:remove_yatree_event(event)
  local id = self.registered_events.autocmd[event]
  if id then
    self.registered_events.yatree[event] = nil
    events.remove_yatree_event(event, id)
  end
end

---@protected
function Panel:remove_all_yatree_events()
  for event in pairs(self.registered_events.yatree) do
    self:remove_yatree_event(event)
  end
end

-- selene: allow(unused_variable)

---@async
---@param new_cwd string
---@diagnostic disable-next-line:unused-local
function Panel:on_cwd_changed(new_cwd) end

return Panel

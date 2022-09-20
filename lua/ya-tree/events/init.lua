local void = require("plenary.async").void

local events = require("ya-tree.events.event")
local log = require("ya-tree.log")

local api = vim.api

---@class YaTreeEvent.AutoCmdEventHandler
---@field id string
---@field callback fun(bufnr: integer, file: string, match: string)

---@class YaTreeEvent.GitEventHandler
---@field id string
---@field callback async fun(repo: GitRepo, fs_changes: boolean)

---@class YaTreeEvent.YaTreeEventHandler
---@field id string
---@field callback fun(...)

local M = {}

local get_event_name, create_autocmd
do
  local mt = {
    __index = function(t, key)
      local val = {}
      rawset(t, key, val)
      return val
    end,
  }

  ---@private
  ---@type integer
  M._augroup = api.nvim_create_augroup("YaTree", { clear = true })
  ---@private
  ---@type { [integer]: string, [string]: integer }
  M._autocmd_ids_and_event_names = {}
  ---@private
  ---@type table<string, YaTreeEvent.AutoCmdEventHandler[]>
  M._autocmd_event_listeners = setmetatable({}, mt)
  ---@private
  ---@type table<string, YaTreeEvent.GitEventHandler[]>
  M._git_event_listeners = setmetatable({}, mt)
  ---@private
  ---@type table<string, YaTreeEvent.YaTreeEventHandler[]>
  M._yatree_event_listeners = setmetatable({}, mt)

  ---@type table<integer, string>
  local event_names = setmetatable({}, {
    __index = function(_, key)
      return "unknown_event_" .. key
    end,
  })
  for _, ns in pairs(events) do
    for name, event in pairs(ns) do
      event_names[event] = name
    end
  end

  ---@param event integer
  ---@return string
  get_event_name = function(event)
    return event_names[event]
  end
  M.get_event_name = get_event_name

  ---@type table<YaTreeEvents.AutocmdEvent, string|string[]>
  local event_to_autocmds = {
    [events.autocmd.TAB_NEW] = "TabNewEntered",
    [events.autocmd.TAB_ENTERED] = "TabEnter",
    [events.autocmd.TAB_CLOSED] = "TabClosed",

    [events.autocmd.BUFFER_NEW] = { "BufAdd", "BufFilePost", "TermOpen" },
    [events.autocmd.BUFFER_ENTERED] = "BufEnter",
    [events.autocmd.BUFFER_HIDDEN] = "BufHidden",
    [events.autocmd.BUFFER_DISPLAYED] = "BufWinEnter",
    [events.autocmd.BUFFER_DELETED] = { "BufDelete", "TermClose" },
    [events.autocmd.BUFFER_MODIFIED] = "BufModifiedSet",
    [events.autocmd.BUFFER_SAVED] = "BufWritePost",

    [events.autocmd.CWD_CHANGED] = "DirChanged",

    [events.autocmd.DIAGNOSTICS_CHANGED] = "DiagnosticChanged",

    [events.autocmd.WINDOW_LEAVE] = "WinLeave",
    [events.autocmd.WINDOW_CLOSED] = "WinClosed",

    [events.autocmd.COLORSCHEME] = "ColorScheme",

    [events.autocmd.LEAVE_PRE] = "VimLeavePre",
  }

  ---@class NvimAutocmdInput
  ---@field id integer
  ---@field event string
  ---@field buf integer
  ---@field match string
  ---@field file string

  ---@param input NvimAutocmdInput
  local function autocmd_callback(input)
    local event_name = M._autocmd_ids_and_event_names[input.id]
    local handlers = M._autocmd_event_listeners[event_name]
    if #handlers > 0 then
      if vim.v.exiting == nil then
        log.debug("calling handlers for autocmd %q", input.event)
      end
      for _, handler in ipairs(handlers) do
        handler.callback(input.buf, input.file, input.match)
      end
    end
  end

  ---@param event YaTreeEvents.AutocmdEvent
  ---@param event_name string
  create_autocmd = function(event, event_name)
    local autocmd = event_to_autocmds[event]
    local id = M._autocmd_ids_and_event_names[event_name]
    if id then
      log.warn("an autocmd source has already been defined for event %q with id %s, removing old definition", event_name, id)
      api.nvim_del_autocmd(id)
      M._autocmd_ids_and_event_names[id] = nil
      M._autocmd_ids_and_event_names[event_name] = nil
    end
    id = api.nvim_create_autocmd(autocmd, {
      group = M._augroup,
      pattern = "*",
      callback = autocmd_callback,
      desc = event_name,
    }) --[[@as integer]]
    M._autocmd_ids_and_event_names[id] = event_name
    M._autocmd_ids_and_event_names[event_name] = id
    log.debug('created "%s" autocmd handler for event %q as id %s', autocmd, event_name, id)
  end
end

---@param event_name string
---@param listeners { id: string, callback: fun(...) }[]
---@param id string
---@param callback fun(...)
local function add_listener(event_name, listeners, id, callback)
  for index, handler in ipairs(listeners) do
    if handler.id == id then
      log.warn("event %q already has a handler with id %q registered, removing old handler from list", event_name, id)
      table.remove(listeners, index)
    end
  end
  listeners[#listeners + 1] = { id = id, callback = callback }
  log.debug("added handler %q for event %q", id, event_name)
end

---@param event YaTreeEvents.AutocmdEvent
---@param id string
---@param async boolean
---@param callback fun(bufnr: integer, file: string, match: string)
---@overload fun(event: YaTreeEvents.AutocmdEvent, id: string, callback: fun(bufnr: integer, file: string, match: string))
function M.on_autocmd_event(event, id, async, callback)
  if type(async) == "function" then
    callback = async
    async = false
  end
  local event_name = get_event_name(event)
  if not M._autocmd_ids_and_event_names[event_name] then
    create_autocmd(event, event_name)
  end
  add_listener(event_name, M._autocmd_event_listeners[event_name], id, async and void(callback) or callback)
end

---@param event_name string
---@param listeners { id: string, handler: fun(...) }[]
---@param id string
local function remove_listener(event_name, listeners, id)
  for index, handler in ipairs(listeners) do
    if handler.id == id then
      log.debug("removing event handler %q for event %q", id, event_name)
      table.remove(listeners, index)
    end
  end
end

---@param event YaTreeEvents.AutocmdEvent
---@param id string
function M.remove_autocmd_event(event, id)
  local event_name = get_event_name(event)
  remove_listener(event_name, M._autocmd_event_listeners[event_name], id)
end

---@param event YaTreeEvents.GitEvent
---@param id string
---@param callback async fun(repo: GitRepo, fs_changes: boolean)
function M.on_git_event(event, id, callback)
  local event_name = get_event_name(event)
  add_listener(event_name, M._git_event_listeners[event_name], id, callback)
end

---@param event YaTreeEvents.GitEvent
---@param id string
function M.remove_git_event(event, id)
  local event_name = get_event_name(event)
  remove_listener(event_name, M._git_event_listeners[event_name], id)
end

---@async
---@param event YaTreeEvents.GitEvent
---@param repo GitRepo
---@param fs_changes boolean
function M.fire_git_event(event, repo, fs_changes)
  local event_name = get_event_name(event)
  if vim.v.exiting == nil then
    log.debug("calling handlers for event %q", event_name)
  end
  for _, handler in pairs(M._git_event_listeners[event_name]) do
    handler.callback(repo, fs_changes)
  end
end

---@param event YaTreeEvents.YaTreeEvent
---@param id string
---@param callback fun(...)
function M.on_yatree_event(event, id, callback)
  local event_name = get_event_name(event)
  add_listener(event_name, M._yatree_event_listeners[event_name], id, callback)
end

---@param event YaTreeEvents.YaTreeEvent
---@param id string
function M.remove_yatree_event(event, id)
  local event_name = get_event_name(event)
  remove_listener(event_name, M._yatree_event_listeners[event_name], id)
end

---@param event YaTreeEvents.YaTreeEvent
---@param ... any
function M.fire_yatree_event(event, ...)
  local event_name = get_event_name(event)
  if vim.v.exiting == nil then
    log.debug("calling handlers for event %q", event_name)
  end
  for _, handler in pairs(M._yatree_event_listeners[event_name]) do
    handler.callback(...)
  end
end

return M
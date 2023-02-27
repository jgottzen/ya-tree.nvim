local events = require("ya-tree.events.event")
local log = require("ya-tree.log").get("events")
local void = require("ya-tree.async").void

local api = vim.api

---@alias Yat.Events.AutocmdEvent.CallbackFn fun(bufnr: integer, file: string, match: string)

---@class Yat.Events.Handler.AutoCmd
---@field id string
---@field callback Yat.Events.AutocmdEvent.CallbackFn

---@alias Yat.Events.GitEvent.CallbackFn async fun(repo: Yat.Git.Repo, fs_changes: boolean)

---@class Yat.Events.Handler.Git
---@field id string
---@field callback Yat.Events.GitEvent.CallbackFn

---@alias Yat.Events.YaTreeEvent.CallbackFn fun(...)

---@class Yat.Events.Handler.YaTree
---@field id string
---@field callback Yat.Events.YaTreeEvent.CallbackFn

local M = {}

---@type table<integer, string>
local EVENT_NAMES = setmetatable({}, {
  __index = function(_, key)
    return "unknown_event_" .. key
  end,
})
local create_autocmd
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
  ---@type table<string, Yat.Events.Handler.AutoCmd[]>
  M._autocmd_event_listeners = setmetatable({}, mt)
  ---@private
  ---@type table<string, Yat.Events.Handler.Git[]>
  M._git_event_listeners = setmetatable({}, mt)
  ---@private
  ---@type table<string, Yat.Events.Handler.YaTree[]>
  M._yatree_event_listeners = setmetatable({}, mt)

  for _, ns in pairs(events) do
    for name, event in pairs(ns) do
      EVENT_NAMES[event] = name
    end
  end

  ---@param event integer
  ---@return string
  M.get_event_name = function(event)
    return EVENT_NAMES[event]
  end

  ---@type table<Yat.Events.AutocmdEvent, string|string[]>
  local EVENT_TO_AUTOCMDS = {
    [events.autocmd.BUFFER_NEW] = { "BufAdd", "TermOpen" },
    [events.autocmd.BUFFER_HIDDEN] = "BufHidden",
    [events.autocmd.BUFFER_DISPLAYED] = "BufWinEnter",
    [events.autocmd.BUFFER_DELETED] = { "BufDelete", "TermClose" },
    [events.autocmd.BUFFER_MODIFIED] = "BufModifiedSet",
    [events.autocmd.BUFFER_SAVED] = "BufWritePost",
    [events.autocmd.BUFFER_ENTER] = "BufEnter",

    [events.autocmd.COLORSCHEME] = "ColorScheme",

    [events.autocmd.LEAVE_PRE] = "VimLeavePre",

    [events.autocmd.DIR_CHANGED] = "DirChanged",

    [events.autocmd.LSP_ATTACH] = "LspAttach",
  }

  ---@class Nvim.AutocmdArgs
  ---@field id integer
  ---@field event string
  ---@field buf integer
  ---@field match string
  ---@field file string

  ---@param input Nvim.AutocmdArgs
  local function autocmd_callback(input)
    local event_name = M._autocmd_ids_and_event_names[input.id]
    local handlers = M._autocmd_event_listeners[event_name]
    if #handlers > 0 then
      if vim.v.exiting == vim.NIL then
        log.trace("calling handlers for autocmd %q", input.event)
      end
      for _, handler in ipairs(handlers) do
        handler.callback(input.buf, input.file, input.match)
      end
    end
  end

  ---@param event Yat.Events.AutocmdEvent
  ---@param event_name string
  local function _create_autcmd(event, event_name)
    local autocmd = EVENT_TO_AUTOCMDS[event]
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
    })
    M._autocmd_ids_and_event_names[id] = event_name
    M._autocmd_ids_and_event_names[event_name] = id
    log.debug('created "%s" autocmd handler for event %q as id %s', autocmd, event_name, id)
  end

  ---@param event Yat.Events.AutocmdEvent
  ---@param event_name string
  create_autocmd = function(event, event_name)
    if vim.in_fast_event() then
      vim.schedule_wrap(_create_autcmd)(event, event_name)
    else
      _create_autcmd(event, event_name)
    end
  end
end

---@param event_name string
---@param listeners { id: string, callback: fun(...) }[]
---@param id string
---@param callback fun(...)
local function add_listener(event_name, listeners, id, callback)
  for i = #listeners, 1, -1 do
    if listeners[i].id == id then
      log.warn("event %q already has a handler with id %q registered, removing old handler from list", event_name, id)
      table.remove(listeners, i)
    end
  end
  listeners[#listeners + 1] = { id = id, callback = callback }
  log.debug("added handler %q for event %q", id, event_name)
end

---@param event Yat.Events.AutocmdEvent
---@param id string
---@param async boolean
---@param callback Yat.Events.AutocmdEvent.CallbackFn
---@overload fun(event: Yat.Events.AutocmdEvent, id: string, callback: Yat.Events.AutocmdEvent.CallbackFn)
function M.on_autocmd_event(event, id, async, callback)
  if type(async) == "function" then
    callback = async
    async = false
  end
  local event_name = EVENT_NAMES[event]
  if not M._autocmd_ids_and_event_names[event_name] then
    create_autocmd(event, event_name)
  end
  add_listener(event_name, M._autocmd_event_listeners[event_name], id, async and void(callback) or callback)
end

---@param event_name string
---@param listeners { id: string, handler: fun(...) }[]
---@param id string
local function remove_listener(event_name, listeners, id)
  for i = #listeners, 1, -1 do
    if listeners[i].id == id then
      log.debug("removing event handler %q for event %q", id, event_name)
      table.remove(listeners, i)
    end
  end
  if #listeners == 0 then
    local autocmd_id = M._autocmd_ids_and_event_names[event_name]
    if autocmd_id then
      api.nvim_del_autocmd(autocmd_id)
      M._autocmd_ids_and_event_names[event_name] = nil
      M._autocmd_ids_and_event_names[autocmd_id] = nil
      log.debug("removed autocmd for %q", event_name)
    end
  end
end

---@param event Yat.Events.AutocmdEvent
---@param id string
function M.remove_autocmd_event(event, id)
  local event_name = EVENT_NAMES[event]
  remove_listener(event_name, M._autocmd_event_listeners[event_name], id)
end

---@param event Yat.Events.GitEvent
---@param id string
---@param callback Yat.Events.GitEvent.CallbackFn
function M.on_git_event(event, id, callback)
  local event_name = EVENT_NAMES[event]
  add_listener(event_name, M._git_event_listeners[event_name], id, callback)
end

---@param event Yat.Events.GitEvent
---@param id string
function M.remove_git_event(event, id)
  local event_name = EVENT_NAMES[event]
  remove_listener(event_name, M._git_event_listeners[event_name], id)
end

---@async
---@param event Yat.Events.GitEvent
---@param repo Yat.Git.Repo
---@param fs_changes boolean
function M.fire_git_event(event, repo, fs_changes)
  local event_name = EVENT_NAMES[event]
  if vim.v.exiting == vim.NIL then
    log.trace("calling handlers for event %q", event_name)
  end
  for _, handler in pairs(M._git_event_listeners[event_name]) do
    handler.callback(repo, fs_changes)
  end
end

---@param event Yat.Events.YaTreeEvent
---@param id string
---@param async boolean
---@param callback Yat.Events.YaTreeEvent.CallbackFn
---@overload fun(event: Yat.Events.YaTreeEvent, id: string, callback: Yat.Events.YaTreeEvent.CallbackFn)
function M.on_yatree_event(event, id, async, callback)
  if type(async) == "function" then
    callback = async
    async = false
  end
  local event_name = EVENT_NAMES[event]
  add_listener(event_name, M._yatree_event_listeners[event_name], id, async and void(callback) or callback)
end

---@param event Yat.Events.YaTreeEvent
---@param id string
function M.remove_yatree_event(event, id)
  local event_name = EVENT_NAMES[event]
  remove_listener(event_name, M._yatree_event_listeners[event_name], id)
end

---@param event Yat.Events.YaTreeEvent
---@param ... any
function M.fire_yatree_event(event, ...)
  local event_name = EVENT_NAMES[event]
  if vim.v.exiting == vim.NIL then
    log.debug("calling handlers for event %q", event_name)
  end
  for _, handler in pairs(M._yatree_event_listeners[event_name]) do
    handler.callback(...)
  end
end

return M

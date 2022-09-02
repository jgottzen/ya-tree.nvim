local void = require("plenary.async").void

local event = require("ya-tree.events.event")
local log = require("ya-tree.log")

local api = vim.api

---@class YaTreeEvent.AutoCmdEventHandler
---@field id string
---@field handler fun(bufnr: integer, file: string, match: string)

---@class YaTreeEvent.GitEventHandler
---@field id string
---@field handler async fun(repo: GitRepo, fs_changes: boolean)

local M = {
  ---@private
  ---@type integer
  _augroup = api.nvim_create_augroup("YaTree", { clear = true }),
  ---@private
  ---@type table<string, YaTreeEvent.AutoCmdEventHandler[]>
  _autocmd_event_listeners = {},
  ---@private
  ---@type YaTreeEvent.GitEventHandler[]
  _git_event_listeners = {},
  ---@private
  ---@type table<integer, string>
  _autocmd_ids_to_event = {},
}

---@param event_id YaTreeEvent
---@return string name
local function event_id_to_event_name(event_id)
  return event[event_id] --[[@as string]]
end

---@param event_id YaTreeEvent
---@param id string
---@param async boolean
---@param callback fun(bufnr: integer, file: string, match: string)
function M.on_autocmd_event(event_id, id, async, callback)
  local event_name = event_id_to_event_name(event_id)
  if not event_name then
    log.error("no event of id %s and type %q exists", event_id, event_name)
    return
  end

  local handlers = M._autocmd_event_listeners[event_name]
  if not handlers then
    handlers = {}
    M._autocmd_event_listeners[event_name] = handlers
  end
  for k, v in ipairs(handlers) do
    if v.id == id then
      log.warn("event %q already has a handler with id %q registered, removing old handler from list", event_name, id)
      table.remove(handlers, k)
    end
  end
  handlers[#handlers + 1] = { id = id, handler = async and void(callback) or callback }
  log.debug("added handler %q for event %q", id, event_name)
end

---@param id string
---@param callback async fun(repo: GitRepo, fs_changes: boolean)
function M.on_git_event(id, callback)
  local event_name = event_id_to_event_name(event.GIT)
  if not event_name then
    log.error("no event of id %s and type %q exists", event.GIT, event_name)
    return
  end

  for k, v in ipairs(M._git_event_listeners) do
    if v.id == id then
      log.warn("event %q already has a handler with id %q registered, removing old handler from list", event_name, id)
      table.remove(M._git_event_listeners, k)
    end
  end
  M._git_event_listeners[#M._git_event_listeners + 1] = { id = id, handler = callback }
  log.debug("added handler %q for event %q", id, event_name)
end

---@param event_id YaTreeEvent
---@param id string
function M.remove_event_handler(event_id, id)
  local event_name = event_id_to_event_name(event_id)
  if not event_name then
    log.error("no event of id %s and type %q exists", event_id, event_name)
    return
  end

  local handlers = event_id == event.GIT and M._git_event_listeners or M._autocmd_event_listeners[event_name]
  if handlers then
    for index, handler in ipairs(handlers) do
      if handler.id == id then
        log.debug("removing event handler %q for event %q", id, event_name)
        table.remove(handlers, index)
      end
    end
  end
end

---@async
---@param repo GitRepo
---@param fs_changes boolean
function M.fire_git_event(repo, fs_changes)
  local event_name = event_id_to_event_name(event.GIT)
  if vim.v.exiting == nil then
    log.debug("calling handlers for event %q", event_name)
  end
  for _, handler in ipairs(M._git_event_listeners) do
    handler.handler(repo, fs_changes)
  end
end

---@class NvimAutocmdInput
---@field id integer
---@field event string
---@field buf integer
---@field match string
---@field file string

---@param input NvimAutocmdInput
local function autocmd_callback(input)
  local event_name = M._autocmd_ids_to_event[input.id]
  local handlers = M._autocmd_event_listeners[event_name]
  if handlers then
    if vim.v.exiting == nil then
      log.debug("calling handlers for autocmd %q", input.event)
    end
    for _, handler in ipairs(handlers) do
      handler.handler(input.buf, input.file, input.match)
    end
  end
end

---@param event_id YaTreeEvent
---@param autocmd string|string[]
function M.define_autocmd_event_source(event_id, autocmd)
  local event_name = event_id_to_event_name(event_id)
  for k, v in pairs(M._autocmd_ids_to_event) do
    if v == event_name then
      log.warn("an autocmd source has already been defined for event %q with id %s, removing old definition", event_name, k)
      api.nvim_del_autocmd(k)
      M._autocmd_ids_to_event[k] = nil
    end
  end
  local id = api.nvim_create_autocmd(autocmd, {
    group = M._augroup,
    pattern = "*",
    callback = autocmd_callback,
    desc = event_name,
  })
  M._autocmd_ids_to_event[id] = event_name
  log.debug('created "%s" autocmd handler for event %q as id %s', autocmd, event_name, id)
end

do
  M.define_autocmd_event_source(event.TAB_NEW, "TabNewEntered")
  M.define_autocmd_event_source(event.TAB_ENTERED, "TabEnter")
  M.define_autocmd_event_source(event.TAB_CLOSED, "TabClosed")

  M.define_autocmd_event_source(event.BUFFER_NEW, { "BufAdd", "BufFilePost", "TermOpen" })
  M.define_autocmd_event_source(event.BUFFER_ENTERED, "BufEnter")
  M.define_autocmd_event_source(event.BUFFER_HIDDEN, "BufHidden")
  M.define_autocmd_event_source(event.BUFFER_DISPLAYED, "BufWinEnter")
  M.define_autocmd_event_source(event.BUFFER_DELETED, { "BufDelete", "TermClose" })
  M.define_autocmd_event_source(event.BUFFER_MODIFIED, "BufModifiedSet")
  M.define_autocmd_event_source(event.BUFFER_SAVED, "BufWritePost")

  M.define_autocmd_event_source(event.CWD_CHANGED, "DirChanged")

  M.define_autocmd_event_source(event.DIAGNOSTICS_CHANGED, "DiagnosticChanged")

  M.define_autocmd_event_source(event.WINDOW_LEAVE, "WinLeave")
  M.define_autocmd_event_source(event.WINDOW_CLOSED, "WinClosed")

  M.define_autocmd_event_source(event.COLORSCHEME, "ColorScheme")

  M.define_autocmd_event_source(event.LEAVE_PRE, "VimLeavePre")
end

return M

local accumulate = require("ya-tree.debounce").accumulate_trailing
local event = require("ya-tree.events.event")
local events = require("ya-tree.events")
local log = require("ya-tree.log").get("fs")
local utils = require("ya-tree.utils")

local M = {
  ---@private
  ---@type table<string, Yat.Fs.Watcher>
  _watchers = {},
  ---@private
  ---@type {[1]: string, [2]: string}[]
  _exclude_patterns = {},
}

---@class Luv.Fs.Event
---@field start fun(self: Luv.Fs.Event, path: string, flags: { watch_entry?: boolean, stat?: boolean, recursive?: boolean }, callback: fun(err?: string, filename: string, events: { change: boolean, rename: boolean})): 0|nil
---@field stop fun(self: Luv.Fs.Event): 0|nil
---@field getpath fun(self: Luv.Fs.Event): string|nil
---@field close fun(self: Luv.Fs.Event)
---@field is_active fun(self: Luv.Fs.Event): boolean?
---@field is_closing fun(self: Luv.Fs.Event): boolean?

---@class Yat.Fs.Watcher
---@field handle Luv.Fs.Event
---@field number_of_watchers integer

---@param dir string
---@return boolean
local function is_ignored(dir)
  for _, patterns in ipairs(M._exclude_patterns) do
    if vim.endswith(dir, patterns[1]) or dir:find(patterns[2], 1, true) then
      return true
    end
  end
  return false
end

---@param dir string
function M.watch_dir(dir)
  local config = require("ya-tree.config").config
  if not config.dir_watcher.enable or is_ignored(dir) then
    return
  end

  local watcher = M._watchers[dir]
  if not watcher then
    ---@param args { err: string|nil, filename: string }[]
    local handler = accumulate(function(args)
      local filenames = {}
      for _, val in ipairs(args) do
        if val.err then
          log.error("error from fs_event: %s", val.err)
        elseif val.filename then
          filenames[#filenames + 1] = val.filename
        end
      end
      if #filenames > 0 then
        filenames = utils.tbl_unique(filenames)
        table.sort(filenames)
        events.fire_yatree_event(event.ya_tree.FS_CHANGED, dir, filenames)
      end
    end, function(err, filename)
      return { err = err, filename = filename }
    end, 200)

    watcher = {
      handle = vim.loop.new_fs_event() --[[@as Luv.Fs.Event]],
      number_of_watchers = 1,
    }
    log.debug("starting fs_event on %q", dir)
    watcher.handle:start(dir, { watch_entry = false, stat = false, recursive = false }, handler)
  else
    watcher.number_of_watchers = watcher.number_of_watchers + 1
    log.debug("increasing fs_event watchers on %q by 1 to %s", dir, watcher.number_of_watchers)
  end
  M._watchers[dir] = watcher
end

---@param path string
function M.remove_watcher(path)
  local watcher = M._watchers[path]
  if watcher then
    watcher.number_of_watchers = watcher.number_of_watchers - 1
    if watcher.number_of_watchers == 0 then
      log.debug("no more watchers on %q, stopping fs_event", path)
      local err, message = watcher.handle:stop()
      if err ~= 0 then
        log.error("error stopping the fs_event watcher on %q: %s", path, message)
      end
      watcher.handle:close()
      watcher.handle = nil
      M._watchers[path] = nil
    else
      log.debug("decreasing number of fs_event watchers on %q by 1 to %s", path, watcher.number_of_watchers)
    end
  end
end

function M.stop_all()
  for _, watcher in pairs(M._watchers) do
    watcher.handle:stop()
    watcher.handle:close()
    watcher.handle = nil
  end
  M._watchers = {}
end

---@param config Yat.Config
function M.setup(config)
  M._exclude_patterns = { { utils.os_sep .. ".git", utils.os_sep .. ".git" .. utils.os_sep } }
  for _, ignored in ipairs(config.dir_watcher.exclude) do
    M._exclude_patterns[#M._exclude_patterns + 1] = { utils.os_sep .. ignored, utils.os_sep .. ignored .. utils.os_sep }
  end
  events.on_autocmd_event(event.autocmd.LEAVE_PRE, "YA_TREE_WATCHER_CLEANUP", M.stop_all)
end

return M

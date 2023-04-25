local lazy = require("ya-tree.lazy")

local Config = lazy.require("ya-tree.config") ---@module "ya-tree.config"
local debounce = lazy.require("ya-tree.debounce") ---@module "ya-tree.debounce"
local event = lazy.require("ya-tree.events.event") ---@module "ya-tree.events.event"
local events = lazy.require("ya-tree.events") ---@module "ya-tree.events"
local Logger = lazy.require("ya-tree.log") ---@module "ya-tree.log"
local utils = lazy.require("ya-tree.utils") ---@module "ya-tree.utils"

local M = {
  ---@private
  ---@type table<string, {handle: uv_fs_event_t, number_of_watchers: integer}?>
  _watchers = {},
  ---@private
  ---@type {[1]: string, [2]: string}[]
  _exclude_patterns = {},
}

local setup_done = false

---@param config Yat.Config
local function setup(config)
  M._exclude_patterns = { { utils.os_sep .. ".git", utils.os_sep .. ".git" .. utils.os_sep } }
  for _, ignored in ipairs(config.dir_watcher.exclude) do
    M._exclude_patterns[#M._exclude_patterns + 1] = { utils.os_sep .. ignored, utils.os_sep .. ignored .. utils.os_sep }
  end
  events.on_autocmd_event(event.autocmd.LEAVE_PRE, "YA_TREE_WATCHER_CLEANUP", M.stop_all)
  setup_done = true
end

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
  if not Config.config.dir_watcher.enable or is_ignored(dir) then
    return
  end
  if not setup_done then
    setup(Config.config)
  end

  local log = Logger.get("fs")
  local watcher = M._watchers[dir]
  if not watcher then
    ---@param args { err: string|nil, filename: string }[]
    local handler = debounce.accumulate_trailing(function(args)
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
      handle = vim.loop.new_fs_event(),
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
    local log = Logger.get("fs")
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

return M

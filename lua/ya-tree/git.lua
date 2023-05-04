local lazy = require("ya-tree.lazy")

local async = lazy.require("ya-tree.async") ---@module "ya-tree.async"
local Config = lazy.require("ya-tree.config") ---@module "ya-tree.config"
local event = require("ya-tree.events.event")
local events = require("ya-tree.events")
local fs = lazy.require("ya-tree.fs") ---@module "ya-tree.fs"
local job = lazy.require("ya-tree.job") ---@module "ya-tree.job"
local Logger = lazy.require("ya-tree.log") ---@module "ya-tree.log"
local meta = require("ya-tree.meta")
local Path = lazy.require("ya-tree.path") ---@module "ya-tree.path"
local utils = lazy.require("ya-tree.utils") ---@module "ya-tree.utils"

local uv = vim.loop

local M = {
  ---@private
  ---@type table<string, Yat.Git.Repo>
  repos = {},
}

---@async
---@param args string[]
---@param null_terminated? boolean
---@param cmd? string
---@return string[], string?
local function command(args, null_terminated, cmd)
  cmd = cmd or "git"
  args = cmd == "git" and { "--no-pager", unpack(args) } or args

  local _, stdout, stderr = job.async_run({ cmd = cmd, args = args })
  local lines = vim.split(stdout or "", null_terminated and "\0" or "\n", { plain = true })
  if lines[#lines] == "" then
    lines[#lines] = nil
  end

  return lines, stderr
end

---@param path string
---@return string path
local function windowize_path(path)
  local str = path:gsub("/", "\\")
  return str
end

---@async
---@param path string
---@param cmd? string
---@return string|nil toplevel, string git_dir, string branch
local function get_repo_info(path, cmd)
  local args = {
    "-C",
    path,
    "rev-parse",
    "--show-toplevel",
    "--absolute-git-dir",
    "--abbrev-ref",
    "HEAD",
  }

  local result = command(args, false, cmd)
  async.scheduler()
  if #result == 0 then
    return nil, "", ""
  end

  local toplevel = result[1]
  local git_root = result[2]
  local branch = result[3]
  if utils.is_windows then
    toplevel = windowize_path(toplevel)
    git_root = windowize_path(git_root)
  end

  return toplevel, git_root, branch
end

---@class Yat.Git.Repo : Yat.Object
---@field protected new async fun(self: Yat.Git.Repo, toplevel: string, git_dir: string, branch: string, is_yadm: boolean): Yat.Git.Repo
---
---@field public toplevel string
---@field public remote_url string
---@field public branch string
---@field package _is_yadm boolean
---@field private _git_dir string
---@field private _git_dir_watcher? uv_fs_poll_t
---@field package _index Yat.Git.IndexCommands
---@field private _status Yat.Git.StatusCommand
local Repo = meta.create_class("Yat.Git.Repo")

Repo.__tostring = function(self)
  return string.format("(toplevel=%s, git_dir=%s, is_yadm=%s)", self.toplevel, self._git_dir, self._is_yadm)
end

---@param other Yat.Git.Repo
Repo.__eq = function(self, other)
  return self._git_dir == other._git_dir
end

---@class Yat.Git.IndexCommands
---@field package repo Yat.Git.Repo
local GitIndex = {}
GitIndex.__index = GitIndex

---@private
---@param repo Yat.Git.Repo
---@return Yat.Git.IndexCommands
function GitIndex:new(repo)
  return setmetatable({ repo = repo }, self)
end

---@class Yat.Git.Repo.MetaStatus
---@field public unmerged integer
---@field public stashed integer
---@field public behind integer
---@field public ahead integer
---@field public staged integer
---@field public unstaged integer
---@field public untracked integer

---@class Yat.Git.Repo.Status : Yat.Git.Repo.MetaStatus
---@field package _timestamp integer
---@field package _changed_entries table<string, string>
---@field package _propagated_changed_entries table<string, string>
---@field package _ignored string[]

---@class Yat.Git.StatusCommand
---@field package repo Yat.Git.Repo
---@field package status Yat.Git.Repo.Status
local GitStatus = {}
GitStatus.__index = GitStatus

---@private
---@param class Yat.Git.StatusCommand
---@param repo Yat.Git.Repo
---@return Yat.Git.StatusCommand
function GitStatus.new(class, repo)
  ---@type Yat.Git.StatusCommand
  local self = {
    repo = repo,
    status = {
      unmerged = 0,
      stashed = 0,
      behind = 0,
      ahead = 0,
      staged = 0,
      unstaged = 0,
      untracked = 0,
      _timestamp = 0,
      _changed_entries = {},
      _propagated_changed_entries = {},
      _ignored = {},
    },
  }
  return setmetatable(self, class)
end

---@private
---@param toplevel string
---@param git_dir string
---@param branch string
---@param is_yadm boolean
function Repo:init(toplevel, git_dir, branch, is_yadm)
  self.toplevel = toplevel
  self.branch = branch
  self._is_yadm = is_yadm
  self._git_dir = git_dir
  self._index = GitIndex:new(self)
  self._status = GitStatus:new(self)

  self:_get_remote_url()

  if Config.config.git.watch_git_dir then
    self:_add_git_watcher(Config.config)
  end
end

---@return boolean is_yadm
function Repo:is_yadm()
  return self._is_yadm
end

---@private
---@param config Yat.Config
function Repo:_add_git_watcher(config)
  local log = Logger.get("git")
  if not self._git_dir_watcher then
    ---@param err string
    ---@type fun(err?: string)
    local fs_poll_callback = async.void(function(err)
      log.debug("fs_poll for %s", tostring(self))
      if err then
        log.error("git dir watcher for %q encountered an error: %s", self._git_dir, err)
        return
      end

      self._status:refresh({ ignored = true })
      async.scheduler()
      events.fire_git_event(event.git.DOT_GIT_DIR_CHANGED, self)
    end)

    local result, message
    self._git_dir_watcher, message = uv.new_fs_poll()
    if not self._git_dir_watcher then
      log.error("failed to create fs_poll for directory %s, error: %s", self._git_dir, message)
      return
    end

    log.debug("setting up git dir watcher for repo %s with interval %s", tostring(self), config.git.watch_git_dir_interval)
    result, message = self._git_dir_watcher:start(self._git_dir, config.git.watch_git_dir_interval, fs_poll_callback)
    if result == 0 then
      log.debug("successfully started fs_poll for directory %s", self._git_dir)
    else
      pcall(self._git_dir_watcher.stop, self._git_dir_watcher)
      pcall(self._git_dir_watcher.close, self._git_dir_watcher)
      self._git_dir_watcher = nil
      log.error("failed to start fs_poll for directory %s, error: %s", self._git_dir, message)
    end
  end
end

---@package
function Repo:_remove_git_watcher()
  if self._git_dir_watcher ~= nil then
    self._git_dir_watcher:stop()
    self._git_dir_watcher:close()
    self._git_dir_watcher = nil
    if vim.v.exiting == vim.NIL then
      Logger.get("git").debug("stopping fs_poll for repo %s", tostring(self))
    end
  end
end

---@param path string
---@param directory boolean
---@return boolean ignored
function Repo:is_ignored(path, directory)
  local sep = Path.path.sep
  path = directory and (path .. sep) or path
  for _, ignored in ipairs(self._status.status._ignored) do
    if ignored:sub(-1) == sep then
      -- directory ignore
      if vim.startswith(path, ignored) then
        return true
      end
    else
      -- file ignore
      if path == ignored then
        return true
      end
    end
  end
  return false
end

---@async
---@param args string[]
---@param null_terminated? boolean
---@return string[] results empty if an error occurred
---@return string? error_message
function Repo:command(args, null_terminated)
  -- always run in the the toplevel directory, so all paths are relative the root,
  -- this way we can just concatenate the paths returned by git with the toplevel
  local results, err = command({ "--git-dir=" .. self._git_dir, "-C", self.toplevel, unpack(args) }, null_terminated)
  async.scheduler()
  if err then
    local message = vim.split(err, "\n", { plain = true, trimempty = true })
    Logger.get("git").error("error running git command, %s", table.concat(message, " "))
    return {}, err
  end
  return results
end

---@async
---@private
function Repo:_get_remote_url()
  local result, err = self:command({ "ls-remote", "--get-url" })
  if not err then
    self.remote_url = result[1]
  end
end

---@return Yat.Git.IndexCommands
function Repo:index()
  return self._index
end

---@async
---@param path string
---@return string|nil error_message
function GitIndex:add(path)
  local _, err = self.repo:command({ "add", path })
  return err
end

---@async
---@param path string
---@param staged? boolean
---@return string|nil error_message
function GitIndex:restore(path, staged)
  local args = { "restore" }
  if staged then
    args[#args + 1] = "--staged"
  end
  args[#args + 1] = path
  local _, err = self.repo:command(args)
  return err
end

---@async
---@param path string
---@param new_path string
---@return string|nil error_message
function GitIndex:move(path, new_path)
  local _, err = self.repo:command({ "mv", path, new_path })
  return err
end

---@return Yat.Git.StatusCommand
function Repo:status()
  return self._status
end

---@return string[] files
function GitStatus:changed_paths()
  return vim.tbl_keys(self.status._changed_entries) --[=[@as string[]]=]
end

---@return Yat.Git.Repo.MetaStatus status
function GitStatus:meta()
  return self.status
end

---@param opts { header?: boolean, ignored?: boolean, all_untracked?: boolean }
---@param path? string
---  - {opts.header?} `boolean`
---  - {opts.ignored?} `boolean`
---  - {opts.all_untracked?} `boolean`
---@return string[] arguments
local function create_status_arguments(opts, path)
  -- use "-z" , otherwise bytes > 0x80 will be quoted, eg octal \303\244 for "ä"
  -- another option is using "-c" "core.quotePath=false"
  local args = {
    "--no-optional-locks",
    "status",
    -- --ignore-submodules=all, -- this is the default
    "--porcelain=v2",
    "-z", -- null-terminated
  }
  if opts.all_untracked then
    args[#args + 1] = "-uall" -- --untracked-files=all
  else
    args[#args + 1] = "-unormal" -- --untracked-files=normal
  end
  if opts.header then
    args[#args + 1] = "-b" --branch
    args[#args + 1] = "--show-stash"
  end
  -- only include ignored if requested
  if opts.ignored then
    args[#args + 1] = "--ignored=matching"
  else
    args[#args + 1] = "--ignored=no"
  end
  if path then
    args[#args + 1] = path
  end

  return args
end

---@param status string
---@return boolean staged
local function is_staged(status)
  return status:sub(1, 1) ~= "."
end

---@param status string
---@return boolean unstaged
local function is_unstaged(status)
  return status:sub(2, 2) ~= "."
end

---@param status string
---@return boolean untracked
local function is_untracked(status)
  return status:sub(1, 1) == "?"
end

do
  local ONE_SECOND_IN_NS = 1000 * 1000 * 1000

  ---@async
  ---@param path string
  function GitStatus:refresh_path(path)
    local log = Logger.get("git")
    local now = uv.hrtime()
    if (self.status._timestamp + ONE_SECOND_IN_NS) > now then
      log.debug("refresh(_path) called within 1 second, returning")
    end
    local is_directory = fs.is_directory(path)
    if is_directory then
      path = path .. Path.path.sep
    end
    local args = create_status_arguments({ header = false, ignored = false }, path)
    log.debug("git status for path %q", path)
    local results, err = self.repo:command(args, true)
    if err then
      return
    end

    local function update_status(old_status)
      if is_staged(old_status) then
        self.status.staged = self.status.staged - 1
      end
      if is_unstaged(old_status) then
        self.status.unstaged = self.status.unstaged - 1
      end
      if is_untracked(old_status) then
        self.status.untracked = self.status.untracked - 1
      end
    end

    self.status._timestamp = now
    ---@type table<string, string>
    local old_changes = {}
    if is_directory then
      for changed_path, old_status in pairs(self.status._changed_entries) do
        if vim.startswith(changed_path, path) then
          old_changes[changed_path] = old_status
          update_status(old_status)
        end
      end
    else
      local old_status = self.status._changed_entries[path]
      if old_status then
        old_changes[path] = old_status
        update_status(old_status)
      end
    end

    ---@type table<string, boolean>
    local changed_paths = {}
    local i = 1
    while i <= #results do
      local line = results[i]
      local line_type = line:sub(1, 1)
      if line_type == "1" then
        local absolute_path = self:_parse_porcelainv2_change_row(line)
        changed_paths[absolute_path] = true
      elseif line_type == "2" then
        -- the new and original paths are separated by NUL,
        -- the original path isn't currently used, so just step over it
        i = i + 1
        local absolute_path = self:_parse_porcelainv2_rename_row(line)
        changed_paths[absolute_path] = true
      elseif line_type == "?" then
        local absolute_path = self:_parse_porcelainv2_untracked_row(line)
        if absolute_path then
          changed_paths[absolute_path] = true
        end
      end
      i = i + 1
    end
    local propagete = false
    for old_path in pairs(old_changes) do
      if not changed_paths[old_path] then
        self.status._changed_entries[old_path] = nil
        propagete = true
      end
    end
    if propagete then
      self.status._propagated_changed_entries = {}
      for _path, status in pairs(self.status._changed_entries) do
        if status ~= "!" then
          local fully_staged = is_staged(status) and not is_unstaged(status)
          self:_propagate_status_to_parents(_path, fully_staged)
        end
      end
    end

    async.scheduler()
  end

  ---@async
  ---@param opts? { ignored?: boolean }
  ---  - {opts.ignored?} `boolean`
  function GitStatus:refresh(opts)
    local log = Logger.get("git")
    local now = uv.hrtime()
    if (self.status._timestamp + ONE_SECOND_IN_NS) > now then
      log.debug("refresh(_path) called within 1 second, returning")
    end
    opts = opts or {}
    local args = create_status_arguments({
      header = true,
      ignored = opts.ignored,
      all_untracked = Config.config.git.all_untracked or self.repo._is_yadm,
    })
    log.debug("git status for %q", self.repo.toplevel)
    local results, err = self.repo:command(args, true)
    if err then
      return false
    end

    self.status.unmerged = 0
    self.status.stashed = 0
    self.status.behind = 0
    self.status.ahead = 0
    self.status.staged = 0
    self.status.unstaged = 0
    self.status.untracked = 0
    self.status._timestamp = now
    self.status._changed_entries = {}
    self.status._propagated_changed_entries = {}
    self.status._ignored = {}

    local i = 1
    while i <= #results do
      local line = results[i]
      local line_type = line:sub(1, 1)
      if line_type == "#" then
        self:_parse_porcelainv2_header_row(line)
      elseif line_type == "1" then
        self:_parse_porcelainv2_change_row(line)
      elseif line_type == "2" then
        -- the new and original paths are separated by NUL,
        -- the original path isn't currently used, so just step over it
        i = i + 1
        self:_parse_porcelainv2_rename_row(line)
      elseif line_type == "u" then
        self:_parse_porcelainv2_merge_row(line)
      elseif line_type == "?" then
        self:_parse_porcelainv2_untracked_row(line)
      elseif line_type == "!" then
        self:_parse_porcelainv2_ignored_row(line)
      else
        log.warn("unknown status type %q, full line=%q", line_type, line)
      end

      i = i + 1
    end

    async.scheduler()
  end
end

---@private
---@param line string
function GitStatus:_parse_porcelainv2_header_row(line)
  -- FORMAT
  --
  -- Line                                     Notes
  -- --------------------------------------------------------------------------------------
  -- # branch.oid <commit> | (initial)        Current commit.
  -- # branch.head <branch> | (detached)      Current branch.
  -- # branch.upstream <upstream_branch>      If upstream is set.
  -- # branch.ab +<ahead> -<behind>           If upstream is set and the commit is present.
  -- --------------------------------------------------------------------------------------

  local parts = vim.split(line, " ", { plain = true })
  local _type = parts[2]
  if _type == "branch.head" then
    self.branch = parts[3]
  elseif _type == "branch.ab" then
    local ahead = parts[3]
    if ahead then
      self.status.ahead = tonumber(ahead:sub(2)) or 0
    end
    local behind = parts[4]
    if behind then
      self.status.behind = tonumber(behind:sub(2)) or 0
    end
  elseif _type == "stash" then
    self.status.stashed = tonumber(parts[3]) or 0
  end
end

---@param toplevel string the toplevel path
---@param relative_path string the root-relative path
---@return string absolute_path the absolute path
local function make_absolute_path(toplevel, relative_path)
  if utils.is_windows == true then
    relative_path = windowize_path(relative_path)
  end
  return fs.join_path(toplevel, relative_path)
end

---@private
---@param line string
---@return string absolue_path
function GitStatus:_parse_porcelainv2_change_row(line)
  -- FORMAT
  --
  -- 1 <XY> <sub> <mH> <mI> <mW> <hH> <hI> <path>

  local status = line:sub(3, 4)
  local relative_path = line:sub(114)
  local absolute_path = make_absolute_path(self.repo.toplevel, relative_path)
  self.status._changed_entries[absolute_path] = status
  local fully_staged = self:_update_stage_counts(status)
  self:_propagate_status_to_parents(absolute_path, fully_staged)
  return absolute_path
end

---@private
---@param status string
---@return boolean fully_staged
function GitStatus:_update_stage_counts(status)
  local staged = is_staged(status)
  local unstaged = is_unstaged(status)
  if staged then
    self.status.staged = self.status.staged + 1
  end
  if unstaged then
    self.status.unstaged = self.status.unstaged + 1
  end

  return staged and not unstaged
end

---@private
---@param path string
---@param fully_staged boolean
function GitStatus:_propagate_status_to_parents(path, fully_staged)
  local status = fully_staged and "staged" or "dirty"
  local size = #self.repo.toplevel
  for _, parent in next, Path:new(path):parents() do
    -- stop at directories below the toplevel directory
    if #parent <= size then
      break
    end
    if self.status._propagated_changed_entries[parent] == "dirty" then
      -- if the status of a parent is already "dirty", don't overwrite it, and stop
      return
    end
    self.status._propagated_changed_entries[parent] = status
  end
end

---@private
---@param line string
---@return string absolue_path
function GitStatus:_parse_porcelainv2_rename_row(line)
  -- FORMAT
  --
  -- 2 <XY> <sub> <mH> <mI> <mW> <hH> <hI> <X><score> <path><sep><origPath>

  -- currently the line parameter doesn't include the <sep><origPath> part,
  -- see the comment in Repo:refresh_status

  local status = line:sub(3, 4)
  -- the score field is of variable length, and begins at col 114 and ends with space
  local end_of_score_pos = line:find(" ", 114, true)
  local relative_path = line:sub(end_of_score_pos + 1)
  local absolute_path = make_absolute_path(self.repo.toplevel, relative_path)
  self.status._changed_entries[absolute_path] = status
  local fully_staged = self:_update_stage_counts(status)
  self:_propagate_status_to_parents(absolute_path, fully_staged)
  return absolute_path
end

---@private
---@param line string
function GitStatus:_parse_porcelainv2_merge_row(line)
  -- FORMAT
  -- u <XY> <sub> <m1> <m2> <m3> <mW> <h1> <h2> <h3> <path>

  local status = line:sub(3, 4)
  local relative_path = line:sub(162)
  local absolute_path = make_absolute_path(self.repo.toplevel, relative_path)
  self.status._changed_entries[absolute_path] = status
  self.status.unmerged = self.status.unmerged + 1
end

---@private
---@param line string
---@return string|nil absolue_path
function GitStatus:_parse_porcelainv2_untracked_row(line)
  -- FORMAT
  --
  -- ? <path>

  -- if in a yadm managed repository/directory it's quite likely that _a lot_ of
  -- files will be untracked, so don't add untracked files in that case.
  if not self.repo._is_yadm then
    local status = line:sub(1, 1)
    local relative_path = line:sub(3)
    local absolute_path = make_absolute_path(self.repo.toplevel, relative_path)
    self.status._changed_entries[absolute_path] = status
    self.status.untracked = self.status.untracked + 1
    return absolute_path
  end
end

---@private
---@param line string
---@return string absolute_path
function GitStatus:_parse_porcelainv2_ignored_row(line)
  -- FORMAT
  --
  -- ! path/to/directory/
  -- ! path/to/file

  local status = line:sub(1, 1)
  local relative_path = line:sub(3)
  local absolute_path = make_absolute_path(self.repo.toplevel, relative_path)
  self.status._changed_entries[absolute_path] = status
  self.status._ignored[#self.status._ignored + 1] = absolute_path
  return absolute_path
end

---@param path string
---@param directory boolean
---@return string|nil status
function GitStatus:of(path, directory)
  local sep = Path.path.sep
  local status = self.status._changed_entries[path] or self.status._propagated_changed_entries[path]
  if not status then
    path = directory and (path .. sep) or path
    for _path, _status in pairs(self.status._changed_entries) do
      if _status == "?" and _path:sub(-1) == sep and vim.startswith(path, _path) then
        return _status
      end
    end
  end
  return status
end

---@async
---@param path string
---@return Yat.Git.Repo|nil repo a `Repo` object or `nil` if the path is not in a git repo.
function M.create_repo(path)
  local log = Logger.get("git")
  -- check if it's already cached
  local cached = M.repos[path]
  if cached then
    log.debug("repository for %s already created, returning cached repo %s", path, tostring(cached))
    return cached
  end

  if not Config.config.git.enable then
    return nil
  end

  if not fs.is_directory(path) then
    path = Path:new(path):parent().filename
  end

  local toplevel, git_dir, branch = get_repo_info(path)
  local is_yadm = false
  if not toplevel and Config.config.git.yadm.enable then
    if vim.startswith(path, Path.path.home) and #command({ "ls-files", path }, false, "yadm") ~= 0 then
      toplevel, git_dir, branch = get_repo_info(path, "yadm")
      is_yadm = toplevel ~= nil
    end
    async.scheduler()
  end

  if not toplevel then
    log.debug("no git repo found for %q", path)
    return nil
  end

  cached = M.repos[toplevel]
  if cached then
    log.debug("%q is in repository %q, which already exists, returning it", path, tostring(cached))
    return cached
  end

  local repo = Repo:new(toplevel, git_dir, branch, is_yadm)
  M.repos[repo.toplevel] = repo
  log.info("created Repo %s for %q", tostring(repo), path)
  return repo
end

---@param repo Yat.Git.Repo
function M.remove_repo(repo)
  repo:_remove_git_watcher()
  M.repos[repo.toplevel] = nil
  Logger.get("git").debug("removed repo %s from cache", tostring(repo))
end

---@param path string
---@return Yat.Git.Repo|nil repo
function M.get_repo_for_path(path)
  ---@type table<string, Yat.Git.Repo>
  local yadm_repos = {}
  for toplevel, repo in pairs(M.repos) do
    if not repo._is_yadm then
      if vim.startswith(path, toplevel) then
        return repo
      end
    else
      yadm_repos[toplevel] = repo
    end
  end

  for toplevel, repo in pairs(yadm_repos) do
    if vim.startswith(path, toplevel) then
      return repo
    end
  end
end

events.on_autocmd_event(event.autocmd.LEAVE_PRE, "YA_TREE_GIT_CLEANUP", function()
  for _, repo in pairs(M.repos) do
    repo:_remove_git_watcher()
  end
end)

return M

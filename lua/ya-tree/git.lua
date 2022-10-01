local scheduler = require("plenary.async.util").scheduler
local void = require("plenary.async").void
local wrap = require("plenary.async").wrap
local Path = require("plenary.path")

local config = require("ya-tree.config").config
local events = require("ya-tree.events")
local fs = require("ya-tree.filesystem")
local job = require("ya-tree.job")
local utils = require("ya-tree.utils")
local log = require("ya-tree.log")("git")

local os_sep = Path.path.sep

local uv = vim.loop

local M = {
  ---@type table<string, Yat.Git.Repo>
  repos = setmetatable({}, { __mode = "kv" }),
}

---@param args string[]
---@param null_terminated? boolean
---@param cmd? string
---@param callback fun(stdin: string[], stderr?: string)
---@type async fun(args: string[], null_terminated?: boolean, cmd?: string): string[], string?
local command = wrap(function(args, null_terminated, cmd, callback)
  cmd = cmd or "git"
  args = cmd == "git" and { "--no-pager", unpack(args) } or args

  job.run({ cmd = cmd, args = args }, function(_, stdout, stderr)
    local lines = vim.split(stdout or "", null_terminated and "\0" or "\n", { plain = true }) --[=[@as string[]]=]
    if lines[#lines] == "" then
      lines[#lines] = nil
    end

    callback(lines, stderr)
  end)
end, 4)

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
  scheduler()
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

---@class uv_fs_poll_t
---@field start fun(self: uv_fs_poll_t, path: string, interval: number, callback: fun(err: string)):0|nil, string?
---@field stop fun(self: uv_fs_poll_t):0|nil, string?
---@field close fun(self: uv_fs_poll_t)

---@class Yat.Git.Repo.MetaStatus
---@field public unmerged integer
---@field public stashed integer
---@field public behind integer
---@field public ahead integer
---@field public staged integer
---@field public unstaged integer
---@field public untracked integer

---@class Yat.Git.Repo.Status : Yat.Git.Repo.MetaStatus
---@field private _changed_entries table<string, string>
---@field private _propagated_changed_entries table<string, string>
---@field private _ignored string[]

---@class Yat.Git.Repo
---@field public toplevel string
---@field public remote_url string
---@field public branch string
---@field private _status Yat.Git.Repo.Status
---@field private _is_yadm boolean
---@field private _git_dir string
---@field private _git_dir_watcher? uv_fs_poll_t
local Repo = {}
Repo.__index = Repo

---@param self Yat.Git.Repo
---@return string
Repo.__tostring = function(self)
  return string.format("(toplevel=%s, git_dir=%s, is_yadm=%s)", self.toplevel, self._git_dir, self._is_yadm)
end

---@param self Yat.Git.Repo
---@param other Yat.Git.Repo
---@return boolean
Repo.__eq = function(self, other)
  return self._git_dir == other._git_dir
end

---@async
---@param path string
---@return Yat.Git.Repo|nil repo a `Repo` object or `nil` if the path is not in a git repo.
function Repo:new(path)
  -- check if it's already cached
  local cached = M.repos[path]
  if cached then
    log.debug("repository for %s already created, returning cached repo %s", path, tostring(cached))
    return cached
  end

  if not config.git.enable then
    return nil
  end

  if not fs.is_directory(path) then
    path = Path:new(path):parent().filename --[[@as string]]
  end

  local toplevel, git_dir, branch = get_repo_info(path)
  local is_yadm = false
  if not toplevel and config.git.yadm.enable then
    if vim.startswith(path, os.getenv("HOME")) and #command({ "ls-files", path }, false, "yadm") ~= 0 then
      toplevel, git_dir, branch = get_repo_info(path, "yadm")
      is_yadm = toplevel ~= nil
    end
    scheduler()
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

  ---@type Yat.Git.Repo
  local this = {
    toplevel = toplevel,
    branch = branch,
    _status = {
      unmerged = 0,
      stashed = 0,
      behind = 0,
      ahead = 0,
      staged = 0,
      unstaged = 0,
      untracked = 0,
      _changed_entries = {},
      _propagated_changed_entries = {},
      _ignored = {},
    },
    _is_yadm = is_yadm,
    _git_dir = git_dir,
  }
  setmetatable(this, self)

  this:_read_remote_url()

  log.debug("created Repo %s for %q", tostring(this), path)
  M.repos[this.toplevel] = this

  if config.git.watch_git_dir then
    this:add_git_watcher()
  end
  return this
end

---@return boolean is_yadm
function Repo:is_yadm()
  return self._is_yadm
end

---@return string[] files
function Repo:working_tree_changed_paths()
  return vim.tbl_keys(self._status._changed_entries) --[=[@as string[]]=]
end

---@return Yat.Git.Repo.MetaStatus status
function Repo:meta_status()
  return self._status
end

function Repo:add_git_watcher()
  if not self._git_dir_watcher then
    local event = require("ya-tree.events.event").git
    ---@param err string
    ---@type fun(err?: string)
    local fs_poll_callback = void(function(err)
      log.debug("fs_poll for %s", tostring(self))
      if err then
        log.error("git dir watcher for %q encountered an error: %s", self._git_dir, err)
        return
      end

      local fs_changes = self:refresh_status({ ignored = true })
      events.fire_git_event(event.DOT_GIT_DIR_CHANGED, self, fs_changes)
    end)

    local result, message = uv.new_fs_poll()
    if result ~= nil then
      self._git_dir_watcher = result
    else
      log.error("failed to create fs_poll for directory %s, error: %s", self._git_dir, message)
      return
    end

    log.debug("setting up git dir watcher for repo with internval %s", tostring(self), config.git.watch_git_dir_interval)
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

function Repo:remove_git_watcher()
  if self._git_dir_watcher ~= nil then
    self._git_dir_watcher:stop()
    self._git_dir_watcher:close()
    self._git_dir_watcher = nil
    if vim.v.exiting == vim.NIL then
      log.debug("the last listener was removed, stopping fs_poll for repo %s", tostring(self))
    end
  end
end

---@async
---@param args string[]
---@param null_terminated? boolean
---@return string[]
function Repo:command(args, null_terminated)
  -- always run in the the toplevel directory, so all paths are relative the root,
  -- this way we can just concatenate the paths returned by git with the toplevel
  local result, err = command({ "--git-dir=" .. self._git_dir, "-C", self.toplevel, unpack(args) }, null_terminated)
  scheduler()
  if err then
    local message = vim.split(err, "\n", { plain = true, trimempty = true })
    log.error("error running git command, %s", table.concat(message, " "))
  end
  return result
end

---@async
---@private
function Repo:_read_remote_url()
  self.remote_url = self:command({ "ls-remote", "--get-url" })[1]
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

---@param opts { header?: boolean, ignored?: boolean, all_untracked?: boolean }
---  - {opts.header?} `boolean`
---  - {opts.ignored?} `boolean`
---  - {opts.all_untracked?} `boolean`
---@return string[] arguments
local function create_status_arguments(opts)
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

  return args
end

---@async
---@param path string
---@return boolean changed
function Repo:refresh_status_for_path(path)
  if fs.is_directory(path) then
    log.error("only individual paths are supported by this method!")
    return true
  end
  local args = create_status_arguments({ header = false, ignored = false })
  args[#args + 1] = path
  log.debug("git status for path %q", path)
  local results = self:command(args, true)

  local old_status = self._status._changed_entries[path]
  if old_status then
    if is_staged(old_status) then
      self._status.staged = self._status.staged - 1
    end
    if is_unstaged(old_status) then
      self._status.unstaged = self._status.unstaged - 1
    end
  end

  local relative_path = utils.relative_path_for(path, self.toplevel)
  local i = 1
  local found = false
  while i <= #results do
    local line = results[i]
    if line:find(relative_path, 1, true) then
      found = true
      local line_type = line:sub(1, 1)
      if line_type == "1" then
        self:_parse_porcelainv2_change_row(line)
      elseif line_type == "2" then
        -- the new and original paths are separated by NUL,
        -- the original path isn't currently used, so just step over it
        i = i + 1
        self:_parse_porcelainv2_rename_row(line)
      elseif line_type == "?" then
        self:_parse_porcelainv2_untracked_row(line)
      end
    end
    i = i + 1
  end
  if not found then
    self._status._changed_entries[path] = nil
    self._status._propagated_changed_entries = {}
    for _path, status in pairs(self._status._changed_entries) do
      if status ~= "!" then
        local fully_staged = is_staged(status) and not is_unstaged(status)
        self:_propagate_status_to_parents(_path, fully_staged)
      end
    end
  end

  scheduler()
  return old_status ~= self._status._changed_entries[path]
end

---@async
---@param opts? { ignored?: boolean }
---  - {opts.ignored?} `boolean`
---@return boolean fs_changes
function Repo:refresh_status(opts)
  opts = opts or {}
  local args = create_status_arguments({ header = true, ignored = opts.ignored, all_untracked = self._is_yadm })
  log.debug("git status for %q", self.toplevel)
  local results = self:command(args, true)

  local old_changed_entries = self._status._changed_entries
  self._status.unmerged = 0
  self._status.stashed = 0
  self._status.behind = 0
  self._status.ahead = 0
  self._status.staged = 0
  self._status.unstaged = 0
  self._status.untracked = 0
  self._status._changed_entries = {}
  self._status._propagated_changed_entries = {}
  self._status._ignored = {}

  local fs_changes = false
  local i = 1
  while i <= #results do
    local line = results[i]
    local line_type = line:sub(1, 1)
    if line_type == "#" then
      self:_parse_porcelainv2_header_row(line)
    elseif line_type == "1" then
      fs_changes = self:_parse_porcelainv2_change_row(line) or fs_changes
    elseif line_type == "2" then
      -- the new and original paths are separated by NUL,
      -- the original path isn't currently used, so just step over it
      i = i + 1
      self:_parse_porcelainv2_rename_row(line)
      fs_changes = true
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

  -- _parse_porcelainv2_change_row and _parse_porcelainv2_rename_row doens't detect all changes
  -- that signify a fs change, comparing the number of entries gives it a decent chance
  fs_changes = fs_changes or vim.tbl_count(old_changed_entries) ~= vim.tbl_count(self._status._changed_entries)

  scheduler()
  return fs_changes
end

---@private
---@param line string
function Repo:_parse_porcelainv2_header_row(line)
  -- FORMAT
  --
  -- Line                                     Notes
  -- --------------------------------------------------------------------------------------
  -- # branch.oid <commit> | (initial)        Current commit.
  -- # branch.head <branch> | (detached)      Current branch.
  -- # branch.upstream <upstream_branch>      If upstream is set.
  -- # branch.ab +<ahead> -<behind>           If upstream is set and the commit is present.
  -- --------------------------------------------------------------------------------------

  local parts = vim.split(line, " ", { plain = true }) --[=[@as string[]]=]
  local _type = parts[2]
  if _type == "branch.head" then
    self.branch = parts[3]
  elseif _type == "branch.ab" then
    local ahead = parts[3]
    if ahead then
      self._status.ahead = tonumber(ahead:sub(2)) or 0
    end
    local behind = parts[4]
    if behind then
      self._status.behind = tonumber(behind:sub(2)) or 0
    end
  elseif _type == "stash" then
    self._status.stashed = tonumber(parts[3]) or 0
  end
end

---@param toplevel string the toplevel path
---@param relative_path string the root-relative path
---@return string absolute_path the absolute path
local function make_absolute_path(toplevel, relative_path)
  if utils.is_windows == true then
    relative_path = windowize_path(relative_path)
  end
  return utils.join_path(toplevel, relative_path)
end

---@private
---@param line string
---@return boolean fs_changes
function Repo:_parse_porcelainv2_change_row(line)
  -- FORMAT
  --
  -- 1 <XY> <sub> <mH> <mI> <mW> <hH> <hI> <path>

  local status = line:sub(3, 4)
  local relative_path = line:sub(114)
  local absolute_path = make_absolute_path(self.toplevel, relative_path)
  self._status._changed_entries[absolute_path] = status
  local fully_staged = self:_update_stage_counts(status)
  self:_propagate_status_to_parents(absolute_path, fully_staged)
  return status:sub(1, 1) == "D" or status:sub(2, 2) == "D"
end

---@private
---@param status string
---@return boolean fully_staged
function Repo:_update_stage_counts(status)
  local staged = is_staged(status)
  local unstaged = is_unstaged(status)
  if staged then
    self._status.staged = self._status.staged + 1
  end
  if unstaged then
    self._status.unstaged = self._status.unstaged + 1
  end

  return staged and not unstaged
end

---@private
---@param path string
---@param fully_staged boolean
function Repo:_propagate_status_to_parents(path, fully_staged)
  local status = fully_staged and "staged" or "dirty"
  local size = #self.toplevel
  for _, parent in next, Path:new(path):parents() do
    ---@cast parent string
    -- stop at directories below the toplevel directory
    if #parent <= size then
      break
    end
    if self._status._propagated_changed_entries[parent] == "dirty" then
      -- if the status of a parent is already "dirty", don't overwrite it, and stop
      return
    end
    self._status._propagated_changed_entries[parent] = status
  end
end

---@private
---@param line string
function Repo:_parse_porcelainv2_rename_row(line)
  -- FORMAT
  --
  -- 2 <XY> <sub> <mH> <mI> <mW> <hH> <hI> <X><score> <path><sep><origPath>

  -- currently the line parameter doesn't include the <sep><origPath> part,
  -- see the comment in Repo:refresh_status

  local status = line:sub(3, 4)
  -- the score field is of variable length, and begins at col 114 and ends with space
  local end_of_score_pos = line:find(" ", 114, true)
  local relative_path = line:sub(end_of_score_pos + 1)
  local absolute_path = make_absolute_path(self.toplevel, relative_path)
  self._status._changed_entries[absolute_path] = status
  local fully_staged = self:_update_stage_counts(status)
  self:_propagate_status_to_parents(absolute_path, fully_staged)
end

---@private
---@param line string
function Repo:_parse_porcelainv2_merge_row(line)
  -- FORMAT
  -- u <XY> <sub> <m1> <m2> <m3> <mW> <h1> <h2> <h3> <path>

  local status = line:sub(3, 4)
  local relative_path = line:sub(162)
  local absolute_path = make_absolute_path(self.toplevel, relative_path)
  self._status._changed_entries[absolute_path] = status
  self._status.unmerged = self._status.unmerged + 1
end

---@private
---@param line string
function Repo:_parse_porcelainv2_untracked_row(line)
  -- FORMAT
  --
  -- ? <path>

  -- if in a yadm managed repository/directory it's quite likely that _a lot_ of
  -- files will be untracked, so don't add untracked files in that case.
  if not self._is_yadm then
    local status = line:sub(1, 1)
    local relative_path = line:sub(3)
    local absolute_path = make_absolute_path(self.toplevel, relative_path)
    self._status._changed_entries[absolute_path] = status
    self._status.untracked = self._status.untracked + 1
  end
end

---@private
---@param line string
function Repo:_parse_porcelainv2_ignored_row(line)
  -- FORMAT
  --
  -- ! path/to/directory/
  -- ! path/to/file

  local status = line:sub(1, 1)
  local relative_path = line:sub(3)
  local absolute_path = make_absolute_path(self.toplevel, relative_path)
  self._status._changed_entries[absolute_path] = status
  self._status._ignored[#self._status._ignored + 1] = absolute_path
end

---@param path string
---@param _type Luv.FileType
---@return string|nil status
function Repo:status_of(path, _type)
  local status = self._status._changed_entries[path] or self._status._propagated_changed_entries[path]
  if not status then
    path = _type == "directory" and (path .. os_sep) or path
    for _path, _status in pairs(self._status._changed_entries) do
      if _status == "?" and _path:sub(-1) == os_sep and vim.startswith(path, _path) then
        status = _status
        break
      end
    end
  end
  return status
end

---@param path string
---@param _type Luv.FileType
---@return boolean ignored
function Repo:is_ignored(path, _type)
  path = _type == "directory" and (path .. os_sep) or path
  for _, ignored in ipairs(self._status._ignored) do
    if ignored:sub(-1) == os_sep then
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
---@param path string
---@return Yat.Git.Repo|nil repo a `Repo` object or `nil` if the path is not in a git repo.
function M.create_repo(path)
  return Repo:new(path)
end

---@param repo Yat.Git.Repo
function M.remove_repo(repo)
  repo:remove_git_watcher()
  M.repos[repo.toplevel] = nil
  log.debug("removed repo %s from cache", tostring(repo))
end

---@param path string
---@return Yat.Git.Repo|nil repo
function M.get_repo_for_path(path)
  ---@type table<string, Yat.Git.Repo>
  local yadm_repos = {}
  for toplevel, repo in pairs(M.repos) do
    if not repo._is_yadm then
      if path:find(toplevel, 1, true) then
        return repo
      end
    else
      yadm_repos[toplevel] = repo
    end
  end

  for toplevel, repo in pairs(yadm_repos) do
    if path:find(toplevel, 1, true) then
      return repo
    end
  end
end

local function on_vim_leave_pre()
  for _, repo in pairs(M.repos) do
    repo:remove_git_watcher()
  end
end

function M.setup()
  config = require("ya-tree.config").config

  local event = require("ya-tree.events.event").autocmd
  events.on_autocmd_event(event.LEAVE_PRE, "YA_TREE_GIT_CLEANUP", on_vim_leave_pre)
end

return M

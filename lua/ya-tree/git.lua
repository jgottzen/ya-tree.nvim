local void = require("plenary.async.async").void
local wrap = require("plenary.async.async").wrap
local scheduler = require("plenary.async.util").scheduler
local Path = require("plenary.path")

local config = require("ya-tree.config").config
local job = require("ya-tree.job")
local utils = require("ya-tree.utils")
local log = require("ya-tree.log")

local os_sep = Path.path.sep

local uv = vim.loop

local M = {
  ---@type GitRepo
  Repo = {},
  ---@type table<string, GitRepo>
  repos = setmetatable({}, { __mode = "kv" }),
}

---@type fun(args: string[], null_terminated?: boolean, cmd?: string): string[], string
local command = wrap(function(args, null_terminated, cmd, callback)
  cmd = cmd or "git"
  args = cmd == "git" and { "--no-pager", unpack(args) } or args

  job.run({ cmd = cmd, args = args }, function(_, stdout, stderr)
    ---@type string[]
    local lines = vim.split(stdout or "", null_terminated and "\0" or "\n", { plain = true })
    if lines[#lines] == "" then
      lines[#lines] = nil
    end

    callback(lines, stderr)
  end)
end, 4)

---@param path string
---@return string path
local function windowize_path(path)
  return path:gsub("/", "\\")
end

---@param path string
---@param cmd? string
---@return string toplevel, string git_dir, string branch
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

  scheduler()

  local result = command(args, false, cmd)
  if #result == 0 then
    return nil
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
---@field start fun(self: uv_fs_poll_t, path: string, interval: number, callback: fun(err: string))
---@field stop fun(self: uv_fs_poll_t)

---@class GitRepo
---@field public toplevel string
---@field public remote_url string
---@field public branch string
---@field public unmerged number
---@field public stashed number
---@field public behind number
---@field public ahead number
---@field public staged number
---@field public unstaged number
---@field public untracked number
---@field private _is_yadm boolean
---@field private _git_dir string
---@field private _git_status table<string, string>
---@field private _ignored string[]
---@field private _git_dir_watcher? uv_fs_poll_t
---@field private _git_watchers table<string, fun(repo: GitRepo, watcher_id: number, fs_changes: boolean)>
local Repo = M.Repo
Repo.__index = Repo

---@param self GitRepo
---@return string
Repo.__tostring = function(self)
  return string.format("(toplevel=%s, git_dir=%s, is_yadm=%s)", self.toplevel, self._git_dir, self._is_yadm)
end

---@param path string
---@return GitRepo? repo #a `Repo` object or `nil` if the path is not in a git repo.
function Repo:new(path)
  -- check if it's already cached
  local cached = M.repos[path]
  if cached then
    log.debug("repository for %s already created, returning cached repo %s", path, tostring(cached))
    return cached
  end

  if not config.git.enable then
    return
  end

  local toplevel, git_dir, branch = get_repo_info(path)
  local is_yadm = false
  if not toplevel and config.git.yadm.enable then
    if vim.startswith(path, os.getenv("HOME")) and #command({ "ls-files", path }, false, "yadm") ~= 0 then
      toplevel, git_dir, branch = get_repo_info(path, "yadm")
      is_yadm = toplevel ~= nil
    end
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

  local this = setmetatable({
    toplevel = toplevel,
    branch = branch,
    unmerged = 0,
    stashed = 0,
    behind = 0,
    ahead = 0,
    staged = 0,
    unstaged = 0,
    untracked = 0,
    _is_yadm = is_yadm,
    _git_dir = git_dir,
    _git_status = {},
    _ignored = {},
    _git_watchers = {},
  }, self)

  this:_read_remote_url()

  log.debug("created Repo %s for %q", tostring(this), path)
  M.repos[this.toplevel] = this

  return this
end

---@return boolean is_yadm
function Repo:is_yadm()
  return self._is_yadm
end

---@param args string[]
---@param null_terminated? boolean
---@return string[]
function Repo:command(args, null_terminated)
  if not self._git_dir then
    return {}
  end

  scheduler()
  -- always run in the the toplevel directory, so all paths are relative the root,
  -- this way we can just concatenate the paths returned by git with the toplevel
  local result, e = command({ "--git-dir=" .. self._git_dir, "-C", self.toplevel, unpack(args) }, null_terminated)
  if e then
    local message = vim.split(e, "\n", { plain = true, trimempty = true })
    log.error("error running git command, %s", table.concat(message, " "))
  end
  return result
end

---@type fun(): number
local get_next_watcher_id
do
  local watcher_id = 0

  get_next_watcher_id = function()
    watcher_id = watcher_id + 1
    return watcher_id
  end
end

---@param fun async fun(repo: GitRepo, watcher_id: number, fs_changes: boolean)
---@return string watcher_id
function Repo:add_git_watcher(fun)
  if not self._git_dir_watcher then
    local function fs_poll_callback(err)
      log.debug("fs_poll for %s", tostring(self))
      if err then
        log.error("git dir watcher for %q encountered an error: %s", self._git_dir, err)
        return
      end

      if vim.tbl_count(self._git_watchers) == 0 then
        log.error("the fs_poll callback was called without any registered watchers")
        self._git_dir_watcher:stop()
        self._git_dir_watcher = nil
        return
      end

      scheduler()

      local fs_changes = self:refresh_status({ ignored = true })

      scheduler()

      for watcher_id, watcher in pairs(self._git_watchers) do
        pcall(watcher, self, watcher_id, fs_changes)
      end
    end

    self._git_dir_watcher = uv.new_fs_poll()
    log.debug("setting up git dir watcher for repo with internval %s", tostring(self), config.git.watch_git_dir_interval)

    local result = self._git_dir_watcher:start(self._git_dir, config.git.watch_git_dir_interval, void(fs_poll_callback))
    if result == 0 then
      log.debug("successfully started fs_poll for %s", self._git_dir)
    else
      log.error("failed to start fs_poll for %s, error: %s", self._git_dir, result)
    end
  end

  local watcher_id = get_next_watcher_id()
  self._git_watchers[watcher_id] = fun
  log.debug("add git watcher %s with id %s", fun, watcher_id)

  return watcher_id
end

---@param watcher_id string
function Repo:remove_git_watcher(watcher_id)
  if not self._git_watchers[watcher_id] then
    log.error("no watcher with id %s for repo %s", watcher_id, tostring(self))
    return
  end

  self._git_watchers[watcher_id] = nil
  log.debug("removed watcher with id %s for repo %s", watcher_id, tostring(self))

  if vim.tbl_count(self._git_watchers) == 0 then
    self._git_dir_watcher:stop()
    self._git_dir_watcher = nil
    log.debug("the last watcher was removed, stopping fs_poll")
  end
end

---@private
function Repo:_read_remote_url()
  if not self._git_dir then
    return
  end

  scheduler()

  self.remote_url = self:command({ "ls-remote", "--get-url" })[1]
end

---@param opts? { ignored?: boolean }
---  - {opts.ignored?} `boolean`
---@return boolean fs_changes
function Repo:refresh_status(opts)
  opts = opts or {}
  -- use "-z" , otherwise bytes > 0x80 will be quoted, eg octal \303\244 for "ä"
  -- another option is using "-c" "core.quotePath=false"
  local args = {
    "--no-optional-locks",
    "status",
    -- "--ignore-submodules=all", -- this is the default
    "--porcelain=v2",
    "-unormal", -- "--untracked-files=normal",
    "-b", --branch
    "--show-stash",
    "-z",
  }
  -- only include ignored if requested
  if opts.ignored then
    table.insert(args, "--ignored=matching")
  else
    table.insert(args, "--ignored=no")
  end

  log.debug("git status for %q, arguments %q", self.toplevel, table.concat(args, " "))
  local results = self:command(args, true)

  self.unmerged = 0
  self.staged = 0
  self.unstaged = 0
  self.untracked = 0
  self.stashed = 0
  self.ahead = 0
  self.behind = 0
  self._git_status = {}
  self._ignored = {}

  local fs_changes = false
  local size = #results
  local i = 1
  while i <= size do
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

  return fs_changes
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

  ---@type string[]
  local parts = vim.split(line, " ", { plain = true })
  if parts then
    local _type = parts[2]
    if _type == "branch.head" then
      self.branch = parts[3]
    elseif _type == "branch.ab" then
      local ahead = parts[3]
      if ahead then
        self.ahead = tonumber(ahead:sub(2)) or 0
      end
      local behind = parts[4]
      if behind then
        self.behind = tonumber(behind:sub(2)) or 0
      end
    elseif _type == "stash" then
      self.stashed = tonumber(parts[3]) or 0
    end
  end
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
  self._git_status[absolute_path] = status
  local fully_staged = self:_update_stage_counts(status)
  self:_propagate_status_to_parents(absolute_path, fully_staged)
  return status:sub(1, 1) == "D" or status:sub(2, 2) == "D"
end

---@private
---@param status string
---@return boolean fully_staged
function Repo:_update_stage_counts(status)
  local fully_staged = true
  if status:sub(1, 1) ~= "." then
    self.staged = self.staged + 1
  end
  if status:sub(2, 2) ~= "." then
    self.unstaged = self.unstaged + 1
    fully_staged = false
  end

  return fully_staged
end

---@private
---@param path string
---@param fully_staged boolean
function Repo:_propagate_status_to_parents(path, fully_staged)
  local status = fully_staged and "staged" or "dirty"
  local size = #self.toplevel
  for _, parent in next, Path:new(path):parents() do
    -- stop at directories below the toplevel directory
    ---@cast parent string
    if #parent <= size then
      break
    end
    if self._git_status[parent] == "dirty" then
      -- if the status of a parent is already "dirty", don't overwrite it, and stop
      return
    end
    self._git_status[parent] = status
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
  self._git_status[absolute_path] = status
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
  self._git_status[absolute_path] = status
  self.unmerged = self.unmerged + 1
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
    self._git_status[absolute_path] = status
    self.untracked = self.untracked + 1
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
  self._git_status[absolute_path] = status
  self._ignored[#self._ignored + 1] = absolute_path
end

---@param path string
---@return string|nil status
function Repo:status_of(path)
  return self._git_status[path]
end

---@param path string
---@param _type file_type
---@return boolean ignored
function Repo:is_ignored(path, _type)
  path = _type == "directory" and (path .. os_sep) or path
  for _, ignored in ipairs(self._ignored) do
    if #ignored > 0 and ignored:sub(-1) == os_sep then
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

---@param path string
---@return GitRepo? repo
function M.get_repo_for_path(path)
  ---@type table<string, GitRepo>
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

function M.setup()
  config = require("ya-tree.config").config
end

return M

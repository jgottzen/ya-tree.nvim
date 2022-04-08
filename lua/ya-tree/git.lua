local Path = require("plenary.path")
local wrap = require("plenary.async.async").wrap
local scheduler = require("plenary.async.util").scheduler

local config = require("ya-tree.config").config
local job = require("ya-tree.job")
local utils = require("ya-tree.utils")
local log = require("ya-tree.log")

local os_sep = Path.path.sep

local M = {
  ---@type Repo
  Repo = {},
  ---@type table<string, Repo>
  repos = {},
}

---@private
M.repos.__mode = "v"

---@type fun(args: string[], cmd: string): string[], string
local command = wrap(function(args, cmd, callback)
  cmd = cmd or "git"
  args = cmd == "git" and { "--no-pager", unpack(args) } or args

  job.run({ cmd = cmd, args = args }, function(_, stdout, stderr)
    local lines = vim.split(stdout or "", "\n", true)
    if lines[#lines] == "" then
      lines[#lines] = nil
    end

    callback(lines, stderr)
  end)
end, 3)

---@param path string
---@return string path
local function windowize_path(path)
  return path:gsub("/", "\\")
end

---@param path string
---@param cmd string
---@return string toplevel, string git_root
local function get_repo_info(path, cmd)
  local args = {
    "-C",
    path,
    "rev-parse",
    "--show-toplevel",
    "--absolute-git-dir",
  }

  scheduler()

  local result = command(args, cmd)
  if #result == 0 then
    return nil
  end
  local toplevel = result[1]
  local git_root = result[2]

  if utils.is_windows then
    toplevel = windowize_path(toplevel)
    git_root = windowize_path(git_root)
  end

  return toplevel, git_root
end

---@class Repo
---@field public toplevel string
---@field private _git_dir string
---@field private _git_status table<string, string>
---@field private _ignored string[]
---@field private _is_yadm boolean
local Repo = M.Repo
Repo.__index = Repo

---@param self Repo
---@return string
Repo.__tostring = function(self)
  return string.format("(toplevel=%q, git_dir=%q, is_yadm=%s)", self.toplevel, self._git_dir, self._is_yadm)
end

---@param path string
---@return Repo|nil repo #a `Repo` object or `nil` if the path is not in a git repo.
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

  local toplevel, git_dir = get_repo_info(path)
  local is_yadm = false
  if config.git.yadm.enable and not toplevel then
    if vim.startswith(path, os.getenv("HOME")) and #command({ "ls-files", path }, "yadm") ~= 0 then
      toplevel, git_dir = get_repo_info(path, "yadm")
      if toplevel then
        is_yadm = true
      end
    end
  end

  if not toplevel then
    log.debug("no git repo found for %q", path)
    return nil
  end

  local this = setmetatable({
    toplevel = toplevel,
    _git_dir = git_dir,
    _git_status = {},
    _ignored = {},
    _is_yadm = is_yadm,
  }, self)

  log.debug("created Repo %s for %q", tostring(this), path)
  M.repos[this.toplevel] = this

  return this
end

---@param args string[]
---@return string[]
function Repo:command(args)
  if not self._git_dir then
    return {}
  end

  scheduler()
  -- always run in the the toplevel directory, so all paths are relative the root,
  -- this way we can just concatenate the paths returned by git with the toplevel
  return command({ "--git-dir=" .. self._git_dir, "-C", self.toplevel, unpack(args) })
end

---@param opts? { ignored?: boolean }
---  - {opts.ignored?} `boolean`
function Repo:refresh_status(opts)
  opts = opts or {}
  local args = {
    "--no-optional-locks",
    "status",
    "--porcelain=v1",
  }
  -- only include ignored if requested
  if opts.ignored then
    table.insert(args, "--ignored=matching")
    -- yadm repositories requires that this flag is added explicitly
    if self._is_yadm then
      table.insert(args, "--untracked-files=normal")
    end
  end

  log.debug("refreshing git status for %q, with arguments=%s", self.toplevel, args)
  local results = self:command(args)

  self._git_status = {}
  self._ignored = {}

  local size = #self.toplevel
  for _, line in ipairs(results) do
    local status = line:sub(1, 2)
    local relative_path = line:sub(4)
    local arrow_pos = relative_path:find(" -> ")
    if arrow_pos then
      relative_path = line:sub(arrow_pos + 5)
    end
    -- remove any " due to whitespace in the path
    relative_path = relative_path:gsub('^"', ""):gsub('$"', "")
    if utils.is_windows == true then
      relative_path = windowize_path(relative_path)
    end
    local absolute_path = utils.join_path(self.toplevel, relative_path)
    -- if in a yadm managed repository/directory it's quite likely that _a lot_ of
    -- files will be untracked, so don't add untracked files in that case.
    if not (self._is_yadm and status == "??") then
      self._git_status[absolute_path] = status
    end

    -- git ignore format:
    -- !! path/to/directory/
    -- !! path/to/file
    -- with paths relative to the repository root
    if status == "!!" then
      self._ignored[#self._ignored + 1] = absolute_path
    else
      -- bubble the status up to the parent directories
      for _, parent in next, Path:new(absolute_path):parents() do
        -- don't add paths above the toplevel directory
        if #parent < size then
          break
        end
        self._git_status[parent] = "dirty"
      end
    end
  end
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
---@return Repo? repo
function M.get_repo_for_path(path)
  for toplevel, repo in pairs(M.repos) do
    if path:find(toplevel, 1, true) then
      return repo
    end
  end
end

function M.setup()
  config = require("ya-tree.config").config
end

return M

----------------------------------------------------------------------------------------------------
-- Based on: https://github.com/nvim-lua/plenary.nvim/blob/master/lua/plenary/path.lua
----------------------------------------------------------------------------------------------------

local F = vim.F
local uv = vim.loop

local path = {}

path.home = uv.os_homedir()

path.sep = (function()
  if jit then
    local os = string.lower(jit.os)
    if os ~= "windows" then
      return "/"
    else
      return "\\"
    end
  else
    -- selene: allow(incorrect_standard_library_use)
    return package.config:sub(1, 1)
  end
end)()

path.root = (function()
  if path.sep == "/" then
    return function()
      return "/"
    end
  else
    ---@param base? string
    ---@return string
    return function(base)
      base = base or uv.cwd() --[[@as string]]
      return base:sub(1, 1) .. ":\\"
    end
  end
end)()

---@type fun(filepath: string): string[]
local split_by_separator = (function()
  local formatted = string.format("([^%s]+)", path.sep)
  return function(filepath)
    local t = {}
    for str in string.gmatch(filepath, formatted) do
      table.insert(t, str)
    end
    return t
  end
end)()

---@param filename string
---@return boolean
local function is_uri(filename)
  return string.match(filename, "^%w+://") ~= nil
end

---@class Yat.Path
---@field private _cwd string
---@field private _absolute string
---@field public filename string
local Path = {
  path = path,
}

---@private
---@param t Yat.Path
---@param k string
Path.__index = function(t, k)
  local raw = rawget(Path, k)
  if raw then
    return raw
  end

  if k == "_cwd" then
    local cwd = uv.fs_realpath(".") --[[@as string]]
    t._cwd = cwd
    return cwd
  end

  if k == "_absolute" then
    local absolute = uv.fs_realpath(t.filename) --[[@as string]]
    t._absolute = absolute
    return absolute
  end
end

---@param pathname string
---@return string
local function clean(pathname)
  if is_uri(pathname) then
    return pathname
  end

  -- Remove double path seps, it's annoying
  pathname = pathname:gsub(path.sep .. path.sep, path.sep)

  -- Remove trailing path sep if not root
  if not Path.is_root(pathname) and pathname:sub(-1) == path.sep then
    return pathname:sub(1, -2)
  end
  return pathname
end

---@private
Path.__tostring = function(self)
  return clean(self.filename)
end

---@param a any
---@return boolean
function Path.is_path(a)
  return getmetatable(a) == Path
end

---@param filename string
---@param sep? string
---@return boolean
function Path.is_absolute_path(filename, sep)
  sep = sep or path.sep
  if sep == "\\" then
    return string.match(filename, "^[%a]:\\.*$") ~= nil
  end
  return string.sub(filename, 1, 1) == sep
end

---@param pathname string
---@return boolean
function Path.is_root(pathname)
  if path.sep == "\\" then
    return string.match(pathname, "^[A-Z]:\\?$")
  end
  return pathname == "/"
end

---@param ... string|Yat.Path
---@return Yat.Path
function Path:new(...)
  local args = { ... }

  if type(self) == "string" then
    table.insert(args, 1, self)
    self = Path
  end

  local path_input
  if #args == 1 then
    path_input = args[1]
  else
    path_input = args
  end

  -- If we already have a Path, it's fine.
  --   Just return it
  if Path.is_path(path_input) then
    return path_input --[[@as Yat.Path]]
  end

  local path_string
  if type(path_input) == "table" then
    local path_objs = {}
    for _, v in ipairs(path_input) do
      if Path.is_path(v) then
        ---@cast v Yat.Path
        path_objs[#path_objs + 1] = v.filename
      else
        assert(type(v) == "string", "type error :: parameters must be an array of strings")
        path_objs[#path_objs + 1] = v
      end
    end

    path_string = table.concat(path_objs, path.sep)
  else
    assert(type(path_input) == "string", vim.inspect(path_input))
    path_string = path_input
  end

  ---@type Yat.Path
  local this = {
    filename = path_string,
  }

  setmetatable(this, Path)

  return this
end

---@private
---@return string
function Path:_fs_filename()
  return self:absolute() or self.filename
end

---@private
---@return uv.aliases.fs_stat_table
function Path:_stat()
  return uv.fs_stat(self:_fs_filename()) or {}
end

---@return boolean
function Path:is_dir()
  return self:_stat().type == "directory"
end

---@return boolean
function Path:is_absolute()
  return Path.is_absolute_path(self.filename, path.sep)
end

---@return boolean
function Path:exists()
  return not vim.tbl_isempty(self:_stat())
end

---@param filename string
---@param cwd string
---@return string
local function normalize_path(filename, cwd)
  if is_uri(filename) then
    return filename
  end

  -- handles redundant `./` in the middle
  local redundant = path.sep .. "%." .. path.sep
  if filename:match(redundant) then
    filename = filename:gsub(redundant, path.sep)
  end

  local out_file = filename

  local has = string.find(filename, path.sep .. "..", 1, true) or string.find(filename, ".." .. path.sep, 1, true)

  if has then
    local is_abs = Path.is_absolute_path(filename, path.sep)

    ---@param filename_local string
    ---@return string[]
    local function split_without_disk_name(filename_local)
      local parts = split_by_separator(filename_local)
      -- Remove disk name part on Windows
      if path.sep == "\\" and is_abs then
        table.remove(parts, 1)
      end
      return parts
    end

    local parts = split_without_disk_name(filename)
    local idx = 1
    local initial_up_count = 0

    repeat
      if parts[idx] == ".." then
        if idx == 1 then
          initial_up_count = initial_up_count + 1
        end
        table.remove(parts, idx)
        table.remove(parts, idx - 1)
        if idx > 1 then
          idx = idx - 2
        else
          idx = idx - 1
        end
      end
      idx = idx + 1
    until idx > #parts

    local prefix = ""
    if is_abs or #split_without_disk_name(cwd) == initial_up_count then
      prefix = path.root(filename)
    end

    out_file = prefix .. table.concat(parts, path.sep)
  end

  return out_file
end

---@return string
function Path:absolute()
  if self:is_absolute() then
    return normalize_path(self.filename, self._cwd)
  else
    return normalize_path(self._absolute or table.concat({ self._cwd, self.filename }, path.sep), self._cwd)
  end
end

---@param to string
---@return string
function Path:make_relative(to)
  if is_uri(self.filename) then
    return self.filename
  end

  self.filename = clean(self.filename)
  to = clean(F.if_nil(to, self._cwd))
  if self.filename == to then
    self.filename = "."
  else
    if to:sub(#to, #to) ~= path.sep then
      to = to .. path.sep
    end

    if self.filename:sub(1, #to) == to then
      self.filename = self.filename:sub(#to + 1, -1)
    end
  end

  return self.filename
end

local _get_parent = (function()
  local formatted = string.format("^(.+)%s[^%s]+", path.sep, path.sep)
  ---@param abs_path string
  ---@return string
  return function(abs_path)
    return abs_path:match(formatted)
  end
end)()

---@return Yat.Path
function Path:parent()
  return Path:new(_get_parent(self:absolute()) or path.root(self:absolute()))
end

---@return string[]
function Path:parents()
  local results = {}
  local cur = self:absolute()
  repeat
    cur = _get_parent(cur)
    results[#results + 1] = cur
  until not cur
  results[#results + 1] = path.root(self:absolute())
  return results
end

return Path

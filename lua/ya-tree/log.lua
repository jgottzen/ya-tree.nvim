local Path = require("plenary.path")

local api = vim.api
local fn = vim.fn
local uv = vim.loop

---@class Yat.Logger
---@field config Yat.Logger.Config
local logger_class = {}
-- selene: allow(unused_variable)
---@param msg string
---@param ... any
---@overload fun(...)
---@diagnostic disable-next-line:unused-local
function logger_class.trace(msg, ...) end
-- selene: allow(unused_variable)
---@param msg string
---@param ... any
---@overload fun(...)
---@diagnostic disable-next-line:unused-local
function logger_class.debug(msg, ...) end
-- selene: allow(unused_variable)
---@param msg string
---@param ... any
---@overload fun(...)
---@diagnostic disable-next-line:unused-local
function logger_class.info(msg, ...) end
-- selene: allow(unused_variable)
---@param msg string
---@param ... any
---@overload fun(...)
---@diagnostic disable-next-line:unused-local
function logger_class.warn(msg, ...) end
-- selene: allow(unused_variable)
---@param msg string
---@param ... any
---@overload fun(...)
---@diagnostic disable-next-line:unused-local
function logger_class.error(msg, ...) end

---@alias Yat.Logger.Level "trace" | "debug" | "info" | "warn" | "error"

---@class Yat.Logger.Config
---@field namespaces string[]
---@field level Yat.Logger.Level
---@field levels {level: Yat.Logger.Level, highlight: string}[]
local config = {
  name = "ya-tree",
  namespaces = {},
  to_console = false,
  highlight = true,
  to_file = false,
  level = "warn",
  max_size = 5000,
  levels = {
    { level = "trace", highlight = "Comment" },
    { level = "debug", highlight = "Comment" },
    { level = "info", highlight = "NONE" },
    { level = "warn", highlight = "WarningMsg" },
    { level = "error", highlight = "ErrorMsg" },
  },
}

local log
do
  local inspect = vim.inspect
  local fmt = string.format
  local tbl_concat = table.concat
  local tbl_insert = table.insert

  ---@type table<Yat.Logger.Level, integer>
  local levels = {}
  for k, v in ipairs(config.levels) do
    levels[v.level] = k
  end
  local log_file = fmt("%s/%s.log", fn.stdpath("cache"), config.name)
  local dir = Path:new(log_file):parent()
  if not dir:exists() then
    dir:mkdir({ parents = true })
  end

  ---@param value any
  ---@return string
  local function str(value)
    local _type = type(value)
    if _type == "table" then
      local v = inspect(value, { depth = 20 })
      if #v > config.max_size then
        return v:sub(1, config.max_size)
      else
        return v
      end
    elseif _type == "function" then
      return inspect(value)
    else
      return tostring(value)
    end
  end

  ---@param ... any
  ---@return any[]
  local function pack(...)
    local rest = {}
    local list = { n = select("#", ...), ... }
    for i = 1, list.n do
      rest[i] = str(list[i])
    end
    return rest
  end

  ---@param arg any
  ---@param ... any
  ---@return string
  local function concat(arg, ...)
    local t = pack(...)
    tbl_insert(t, 1, str(arg))
    return tbl_concat(t, " ")
  end

  ---@param arg string
  ---@param ... any
  ---@return string
  local function format(arg, ...)
    if type(arg) == "string" then
      if arg:find("%s", 1, true) or arg:find("%q", 1, true) then
        if select("#", ...) > 0 then
          local rest = pack(...)
          local ok, m = pcall(fmt, arg, unpack(rest))
          if ok then
            return m
          end
        end
      end
    end

    return concat(arg, ...)
  end

  ---@param namespace string
  ---@param level integer
  ---@param level_name string
  ---@param highlight string
  ---@param arg any
  ---@param ... any
  log = function(namespace, level, level_name, highlight, arg, ...)
    if level < levels[config.level] or not (config.to_console or config.to_file) or not vim.tbl_contains(config.namespaces, namespace) then
      return
    end

    local message = format(arg, ...)
    local info = debug.getinfo(2, "nSl")
    local _, ms = uv.gettimeofday() --[[@as integer]]
    local timestamp = fmt("%s:%03d", os.date("%H:%M:%S"), ms / 1000)
    local fun_name = info.name ~= "" and info.name or "<anonymous>"
    local fmt_message = fmt("[%s] %s %s:%s:%s: %s", level_name, timestamp, info.short_src, fun_name, info.currentline, message)

    if config.to_console then
      vim.schedule(function()
        for _, m in ipairs(vim.split(fmt_message, "\n", { plain = true })) do
          m = fmt("[%s] [%s] %s", config.name, namespace, m)
          local chunk = (config.highlight and highlight) and { m, highlight } or { m }
          api.nvim_echo({ chunk }, true, {})
        end
      end)
    end
    if config.to_file then
      vim.schedule(function()
        local file = io.open(log_file, "a")
        if file then
          file:write(fmt_message .. "\n")
          file:close()
        else
          config.to_file = false
          error("Could not open log file: " .. log_file)
        end
      end)
    end
  end
end

---@param namespace string
---@return Yat.Logger
return function(namespace)
  ---@type Yat.Logger
  local logger = { config = config }

  for i, v in ipairs(config.levels) do
    local name = v.level
    logger[name] = function(arg, ...)
      return log(namespace, i, name:upper(), v.highlight, arg, ...)
    end
  end

  return logger
end

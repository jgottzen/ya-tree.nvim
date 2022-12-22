local Path = require("ya-tree.path")

local api = vim.api
local fn = vim.fn
local uv = vim.loop

---@class Yat.Logger
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

---@class Yat.Logger.Config
---@field namespaces Yat.Logger.Namespace[]
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
  local log_file = fmt("%s/%s.log", fn.stdpath("log"), config.name)
  local dir = Path:new(log_file):parent()
  if not dir:exists() then
    config.log_file = false
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
  ---@return string[]
  local function pack(...)
    local args = {}
    local list = { n = select("#", ...), ... }
    for i = 1, list.n do
      args[i] = str(list[i])
    end
    return args
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

  ---@param namespace Yat.Logger.Namespace
  ---@param level integer
  ---@param level_name Yat.Logger.Level
  ---@param highlight string
  ---@param arg any
  ---@param ... any
  log = function(namespace, level, level_name, highlight, arg, ...)
    if
      level < levels[config.level]
      or not (config.to_console or config.to_file)
      or not (config.namespaces[1] == "all" or vim.tbl_contains(config.namespaces, namespace))
    then
      return
    end

    local message = format(arg, ...)
    local info = debug.getinfo(3, "nSl")
    local _, ms = uv.gettimeofday() --[[@as integer]]
    local timestamp = fmt("%s:%03d", os.date("%H:%M:%S"), ms / 1000)
    local fun_name = info.name ~= "" and info.name or "<anonymous>"
    local fmt_message = fmt("[%s] %s %s:%s:%s: %s", level_name, timestamp, info.short_src, fun_name, info.currentline, message)

    if config.to_console then
      vim.schedule(function()
        local hl = config.highlight and highlight or nil
        for _, m in ipairs(vim.split(fmt_message, "\n", { plain = true })) do
          m = fmt("[%s] [%s] %s", config.name, namespace, m)
          api.nvim_echo({ { m, hl } }, true, {})
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

---@type table<Yat.Logger.Namespace, Yat.Logger>
local loggers = {}

return {
  ---@param level Yat.Logger.Level
  set_level = function(level)
    config.level = level
  end,

  ---@param to_console boolean
  set_log_to_console = function(to_console)
    config.to_console = to_console
  end,

  ---@param to_file boolean
  set_log_to_file = function(to_file)
    config.to_file = to_file
  end,

  ---@param namespaces Yat.Logger.Namespace[]
  set_logged_namespaces = function(namespaces)
    config.namespaces = namespaces
  end,

  ---@param namespace Yat.Logger.Namespace
  ---@return Yat.Logger
  get = function(namespace)
    local logger = loggers[namespace]
    if not logger then
      ---@type Yat.Logger
      logger = {}
      for i, v in ipairs(config.levels) do
        local name = v.level
        logger[name] = function(arg, ...)
          log(namespace, i, name:upper(), v.highlight, arg, ...)
        end
      end
      loggers[namespace] = logger
    end

    return logger
  end,
}

---@class YaTreeLogger
---@field config YaTreeLoggerConfig
local logger = {}

-- selene: allow(unused_variable)

---@param msg string
---@vararg any
---@overload fun(...)
---@diagnostic disable-next-line: unused-local, unused-vararg
function logger.trace(msg, ...) end
-- selene: allow(unused_variable)

---@param msg string
---@vararg any
---@overload fun(...)
---@diagnostic disable-next-line: unused-local, unused-vararg
function logger.debug(msg, ...) end
-- selene: allow(unused_variable)

---@param msg string
---@vararg any
---@overload fun(...)
---@diagnostic disable-next-line: unused-local, unused-vararg
function logger.info(msg, ...) end
-- selene: allow(unused_variable)

---@param msg string
---@vararg any
---@overload fun(...)
---@diagnostic disable-next-line: unused-local, unused-vararg
function logger.warn(msg, ...) end
-- selene: allow(unused_variable)

---@param msg string
---@vararg any
---@overload fun(...)
---@diagnostic disable-next-line: unused-local, unused-vararg
function logger.error(msg, ...) end

---@class YaTreeLoggerConfig
---@field level "'trace'"|"'debug'"|"'info'"|"'warn'"|"'error'"
local default = {
  name = "ya-tree",
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

local inspect = vim.inspect
local fmt = string.format
local tbl_concat = table.concat
local tbl_insert = table.insert

---@param config? YaTreeLoggerConfig
---@return YaTreeLogger
function logger.new(config)
  config = vim.tbl_deep_extend("force", default, config or {})

  local log_file = fmt("%s/%s.log", vim.fn.stdpath("data"), config.name)
  ---@type YaTreeLogger
  local self = {
    config = config,
  }
  ---@type table<string, number>
  local levels = {}
  for k, v in ipairs(self.config.levels) do
    levels[v.level] = k
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

  ---@vararg any
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
  ---@vararg any
  ---@return string
  local function concat(arg, ...)
    local t = pack(...)
    tbl_insert(t, 1, str(arg))
    return tbl_concat(t, " ")
  end

  ---@param arg string
  ---@vararg any
  ---@return string
  local function format(arg, ...)
    if type(arg) == "string" then
      if arg:find("%%s") or arg:find("%%q") then
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

  ---@param level number
  ---@param name string
  ---@param highlight string
  ---@param arg any
  ---@vararg any
  local function log(level, name, highlight, arg, ...)
    if level < levels[config.level] or not (self.config.to_console or self.config.to_file) then
      return
    end

    local message = format(arg, ...)
    local info = debug.getinfo(2, "nSl")
    local timestamp = os.date("%H:%M:%S")
    local fmt_message = fmt("[%-6s%s] %s:%s:%s: %s", name, timestamp, info.short_src, info.name or "<anonymous>", info.currentline, message)

    if self.config.to_console then
      vim.schedule(function()
        for _, m in ipairs(vim.split(fmt_message, "\n")) do
          m = fmt("[%s] %s", config.name, m)
          local chunk = (self.config.highlight and highlight) and { m, highlight } or { m }
          vim.api.nvim_echo({ chunk }, true, {})
        end
      end)
    end
    if self.config.to_file then
      vim.schedule(function()
        local file = io.open(log_file, "a")
        if file then
          file:write(fmt_message .. "\n")
          file:close()
        else
          error("[simple-log] Could not open log file: " .. log_file)
          self.config.to_file = false
        end
      end)
    end
  end

  for k, v in ipairs(config.levels) do
    self[v.level] = function(arg, ...)
      return log(k, v.level:upper(), v.highlight, arg, ...)
    end
  end

  return self
end

return logger.new()

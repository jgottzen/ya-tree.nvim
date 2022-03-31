local Path = require("plenary.path")

local uv = vim.loop
local os_sep = Path.path.sep

local M = {}

M.os_sep = os_sep
M.os_root = Path.path.root
M.is_windows = vim.fn.has("win32") == 1 or vim.fn.has("win32unix") == 1
M.is_macos = vim.fn.has("mac") == 1 or vim.fn.has("macunix") == 1
M.is_linux = vim.fn.has("unix") == 1

---@type table<string, boolean>
local pathexts = {}
do
  local pathext = vim.env.PATHEXT or ""
  local wexe = vim.split(pathext:gsub("%.", ""), ";")
  for _, v in pairs(wexe) do
    pathexts[v] = true
  end
end

---@param extension string
---@return boolean
function M.is_windows_exe(extension)
  return pathexts[extension:upper()]
end

---@param path string
---@return boolean
function M.is_readable_file(path)
  local stat = uv.fs_stat(path)
  return stat and stat.type == "file" and uv.fs_access(path, "R")
end

---@param first string
---@param second string
---@return string path
function M.join_path(first, second)
  return string.format("%s%s%s", first, os_sep, second)
end

---@param path string
---@param root string
---@return string relative_path
function M.relative_path_for(path, root)
  return Path:new(path):make_relative(root)
end

do
  local has_notify_plugin, notify = pcall(require, "notify")

  ---@param message string message
  ---@param level? number default: vim.log.levels.INFO
  function M.notify(message, level)
    level = level or vim.log.levels.INFO
    if has_notify_plugin and notify == vim.notify then
      vim.notify(message, level, { title = "YaTree" })
    else
      vim.notify(string.format("[ya-tree] %s", message), level)
    end
  end

  ---@param message string message
  function M.warn(message)
    M.notify(message, vim.log.levels.WARN)
  end
end

return M

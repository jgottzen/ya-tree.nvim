local Path = require("plenary.path")

local api = vim.api
local fn = vim.fn
local uv = vim.loop
local os_sep = Path.path.sep

local M = {}

M.os_sep = os_sep
---@type fun(base?: string):string
M.os_root = Path.path.root
M.is_windows = fn.has("win32") == 1 or fn.has("win32unix") == 1
M.is_macos = fn.has("mac") == 1 or fn.has("macunix") == 1
M.is_linux = fn.has("unix") == 1

do
  ---@type table<string, boolean>
  local extensions = {}
  ---@type string[]
  local splits = vim.split(string.gsub(vim.env.PATHEXT or "", "%.", ""), ";")
  for _, extension in pairs(splits) do
    extensions[extension:upper()] = true
  end

  ---@param extension string
  ---@return boolean
  function M.is_windows_exe(extension)
    return extensions[extension:upper()] or false
  end
end

---@param path string
---@return boolean is_directory
function M.is_directory(path)
  local stat = uv.fs_stat(path)
  return stat and stat.type == "directory" or false
end

---@param path string
---@return boolean
function M.is_readable_file(path)
  local stat = uv.fs_stat(path)
  return stat and stat.type == "file" and uv.fs_access(path, "R") or false
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

---@return boolean is_directory, string? path
function M.get_path_from_directory_buffer()
  local bufnr = api.nvim_get_current_buf()
  local bufname = api.nvim_buf_get_name(bufnr)
  if not M.is_directory(bufname) then
    return false
  end
  local buftype = api.nvim_buf_get_option(bufnr, "filetype")
  if buftype ~= "" then
    return false
  end

  local lines = api.nvim_buf_get_lines(bufnr, 0, -1, false)
  if #lines == 0 or (#lines == 1 and lines[1] == "") then
    return true, bufname
  else
    return false
  end
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

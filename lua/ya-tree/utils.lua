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
  local pathexts = {}
  local pathext = vim.env.PATHEXT or ""
  ---@type string[]
  local wexe = vim.split(pathext:gsub("%.", ""), ";")
  for _, v in pairs(wexe) do
    pathexts[v:upper()] = true
  end

  ---@param extension string
  ---@return boolean
  function M.is_windows_exe(extension)
    return pathexts[extension:upper()] or false
  end
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

---@param bufnr? number if not specified the current buffer is used.
---@param bufname? string if not specified the current buffer is used.
---@return boolean is_directory, string? path
function M.get_path_from_directory_buffer(bufnr, bufname)
  bufnr = bufnr or api.nvim_get_current_buf()
  bufname = bufname or api.nvim_buf_get_name(bufnr)
  local stat = uv.fs_stat(bufname)
  if not stat or stat.type ~= "directory" then
    return false
  end
  local buftype = api.nvim_buf_get_option(bufnr, "filetype")
  if buftype ~= "" then
    return false
  end

  local lines = api.nvim_buf_get_lines(bufnr, 0, -1, false)
  if #lines == 0 or (#lines == 1 and lines[1] == "") then
    return true, fn.expand(bufname)
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

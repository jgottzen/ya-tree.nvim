local Path = require("plenary.path")

local api = vim.api
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
---@return string
function M.join_path(first, second)
  return string.format("%s%s%s", first, os_sep, second)
end

---@param path string
---@param root string
---@return string
function M.relative_path_for(path, root)
  return Path:new(path):make_relative(root)
end

function M.feed_esc()
  local keys = api.nvim_replace_termcodes("<ESC>", true, false, true)
  api.nvim_feedkeys(keys, "n", true)
end

do
  local prefix = "[ya-tree] "
  ---@param message string
  function M.print(message)
    print(prefix .. message)
  end

  ---@param message string
  function M.print_error(message)
    api.nvim_err_writeln(prefix .. message)
  end
end

return M

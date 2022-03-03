local Path = require("plenary.path")

local api = vim.api
local uv = vim.loop
local os_sep = Path.path.sep

local M = {}

M.os_sep = os_sep
M.os_root = Path.path.root
M.is_windows = vim.fn.has("win32") ==  1 or vim.fn.has("win32unix") ==  1
M.is_macos = vim.fn.has("mac") ==  1 or vim.fn.has("macunix") ==  1
M.is_linux = vim.fn.has("unix") ==  1

---Matching executable files in Windows.
---@param ext string
---@return boolean
local PATHEXT = vim.env.PATHEXT or ""
local wexe = vim.split(PATHEXT:gsub("%.", ""), ";")
local pathexts = {}
for _, v in pairs(wexe) do
  pathexts[v] = true
end

function M.is_windows_exe(ext)
  return pathexts[ext:upper()]
end

function M.is_readable_file(name)
  local stat = uv.fs_stat(name)
  return stat and stat.type == "file" and uv.fs_access(name, "R")
end

function M.join_path(first, second)
  return string.format("%s%s%s", first, os_sep, second)
end

function M.relative_path_for(path, root)
  return Path:new(path):make_relative(root)
end

function M.feed_esc()
  local keys = api.nvim_replace_termcodes("<ESC>", true, false, true)
  api.nvim_feedkeys(keys, "n", true)
end

local prefix = "[ya-tree] "
function M.print(message)
  print(prefix .. message)
end

function M.print_error(message)
  api.nvim_err_writeln(prefix .. message)
end

return M

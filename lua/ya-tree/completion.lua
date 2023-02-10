local fs = require("ya-tree.fs")

local M = {}

local fn = vim.fn

---@param prefix string
---@param base string
---@return string[]
function M.complete_file_and_dir(prefix, base)
  return vim.tbl_map(function(path)
    return prefix .. path
  end, fn.glob(base .. "*", false, true))
end

---@param prefix string
---@param base string
---@return string[]
function M.complete_dir(prefix, base)
  ---@type string[]
  local paths = {}
  for _, path in ipairs(fn.glob(base .. "*", false, true)) do
    if fs.is_directory(path) then
      paths[#paths + 1] = prefix .. path
    end
  end
  return paths
end

return M

local M = {}

---@type table<string, number>
local diagnostics = {}

---@param new_diagnostics table<string, number>
---@return table<string, number> previous_diagnostics
function M.set_diagnostics(new_diagnostics)
  local previous_diagnostics = diagnostics
  diagnostics = new_diagnostics
  return previous_diagnostics
end

---@param path string
---@return number|nil
function M.of(path)
  return diagnostics[path]
end

return M

local event = require("ya-tree.events.event").ya_tree
local events = require("ya-tree.events")
local Path = require("ya-tree.path")

local api = vim.api

local M = {
  ---@type table<string, Diagnostic[]>
  current_diagnostics = {},
  ---@type table<string, integer>
  current_diagnostic_severities = {},
}

---@param path string
---@return Diagnostic[]|nil
function M.diagnostics_of(path)
  return M.current_diagnostics[path]
end

---@param path string
---@return integer|nil
function M.severity_of(path)
  return M.current_diagnostic_severities[path]
end

---@param diagnostics Diagnostic[]
local function on_diagnostics_changed(diagnostics)
  ---@type table<string, Diagnostic[]>, table<string, integer>
  local new_diagnostics, new_severity_diagnostics = {}, {}
  for _, diagnostic in ipairs(diagnostics) do
    ---@diagnostic disable-next-line:undefined-field
    local bufnr = diagnostic.bufnr --[[@type integer]]
    if api.nvim_buf_is_valid(bufnr) then
      local bufname = api.nvim_buf_get_name(bufnr)
      local current = new_diagnostics[bufname]
      if not current then
        current = {}
        new_diagnostics[bufname] = current
      end
      current[#current + 1] = diagnostic

      local severity = new_severity_diagnostics[bufname]
      -- lower severity value is a higher severity...
      if not severity or diagnostic.severity < severity then
        new_severity_diagnostics[bufname] = diagnostic.severity
      end
    end
  end

  local config = require("ya-tree.config").config
  if config.diagnostics.propagate_to_parents then
    for path, severity in pairs(new_severity_diagnostics) do
      for _, parent in next, Path:new(path):parents() do
        local parent_severity = new_severity_diagnostics[parent]
        if not parent_severity or parent_severity > severity then
          new_severity_diagnostics[parent] = severity
        else
          break
        end
      end
    end
  end

  M.current_diagnostics = new_diagnostics
  local previous_diagnostics_severities = M.current_diagnostic_severities
  M.current_diagnostic_severities = new_severity_diagnostics
  local new_severity_count = vim.tbl_count(new_severity_diagnostics)
  local previous_severity_count = vim.tbl_count(previous_diagnostics_severities)

  local severity_changed = false
  if new_severity_count > 0 and previous_severity_count > 0 then
    if new_severity_count ~= previous_severity_count then
      severity_changed = true
    else
      for path, severity in pairs(new_severity_diagnostics) do
        if previous_diagnostics_severities[path] ~= severity then
          severity_changed = true
          break
        end
      end
    end
  else
    severity_changed = new_severity_count ~= previous_severity_count
  end

  events.fire_yatree_event(event.DIAGNOSTICS_CHANGED, severity_changed)
end

---@param config Yat.Config
function M.setup(config)
  if config.diagnostics.enable then
    local debounced_trailing = require("ya-tree.debounce").debounce_trailing
    local group = api.nvim_create_augroup("YaTreeDiagnostics", { clear = true })
    api.nvim_create_autocmd("DiagnosticChanged", {
      group = group,
      pattern = "*",
      callback = debounced_trailing(function(args)
        on_diagnostics_changed(args.data.diagnostics)
      end, config.diagnostics.debounce_time),
      desc = "Diagnostics handler",
    })
  end
end

return M

local Path = require("plenary.path")

local config = require("ya-tree.config").config
local ui = require("ya-tree.ui")

local api = vim.api

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

local function on_diagnostics_changed()
  local Trees = require("ya-tree.trees")

  local tabpage = api.nvim_get_current_tabpage() --[[@as integer]]
  ---@type table<string, number>
  local new_diagnostics = {}
  for _, diagnostic in ipairs(vim.diagnostic.get()) do
    local bufnr = diagnostic.bufnr
    if api.nvim_buf_is_valid(bufnr) then
      ---@type string
      local bufname = api.nvim_buf_get_name(bufnr)
      local severity = new_diagnostics[bufname]
      -- lower severity value is a higher severity...
      if not severity or diagnostic.severity < severity then
        new_diagnostics[bufname] = diagnostic.severity
      end
    end
  end

  if config.diagnostics.propagate_to_parents then
    for path, severity in pairs(new_diagnostics) do
      for _, parent in next, Path:new(path):parents() do
        ---@cast parent string
        local parent_severity = new_diagnostics[parent]
        if not parent_severity or parent_severity > severity then
          new_diagnostics[parent] = severity
        else
          break
        end
      end
    end
  end

  local previous_diagnostics = diagnostics
  diagnostics = new_diagnostics
  local tree = Trees.current_tree(tabpage)
  if tree and ui.is_open() then
    ---@type number
    local new_diagnostics_count = vim.tbl_count(new_diagnostics)
    ---@type number
    local previous_diagnostics_count = vim.tbl_count(previous_diagnostics)

    local changed = false
    if new_diagnostics_count > 0 and previous_diagnostics_count > 0 then
      if new_diagnostics_count ~= previous_diagnostics_count then
        changed = true
      else
        for path, severity in pairs(new_diagnostics) do
          if previous_diagnostics[path] ~= severity then
            changed = true
            break
          end
        end
      end
    else
      changed = new_diagnostics_count ~= previous_diagnostics_count
    end

    -- only update the ui if the diagnostics have changed
    if changed then
      ui.update(tree)
    end
  end
end

function M.setup()
  config = require("ya-tree.config").config

  local events = require("ya-tree.events")
  local event = require("ya-tree.events.event")

  local debounced_callback = require("ya-tree.debounce").debounce_trailing(function()
    if require("ya-tree.config").config.diagnostics.enable then
      on_diagnostics_changed()
    end
  end, config.diagnostics.debounce_time)
  events.on_autocmd_event(event.DIAGNOSTICS_CHANGED, "YA_TREE_DIAGNOSTICS", false, debounced_callback)
end

return M

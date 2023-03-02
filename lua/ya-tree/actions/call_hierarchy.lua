local M = {}

---@async
---@param panel Yat.Panel.CallHierarchy
function M.toggle_direction(panel)
  panel:toggle_direction()
end

---@async
---@param panel Yat.Panel.CallHierarchy
function M.create_call_hierarchy_from_buffer_position(panel)
  panel:create_from_current_buffer()
end

return M

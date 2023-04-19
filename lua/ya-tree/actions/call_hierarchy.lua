local M = {}

---@async
---@param panel Yat.Panel.CallHierarchy
---@param _ Yat.Node.CallHierarchy
function M.toggle_direction(panel, _)
  panel:toggle_direction()
end

---@async
---@param panel Yat.Panel.CallHierarchy
---@param _ Yat.Node.CallHierarchy
function M.create_call_hierarchy_from_buffer_position(panel, _)
  panel:create_from_current_buffer()
end

return M

local M = {}

---@param panel Yat.Panel.Tree
function M.close_sidebar(panel, _)
  panel.sidebar:close()
end

return M

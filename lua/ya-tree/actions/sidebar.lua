local M = {}

---@param panel Yat.Panel
function M.close_sidebar(panel)
  panel.sidebar:close()
end

return M

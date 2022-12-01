local M = {}

---@param sidebar Yat.Sidebar
function M.close_window(_, _, sidebar)
  sidebar:close()
end

return M

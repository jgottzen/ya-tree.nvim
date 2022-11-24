local help = require("ya-tree.ui.help")

local M = {}

---@param sidebar Yat.Sidebar
function M.close(_, _, sidebar)
  sidebar:close()
end

---@async
---@param tree Yat.Tree
function M.open_help(tree)
  help.open(tree.TYPE)
end

return M

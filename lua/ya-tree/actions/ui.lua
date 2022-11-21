local help = require("ya-tree.ui.help")

local M = {}

---@param context Yat.Action.FnContext
function M.close(_, _, context)
  context.sidebar:close()
end

---@async
---@param tree Yat.Tree
function M.open_help(tree)
  help.open(tree.TYPE)
end

return M

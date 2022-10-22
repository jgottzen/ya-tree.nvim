local ui = require("ya-tree.ui")

local M = {}

function M.close()
  ui.close()
end

---@param _ Yat.Tree
---@param node Yat.Node
function M.focus_parent(_, node)
  ui.focus_parent(node)
end

---@param _ Yat.Tree
---@param node Yat.Node
function M.focus_prev_sibling(_, node)
  ui.focus_prev_sibling(node)
end

---@param _ Yat.Tree
---@param node Yat.Node
function M.focus_next_sibling(_, node)
  ui.focus_next_sibling(node)
end

---@param _ Yat.Tree
---@param node Yat.Node
function M.focus_first_sibling(_, node)
  ui.focus_first_sibling(node)
end

---@param _ Yat.Tree
---@param node Yat.Node
function M.focus_last_sibling(_, node)
  ui.focus_last_sibling(node)
end

---@param _ Yat.Tree
---@param node Yat.Node
function M.focus_prev_git_item(_, node)
  ui.focus_prev_git_item(node)
end

---@param _ Yat.Tree
---@param node Yat.Node
function M.focus_next_git_item(_, node)
  ui.focus_next_git_item(node)
end

---@param _ Yat.Tree
---@param node Yat.Node
function M.focus_prev_diagnostic_item(_, node)
  ui.focus_prev_diagnostic_item(node)
end

---@param _ Yat.Tree
---@param node Yat.Node
function M.focus_next_diagnostic_item(_, node)
  ui.focus_next_diagnostic_item(node)
end

return M

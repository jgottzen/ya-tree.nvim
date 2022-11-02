local help = require("ya-tree.ui.help")
local ui = require("ya-tree.ui")

local M = {}

function M.close()
  ui.close()
end

---@async
---@param tree Yat.Tree
---@param _ Yat.Node
---@param context Yat.Action.FnContext
function M.focus_prev_tree(tree, _, context)
  local prev_tree = context.sidebar:get_previous_tree(tree)
  if prev_tree then
    ui.update(prev_tree, prev_tree.root)
  end
end

---@async
---@param tree Yat.Tree
---@param _ Yat.Node
---@param context Yat.Action.FnContext
function M.focus_next_tree(tree, _, context)
  local next_tree = context.sidebar:get_next_tree(tree)
  if next_tree then
    ui.update(next_tree, next_tree.root)
  end
end

---@async
---@param tree Yat.Tree
---@param node Yat.Node
---@param context Yat.Action.FnContext
function M.focus_parent(tree, node, context)
  if node.parent then
    local row = context.sidebar:get_row_of_node(tree, node.parent)
    if row then
      ui.focus_row(row)
    end
  end
end

---@param sidebar Yat.Sidebar
---@param tree Yat.Tree
---@param iterator fun(): integer, Yat.Node
---@param config Yat.Config
---@return integer|nil node
local function focus_first_non_hidden_node(sidebar, tree, iterator, config)
  local row = sidebar:get_first_non_hidden_node_row(iterator, tree, config)
  if row then
    ui.focus_row(row)
  end
end

---@async
---@param tree Yat.Tree
---@param node Yat.Node
---@param context Yat.Action.FnContext
function M.focus_prev_sibling(tree, node, context)
  if node.parent then
    local iterator = node.parent:iterate_children({ reverse = true, from = node })
    focus_first_non_hidden_node(context.sidebar, tree, iterator, require("ya-tree.config").config)
  end
end

---@async
---@param tree Yat.Tree
---@param node Yat.Node
---@param context Yat.Action.FnContext
function M.focus_next_sibling(tree, node, context)
  if node.parent then
    focus_first_non_hidden_node(context.sidebar, tree, node.parent:iterate_children({ from = node }), require("ya-tree.config").config)
  end
end

---@async
---@param tree Yat.Tree
---@param node Yat.Node
---@param context Yat.Action.FnContext
function M.focus_first_sibling(tree, node, context)
  if node.parent then
    focus_first_non_hidden_node(context.sidebar, tree, node.parent:iterate_children(), require("ya-tree.config").config)
  end
end

---@async
---@param tree Yat.Tree
---@param node Yat.Node
---@param context Yat.Action.FnContext
function M.focus_last_sibling(tree, node, context)
  if node.parent then
    focus_first_non_hidden_node(context.sidebar, tree, node.parent:iterate_children({ reverse = true }), require("ya-tree.config").config)
  end
end

---@async
---@param tree Yat.Tree
---@param node Yat.Node
---@param context Yat.Action.FnContext
function M.focus_prev_git_item(tree, node, context)
  local row = context.sidebar:get_prev_git_item_row(tree, node)
  if row then
    ui.focus_row(row)
  end
end

---@async
---@param tree Yat.Tree
---@param node Yat.Node
---@param context Yat.Action.FnContext
function M.focus_next_git_item(tree, node, context)
  local row = context.sidebar:get_next_git_item_row(tree, node)
  if row then
    ui.focus_row(row)
  end
end

---@async
---@param tree Yat.Tree
---@param node Yat.Node
---@param context Yat.Action.FnContext
function M.focus_prev_diagnostic_item(tree, node, context)
  local row = context.sidebar:get_prev_diagnostic_item_row(tree, node)
  if row then
    ui.focus_row(row)
  end
end

---@async
---@param tree Yat.Tree
---@param node Yat.Node
---@param context Yat.Action.FnContext
function M.focus_next_diagnostic_item(tree, node, context)
  local row = context.sidebar:get_next_diagnostic_item_row(tree, node)
  if row then
    ui.focus_row(row)
  end
end

---@async
---@param tree Yat.Tree
function M.open_help(tree)
  help.open(tree.TYPE)
end

return M

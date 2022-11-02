local scheduler = require("plenary.async.util").scheduler

local ui = require("ya-tree.ui")

local M = {}

---@async
---@param tree Yat.Tree
---@param node Yat.Node
function M.toggle_node(tree, node)
  if node:has_children() then
    if node.expanded then
      node:collapse()
    else
      node:expand()
    end
    ui.update(tree, node)
  end
end

---@async
---@param tree Yat.Tree
---@param node Yat.Node
function M.close_node(tree, node)
  if node:has_children() and node.expanded then
    node:collapse()
  else
    local parent = node.parent
    if parent then
      parent:collapse()
      node = parent
    end
  end
  ui.update(tree, node)
end

---@async
---@param tree Yat.Tree
function M.close_all_nodes(tree)
  tree.root:collapse({ recursive = true })
  ui.update(tree, tree.root)
end

---@async
---@param tree Yat.Tree
---@param node Yat.Node
function M.close_all_child_nodes(tree, node)
  if node:has_children() then
    node:collapse({ recursive = true, children_only = true })
    ui.update(tree, node)
  end
end

do
  ---@async
  ---@param node Yat.Node
  ---@param depth integer
  ---@param config Yat.Config
  local function expand(node, depth, config)
    node:expand()
    if depth < config.expand_all_nodes_max_depth then
      for _, child in node:iterate_children() do
        if child:has_children() and not child:is_hidden(config) then
          expand(child, depth + 1, config)
        end
      end
    end
  end

  ---@async
  ---@param tree Yat.Tree
  ---@param node Yat.Node
  function M.expand_all_nodes(tree, node)
    expand(tree.root, 1, require("ya-tree.config").config)
    ui.update(tree, node)
  end

  ---@async
  ---@param tree Yat.Tree
  ---@param node Yat.Node
  function M.expand_all_child_nodes(tree, node)
    if node:has_children() then
      expand(node, 1, require("ya-tree.config").config)
      ui.update(tree, node)
    end
  end
end

---@async
---@param _ Yat.Tree
---@param node Yat.Node
---@param context Yat.Action.FnContext
function M.goto_node_in_filesystem_tree(_, node, context)
  local tree = context.sidebar:filesystem_tree()
  local target_node = tree.root:expand({ to = node.path })
  scheduler()
  ui.update(tree, target_node)
end

return M

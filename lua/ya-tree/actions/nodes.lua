local scheduler = require("ya-tree.async").scheduler

local M = {}

---@async
---@param tree Yat.Tree
---@param node Yat.Node
---@param sidebar Yat.Sidebar
function M.toggle_node(tree, node, sidebar)
  if node:has_children() then
    if node.expanded then
      node:collapse()
    else
      node:expand()
    end
    sidebar:update(tree, node)
  end
end

---@async
---@param tree Yat.Tree
---@param node Yat.Node
---@param sidebar Yat.Sidebar
function M.close_node(tree, node, sidebar)
  if node:has_children() and node.expanded then
    node:collapse()
  else
    local parent = node.parent
    if parent then
      parent:collapse()
      node = parent
    end
  end
  sidebar:update(tree, node)
end

---@async
---@param tree Yat.Tree
---@param _ Yat.Node
---@param sidebar Yat.Sidebar
function M.close_all_nodes(tree, _, sidebar)
  tree.root:collapse({ recursive = true })
  sidebar:update(tree, tree.root)
end

---@async
---@param tree Yat.Tree
---@param node Yat.Node
---@param sidebar Yat.Sidebar
function M.close_all_child_nodes(tree, node, sidebar)
  if node:has_children() then
    node:collapse({ recursive = true, children_only = true })
    sidebar:update(tree, node)
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
  ---@param sidebar Yat.Sidebar
  function M.expand_all_nodes(tree, node, sidebar)
    expand(tree.root, 1, require("ya-tree.config").config)
    sidebar:update(tree, node)
  end

  ---@async
  ---@param tree Yat.Tree
  ---@param node Yat.Node
  ---@param sidebar Yat.Sidebar
  function M.expand_all_child_nodes(tree, node, sidebar)
    if node:has_children() then
      expand(node, 1, require("ya-tree.config").config)
      sidebar:update(tree, node)
    end
  end
end

---@async
---@param tree Yat.Tree
---@param node Yat.Node
---@param sidebar Yat.Sidebar
function M.focus_parent(tree, node, sidebar)
  if node.parent then
    sidebar:focus_node(tree, node.parent)
  end
end

---@param sidebar Yat.Sidebar
---@param tree Yat.Tree
---@param iterator fun(): integer, Yat.Node
local function focus_first_non_hidden_node_from_iterator(sidebar, tree, iterator)
  local config = require("ya-tree.config").config
  for _, node in iterator do
    if not node:is_hidden(config) then
      sidebar:focus_node(tree, node)
      break
    end
  end
end

---@async
---@param tree Yat.Tree
---@param node Yat.Node
---@param sidebar Yat.Sidebar
function M.focus_prev_sibling(tree, node, sidebar)
  if node.parent then
    focus_first_non_hidden_node_from_iterator(sidebar, tree, node.parent:iterate_children({ reverse = true, from = node }))
  end
end

---@async
---@param tree Yat.Tree
---@param node Yat.Node
---@param sidebar Yat.Sidebar
function M.focus_next_sibling(tree, node, sidebar)
  if node.parent then
    focus_first_non_hidden_node_from_iterator(sidebar, tree, node.parent:iterate_children({ from = node }))
  end
end

---@async
---@param tree Yat.Tree
---@param node Yat.Node
---@param sidebar Yat.Sidebar
function M.focus_first_sibling(tree, node, sidebar)
  if node.parent then
    focus_first_non_hidden_node_from_iterator(sidebar, tree, node.parent:iterate_children())
  end
end

---@async
---@param tree Yat.Tree
---@param node Yat.Node
---@param sidebar Yat.Sidebar
function M.focus_last_sibling(tree, node, sidebar)
  if node.parent then
    focus_first_non_hidden_node_from_iterator(sidebar, tree, node.parent:iterate_children({ reverse = true }))
  end
end

---@param sidebar Yat.Sidebar
---@param tree Yat.Tree
---@param start_node Yat.Node
---@param forward boolean
---@param predicate fun(node: Yat.Node): boolean
local function focus_first_node_that_matches(sidebar, tree, start_node, forward, predicate)
  local node = tree:get_first_node_that_matches(start_node, forward, predicate)
  if node then
    sidebar:focus_node(tree, node)
  end
end

---@async
---@param tree Yat.Tree
---@param start Yat.Node
---@param sidebar Yat.Sidebar
function M.focus_prev_git_item(tree, start, sidebar)
  local config = require("ya-tree.config").config
  focus_first_node_that_matches(sidebar, tree, start, false, function(node)
    return not node:is_hidden(config) and node:git_status() ~= nil
  end)
end

---@async
---@param tree Yat.Tree
---@param start Yat.Node
---@param sidebar Yat.Sidebar
function M.focus_next_git_item(tree, start, sidebar)
  local config = require("ya-tree.config").config
  focus_first_node_that_matches(sidebar, tree, start, true, function(node)
    return not node:is_hidden(config) and node:git_status() ~= nil
  end)
end

---@async
---@param sidebar Yat.Sidebar
---@param tree Yat.Tree
---@param start Yat.Node
---@param forward boolean
local function focus_diagnostic_item(sidebar, tree, start, forward)
  local config = require("ya-tree.config").config
  local directory_min_diagnostic_severity = tree.renderers.extra.directory_min_diagnostic_severity
  local file_min_diagnostic_severity = tree.renderers.extra.file_min_diagnostic_severity
  focus_first_node_that_matches(sidebar, tree, start, forward, function(node)
    if not node:is_hidden(config) then
      local severity = node:diagnostic_severity()
      if severity then
        local target_severity = node:is_directory() and directory_min_diagnostic_severity or file_min_diagnostic_severity
        return severity <= target_severity
      end
    end
    return false
  end)
end

---@async
---@param tree Yat.Tree
---@param node Yat.Node
---@param sidebar Yat.Sidebar
function M.focus_prev_diagnostic_item(tree, node, sidebar)
  focus_diagnostic_item(sidebar, tree, node, false)
end

---@async
---@param tree Yat.Tree
---@param node Yat.Node
---@param sidebar Yat.Sidebar
function M.focus_next_diagnostic_item(tree, node, sidebar)
  focus_diagnostic_item(sidebar, tree, node, true)
end

---@async
---@param _ Yat.Tree
---@param node Yat.Node
---@param sidebar Yat.Sidebar
function M.goto_node_in_filesystem_tree(_, node, sidebar)
  local tree = sidebar:filesystem_tree()
  local target_node = tree.root:expand({ to = node.path })
  scheduler()
  sidebar:update(tree, target_node)
end

return M

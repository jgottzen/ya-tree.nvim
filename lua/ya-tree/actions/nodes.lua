local lazy = require("ya-tree.lazy")

local Config = lazy.require("ya-tree.config") ---@module "ya-tree.config"

local M = {}

---@async
---@param panel Yat.Panel.Tree
---@param node Yat.Node
function M.toggle_node(panel, node)
  if node:has_children() then
    if node.expanded then
      node:collapse()
    else
      node:expand()
    end
    panel:draw(node)
  end
end

---@async
---@param panel Yat.Panel.Tree
---@param node Yat.Node
function M.close_node(panel, node)
  if node:has_children() and node.expanded then
    node:collapse()
  else
    local parent = node.parent
    if parent then
      parent:collapse()
      node = parent
    end
  end
  panel:draw(node)
end

---@async
---@param panel Yat.Panel.Tree
---@param _ Yat.Node
function M.close_all_nodes(panel, _)
  panel.root:collapse({ recursive = true })
  panel:draw(panel.root)
end

---@async
---@param panel Yat.Panel.Tree
---@param node Yat.Node
function M.close_all_child_nodes(panel, node)
  if node:has_children() then
    node:collapse({ recursive = true, children_only = true })
    panel:draw(node)
  end
end

do
  ---@async
  ---@param node Yat.Node
  ---@param depth integer
  local function expand(node, depth, config)
    node:expand()
    if depth < config.expand_all_nodes_max_depth then
      for _, child in node:iterate_children() do
        if child:has_children() and not child:is_hidden() then
          expand(child, depth + 1, config)
        end
      end
    end
  end

  ---@async
  ---@param panel Yat.Panel.Tree
  ---@param node Yat.Node
  function M.expand_all_nodes(panel, node)
    expand(panel.root, 1, Config.config)
    panel:draw(node)
  end

  ---@async
  ---@param panel Yat.Panel.Tree
  ---@param node Yat.Node
  function M.expand_all_child_nodes(panel, node)
    if node:has_children() then
      expand(node, 1, Config.config)
      panel:draw(node)
    end
  end
end

---@async
---@param panel Yat.Panel.Tree
---@param node Yat.Node
function M.focus_parent(panel, node)
  if node.parent then
    panel:focus_node(node.parent)
  end
end

---@param panel Yat.Panel.Tree
---@param iterator fun(): integer, Yat.Node
local function focus_first_non_hidden_node_from_iterator(panel, iterator)
  for _, node in iterator do
    if not node:is_hidden() then
      panel:focus_node(node)
      break
    end
  end
end

---@async
---@param panel Yat.Panel.Tree
---@param node Yat.Node
function M.focus_prev_sibling(panel, node)
  if node.parent then
    focus_first_non_hidden_node_from_iterator(panel, node.parent:iterate_children({ reverse = true, from = node }))
  end
end

---@async
---@param panel Yat.Panel.Tree
---@param node Yat.Node
function M.focus_next_sibling(panel, node)
  if node.parent then
    focus_first_non_hidden_node_from_iterator(panel, node.parent:iterate_children({ from = node }))
  end
end

---@async
---@param panel Yat.Panel.Tree
---@param node Yat.Node
function M.focus_first_sibling(panel, node)
  if node.parent then
    focus_first_non_hidden_node_from_iterator(panel, node.parent:iterate_children())
  end
end

---@async
---@param panel Yat.Panel.Tree
---@param node Yat.Node
function M.focus_last_sibling(panel, node)
  if node.parent then
    focus_first_non_hidden_node_from_iterator(panel, node.parent:iterate_children({ reverse = true }))
  end
end

---@generic T : Yat.Node
---@param panel Yat.Panel.Tree
---@param start_node T
---@param forward boolean
---@param predicate fun(node: T): boolean
local function focus_first_node_that_matches(panel, start_node, forward, predicate)
  local node = panel:get_first_node_that_matches(start_node, forward, predicate)
  if node then
    panel:focus_node(node)
  end
end

---@async
---@param panel Yat.Panel.Tree
---@param start Yat.Node.FsBasedNode
function M.focus_prev_git_item(panel, start)
  focus_first_node_that_matches(panel, start, false, function(node)
    return not node:is_hidden() and node:git_status() ~= nil
  end)
end

---@async
---@param panel Yat.Panel.Tree
---@param start Yat.Node.FsBasedNode
function M.focus_next_git_item(panel, start)
  focus_first_node_that_matches(panel, start, true, function(node)
    return not node:is_hidden() and node:git_status() ~= nil
  end)
end

---@async
---@param panel Yat.Panel.Tree
---@param start Yat.Node
---@param forward boolean
local function focus_diagnostic_item(panel, start, forward)
  local container_min_diagnostic_severity = panel:container_min_severity()
  local leaf_min_diagnostic_severity = panel:leaf_min_severity()
  focus_first_node_that_matches(panel, start, forward, function(node)
    if not node:is_hidden() then
      local severity = node:diagnostic_severity()
      if severity then
        local target_severity = node:is_container() and container_min_diagnostic_severity or leaf_min_diagnostic_severity
        return severity <= target_severity
      end
    end
    return false
  end)
end

---@async
---@param panel Yat.Panel.Tree
---@param node Yat.Node
function M.focus_prev_diagnostic_item(panel, node)
  focus_diagnostic_item(panel, node, false)
end

---@async
---@param panel Yat.Panel.Tree
---@param node Yat.Node
function M.focus_next_diagnostic_item(panel, node)
  focus_diagnostic_item(panel, node, true)
end

return M

local Nodes = require("ya-tree.nodes")
local log = require("ya-tree.log")

local api = vim.api
local uv = vim.loop

---@class YaTree
---@field cwd string the workding directory of the tabpage.
---@field refreshing boolean if the tree is currently refreshing.
---@field root YaTreeNode|YaTreeSearchNode the root of the current tree.
---@field current_node YaTreeNode the currently selected node.
---@field tree YaTreeRoot the current tree.
---@field search SearchTree the current search tree.
---@field tabpage number the current tabpage.

---@class YaTreeRoot
---@field root YaTreeNode the root fo the tree.
---@field current_node YaTreeNode the currently selected node.

---@class SearchTree
---@field result? YaTreeSearchNode the root of the search tree.
---@field current_node? YaTreeNode the currently selected node.

local M = {
  ---@private
  ---@type table<string, YaTree>
  _trees = {},
}

---@param tree YaTree
---@return string
local function tree_tostring(tree)
  return string.format("(cwd=%q, root=%q)", tree.cwd, tree.root.path)
end

---@param opts {tabpage?: number, create_if_missing?: boolean, root_path?: string}
---  - {opts.tabpage?} `number`
---  - {opts.create_if_missing?} `boolean`
---  - {opts.root_path?} `string`
---@return YaTree? tree
function M.get_tree(opts)
  opts = opts or {}
  ---@type number
  local tabpage = opts.tabpage or api.nvim_get_current_tabpage()
  local tree = M._trees[tostring(tabpage)]
  if not tree and (opts.create_if_missing or opts.root_path) then
    ---@type string
    local cwd = uv.cwd()
    ---@type string
    local root = opts.root_path or cwd
    log.debug("creating new tree data for tabpage %s with cwd %q and root %q", tabpage, cwd, root)
    local root_node = Nodes.root(root)
    tree = setmetatable({
      cwd = cwd,
      refreshing = false,
      root = root_node,
      current_node = nil,
      tree = {
        root = root_node,
        current_node = nil,
      },
      search = {
        result = nil,
        current_node = nil,
      },
      tabpage = tabpage,
    }, { __tostring = tree_tostring })
    M._trees[tostring(tabpage)] = tree
  end

  return tree
end

---@param cb fun(tree: YaTree): nil
function M.for_each_tree(cb)
  for _, tree in pairs(M._trees) do
    cb(tree)
  end
end

---@param tabpage number
function M.delete_tree(tabpage)
  M._trees[tostring(tabpage)] = nil
end

return M

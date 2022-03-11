local Nodes = require("ya-tree.nodes")
local log = require("ya-tree.log")

local api = vim.api
local uv = vim.loop

---@class YaTree
---@field cwd string the workding directory of the tabpage.
---@field root YaTreeNode the root of the tree.
---@field current_node YaTreeNode the currently selected node.
---@field search? SearchTree the current search tree.
---@field tabpage number the current tabpage.

---@class SearchTree
---@field result YaTreeSearchNode the root of the search tree.
---@field current_node YaTreeSearchNode the currently selected node.

local M = {
  ---@private
  ---@type table<number, YaTree>
  _trees = {},
}

local trees = M._trees

---@param opts {tabpage?: number, create_if_missing?: boolean, root_path?: string}
---  - {opts.tabpage?} `number`
---  - {opts.create_if_missing?} `boolean`
---  - {opts.root_path?} `string`
---@return YaTree?
function M.get_current_tree(opts)
  opts = opts or {}
  local tabpage = opts.tabpage or api.nvim_get_current_tabpage()
  local tree = trees[tabpage]
  if not tree and (opts.create_if_missing or opts.root_path) then
    ---@type string
    local cwd = uv.cwd()
    ---@type string
    local root = opts.root_path or cwd
    log.debug("creating new tree data for tabpage %s with cwd %q and root %q", tabpage, cwd, root)
    tree = {
      cwd = cwd,
      root = Nodes.root(root),
      current_node = nil,
      search = {
        result = nil,
        current_node = nil,
      },
      tabpage = tabpage,
    }
    trees[tabpage] = tree
  end

  return tree
end

---@param cb fun(tree: YaTree): nil
function M.for_each_tree(cb)
  for _, tree in pairs(trees) do
    cb(tree)
  end
end

return M

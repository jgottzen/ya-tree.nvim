local log = require("ya-tree.log")("trees")

local M = {
  ---@private
  ---@type table<Yat.Trees.Type, Yat.Tree>
  _registered_trees = {},
}

---@return Yat.Trees.Type[]
function M.get_registered_tree_types()
  return vim.tbl_keys(M._registered_trees)
end

---@async
---@param tabpage integer
---@param tree_type Yat.Trees.Type
---@param path? string
---@param kwargs? table<string, any>
---@return Yat.Tree? tree
function M.create_tree(tabpage, tree_type, path, kwargs)
  local tree = M._registered_trees[tree_type]
  if tree then
    log.debug("creating tree of type %q", tree_type)
    return tree:new(tabpage, path, kwargs)
  else
    log.info("no tree of type %q is registered", tree_type)
  end
end

---@param config Yat.Config
function M.setup(config)
  ---@type table<Yat.Actions.Name, Yat.Trees.Type[]>
  local supported_actions = {}
  for tree_name in pairs(config.trees) do
    if tree_name ~= "global_mappings" then
      ---@type boolean, Yat.Tree?
      local ok, tree = pcall(require, "ya-tree.trees." .. tree_name)
      if ok and tree and type(tree.static.setup) == "function" and type(tree.static.TYPE) == "string" and type(tree.new) == "function" then
        log.debug("registering tree %q", tree.static.TYPE)
        tree.static.setup(config)
        M._registered_trees[tree.static.TYPE] = tree

        for _, action in ipairs(tree.static.supported_actions) do
          local trees = supported_actions[action]
          if not trees then
            trees = {}
            supported_actions[action] = trees
          end
          trees[#trees + 1] = tree.static.TYPE
        end
      end
    end
  end

  ---@return table<Yat.Actions.Name, Yat.Trees.Type[]>
  function M.actions_supported_by_trees()
    return supported_actions
  end
end

return M

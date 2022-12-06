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

do
  ---@type table<Yat.Trees.Type, table<string, Yat.Action>>, table<string, table<Yat.Trees.Type, Yat.Action>>
  local tree_mappings, mappings = {}, {}

  ---@param config Yat.Config
  function M.setup(config)
    tree_mappings, mappings = {}, {}

    for tree_name in pairs(config.trees) do
      if tree_name ~= "global_mappings" then
        ---@type boolean, Yat.Tree?
        local ok, tree = pcall(require, "ya-tree.trees." .. tree_name)
        if
          ok
          and tree
          and type(tree) == "table"
          and type(tree.static) == "table"
          and type(tree.static.setup) == "function"
          and type(tree.static.TYPE) == "string"
          and type(tree.new) == "function"
        then
          if tree.static.setup(config) then
            log.debug("registered tree %q", tree.static.TYPE)
            M._registered_trees[tree.static.TYPE] = tree
            tree_mappings[tree.static.TYPE] = tree.static.keymap
          end
        end
      end
    end

    for tree_type, list in pairs(tree_mappings) do
      for key, action in pairs(list) do
        local entry = mappings[key]
        if not entry then
          entry = {}
          mappings[key] = entry
        end
        entry[tree_type] = action
      end
    end
  end

  ---@return table<Yat.Trees.Type, table<string, Yat.Action>>
  function M.tree_mappings()
    return tree_mappings
  end

  ---@return table<string, table<Yat.Trees.Type, Yat.Action>>
  function M.mappings()
    return mappings
  end
end

return M

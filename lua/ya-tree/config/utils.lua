local M = {}

---@param fn async fun(tree: Yat.Tree, node: Yat.Node)
---@param desc string
---@param modes Yat.Actions.Mode[]
---@param trees Yat.Trees.Type[]
---@return Yat.Action action
function M.create_action(fn, desc, modes, trees)
  return {
    fn = fn,
    desc = desc,
    modes = modes,
    trees = trees,
  }
end

return M

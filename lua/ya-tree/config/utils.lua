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

---@param fn Yat.Ui.RendererFunction
---@param config Yat.Config.BaseRendererConfig
---@return Yat.Ui.Renderer.Renderer renderer
function M.create_renderer(fn, config)
  return {
    fn = fn,
    config = config,
  }
end

return M

local M = {}

---@param fn Yat.Action.Fn
---@param desc string
---@param node_independent boolean
---@param modes Yat.Actions.Mode[]
---@param trees Yat.Trees.Type[]
---@return Yat.Action action
function M.create_action(fn, desc, node_independent, modes, trees)
  ---@type Yat.Action
  local action = {
    fn = fn,
    desc = desc,
    modes = modes,
    trees = trees,
    node_independent = node_independent,
  }
  return action
end

---@param fn Yat.Ui.RendererFunction
---@param config Yat.Config.BaseRendererConfig
---@return Yat.Ui.Renderer.Renderer renderer
function M.create_renderer(fn, config)
  ---@type Yat.Ui.Renderer.Renderer
  local renderer = {
    fn = fn,
    config = config,
  }
  return renderer
end

return M

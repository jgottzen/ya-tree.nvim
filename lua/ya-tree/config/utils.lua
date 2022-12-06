local M = {}

---@param fn Yat.Action.Fn
---@param desc string
---@param node_independent boolean
---@param modes Yat.Actions.Mode[]
---@return Yat.Config.Action action
function M.create_action(fn, desc, node_independent, modes)
  ---@type Yat.Config.Action
  local action = {
    fn = fn,
    desc = desc,
    modes = modes,
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

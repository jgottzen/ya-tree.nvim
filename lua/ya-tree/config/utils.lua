local M = {}

---@param fn Yat.Action.TreePanelFn The function implementing the action.
---@param desc string The description of the action.
---@param node_independent boolean Whether the action can be called without a `Yat.Node`, e.g. the `"open_help"` action.
---@param modes Yat.Actions.Mode[] Which modes the action is available in.
---@return Yat.Config.Action action
function M.create_tree_panel_action(fn, desc, node_independent, modes)
  ---@type Yat.Config.Action
  local action = {
    fn = fn,
    desc = desc,
    modes = modes,
    node_independent = node_independent,
  }
  return action
end

---@param fn Yat.Ui.RendererFunction The render function.
---@param config Yat.Config.BaseRendererConfig The renderer configuration.
---@return Yat.Ui.Renderer.Renderer renderer
function M.create_tree_panel_renderer(fn, config)
  ---@type Yat.Ui.Renderer.Renderer
  local renderer = {
    fn = fn,
    config = config,
  }
  return renderer
end

return M

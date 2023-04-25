local lazy = require("ya-tree.lazy")

local Actions = lazy.require("ya-tree.actions") ---@module "ya-tree.actions"
local Logger = lazy.require("ya-tree.log") ---@module "ya-tree.log"
local renderers = lazy.require("ya-tree.ui.renderers") ---@module "ya-tree.ui.renderers"
local utils = lazy.require("ya-tree.utils") ---@module "ya-tree.utils"

local M = {}

---@param panel_type Yat.Panel.Type
---@param mappings table<string, Yat.Actions.Name>
---@param supported_actions Yat.Actions.Name[]
---@return table<string, Yat.Action>
function M.create_mappings(panel_type, mappings, supported_actions)
  local log = Logger.get("panels")

  ---@type table<string, Yat.Action>
  local keymap = {}
  for key, name in pairs(mappings) do
    if name == "" then
      log.debug("key %q is disabled by user config", key)
    else
      local action = Actions.actions[name]
      if not action then
        log.error("key %q is mapped to 'action' %q, which doesn't exist, mapping ignored", key, name, panel_type)
        utils.warn(string.format("Key %q is mapped to 'action' %q, which doesnt' exist, mapping ignored!", key, name, panel_type))
      elseif not vim.tbl_contains(supported_actions, name) and not action.user_defined then
        log.error("key %q is mapped to 'action' %q, which panel %q doesn't support, mapping ignored", key, name, panel_type)
        utils.warn(
          string.format("Key %q is mapped to 'action' %q, which panel %q doesn't support, mapping ignored!", key, name, panel_type)
        )
      else
        if action then
          keymap[key] = action
        else
          log.debug("tree %q action %q is disabled due to dependent feature is disabled", panel_type, name)
        end
      end
    end
  end

  return keymap
end

---@class Yat.Panel.Tree.Ui.Renderer
---@field name Yat.Ui.Renderer.Name
---@field fn Yat.Ui.RendererFunction
---@field config? Yat.Config.BaseRendererConfig

---@param panel_type Yat.Panel.Type
---@param container_renderers Yat.Config.Panels.TreeRenderer[]
---@param leaf_renderers Yat.Config.Panels.TreeRenderer[]
---@return Yat.Panel.Tree.Ui.Renderer[] container_renderers
---@return Yat.Panel.Tree.Ui.Renderer[] leaf_renderers
function M.create_renderers(panel_type, container_renderers, leaf_renderers)
  local log = Logger.get("panels")

  ---@param renderer_type string
  ---@param tree_renderer Yat.Config.Panels.TreeRenderer
  ---@return Yat.Panel.Tree.Ui.Renderer|nil renderer
  local function create_renderer(renderer_type, tree_renderer)
    local name = tree_renderer.name
    if type(name) == "string" then
      local renderer_info = renderers.get_renderer(name)
      if renderer_info then
        ---@type Yat.Panel.Tree.Ui.Renderer
        local renderer = { name = name, fn = renderer_info.fn, config = vim.deepcopy(renderer_info.config) }
        if tree_renderer.override then
          for k, v in pairs(tree_renderer.override) do
            if type(k) == "string" then
              log.debug("overriding %q panel %q renderer %q config value for %q with %s", panel_type, renderer_type, renderer.name, k, v)
              renderer.config[k] = v
            end
          end
        end
        return renderer
      else
        utils.warn(string.format("No renderer with name %q found", name))
      end
    end
    utils.warn("Invalid renderer:\n" .. vim.inspect(tree_renderer))
  end

  ---@type Yat.Panel.Tree.Ui.Renderer[], Yat.Panel.Tree.Ui.Renderer[]
  local containers, leafs = {}, {}
  for _, container_renderer in ipairs(container_renderers) do
    local renderer = create_renderer("container", container_renderer)
    if renderer then
      containers[#containers + 1] = renderer
    end
  end

  for _, leaf_renderer in ipairs(leaf_renderers) do
    local renderer = create_renderer("leaf", leaf_renderer)
    if renderer then
      leafs[#leafs + 1] = renderer
    end
  end

  return containers, leafs
end

return M

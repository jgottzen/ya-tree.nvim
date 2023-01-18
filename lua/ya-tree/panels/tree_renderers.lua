local log = require("ya-tree.log").get("panels")
local utils = require("ya-tree.utils")

local M = {}

---@class Yat.Panel.Tree.Ui.Renderer
---@field name Yat.Ui.Renderer.Name
---@field fn Yat.Ui.RendererFunction
---@field config? Yat.Config.BaseRendererConfig

---@class Yat.Panel.TreeRenderers
---@field directory Yat.Panel.Tree.Ui.Renderer[]
---@field file Yat.Panel.Tree.Ui.Renderer[]

---@class Yat.Panel.Ui.Renderer
---@field name Yat.Ui.Renderer.Name
---@field fn Yat.Ui.RendererFunction
---@field config? Yat.Config.BaseRendererConfig

---@param panel_type Yat.Panel.Type
---@param panel_renderers Yat.Config.Panels.TreeRenderers
---@return Yat.Panel.TreeRenderers
function M.create_renderers(panel_type, panel_renderers)
  local renderers = require("ya-tree.ui.renderers")

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
              log.debug("overriding tree_type %s %q renderer %q config value for %q with %s", panel_type, renderer_type, renderer.name, k, v)
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

  ---@type Yat.Panel.TreeRenderers
  local tree_renderers = {
    directory = {},
    file = {},
  }
  for _, directory_renderer in ipairs(panel_renderers.directory) do
    local renderer = create_renderer("directory", directory_renderer)
    if renderer then
      tree_renderers.directory[#tree_renderers.directory + 1] = renderer
    end
  end

  for _, file_renderer in ipairs(panel_renderers.file) do
    local renderer = create_renderer("file", file_renderer)
    if renderer then
      tree_renderers.file[#tree_renderers.file + 1] = renderer
    end
  end

  return tree_renderers
end

return M

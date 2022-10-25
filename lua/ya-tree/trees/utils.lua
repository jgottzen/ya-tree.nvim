local renderers = require("ya-tree.ui.renderers")
local utils = require("ya-tree.utils")
local log = require("ya-tree.log")("trees")

local M = {}

---@param tree_type Yat.Trees.Type
---@param config Yat.Config
---@return Yat.Trees.TreeRenderers
function M.create_renderers(tree_type, config)
  ---@param renderer_type string
  ---@param raw_renderer Yat.Config.Trees.Renderer
  ---@return Yat.Trees.Ui.Renderer|nil renderer
  local function create_renderer(renderer_type, raw_renderer)
    local name = raw_renderer.name
    if type(name) == "string" then
      local renderer_info = renderers.get_renderer(name)
      if renderer_info then
        ---@type Yat.Trees.Ui.Renderer
        local renderer = { name = name, fn = renderer_info.fn, config = vim.deepcopy(renderer_info.config) }
        if raw_renderer.override then
          for k, v in pairs(raw_renderer.override) do
            if type(k) == "string" then
              log.debug("overriding tree_type %s %q renderer %q config value for %q with %s", tree_type, renderer_type, renderer.name, k, v)
              renderer.config[k] = v
            end
          end
        end
        return renderer
      end
    end
    utils.warn("Invalid renderer:\n" .. vim.inspect(raw_renderer))
  end

  local dconf = config.renderers.builtin.diagnostics
  ---@type Yat.Trees.TreeRenderers
  local tree_renderers = {
    directory = {},
    file = {},
    extra = { directory_min_diagnstic_severrity = dconf.directory_min_severity, file_min_diagnostic_severity = dconf.file_min_severity },
  }
  local tree_renderer_config = config.trees[tree_type].renderers

  for _, directory_renderer in ipairs(tree_renderer_config.directory) do
    local renderer = create_renderer("directory", directory_renderer)
    if renderer then
      tree_renderers.directory[#tree_renderers.directory + 1] = renderer
      if renderer.name == "diagnostics" then
        local renderer_config = renderer.config --[[@as Yat.Config.Renderers.Builtin.Diagnostics]]
        tree_renderers.extra.directory_min_diagnstic_severrity = renderer_config.directory_min_severity
      end
    end
  end

  for _, file_renderer in ipairs(tree_renderer_config.file) do
    local renderer = create_renderer("file", file_renderer)
    if renderer then
      tree_renderers.file[#tree_renderers.file + 1] = renderer
      if renderer.name == "diagnostics" then
        local renderer_config = renderer.config --[[@as Yat.Config.Renderers.Builtin.Diagnostics]]
        tree_renderers.extra.file_min_diagnostic_severity = renderer_config.file_min_severity
      end
    end
  end

  return tree_renderers
end

return M

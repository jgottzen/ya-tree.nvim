local ui_renderers = require("ya-tree.ui.renderers")
local utils = require("ya-tree.utils")
local log = require("ya-tree.log")("trees")

local M = {}

---@class Yat.Trees.Ui.Renderer
---@field name Yat.Ui.Renderer.Name
---@field fn Yat.Ui.RendererFunction
---@field config? Yat.Config.BaseRendererConfig

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
      local renderer_info = ui_renderers.get_renderer(name)
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
        tree_renderers.extra.directory_min_diagnostic_severity = renderer_config.directory_min_severity
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

---@param pos integer
---@param padding string
---@param text string
---@param highlight string
---@return integer end_position, string content, Yat.Ui.HighlightGroup highlight
local function line_part(pos, padding, text, highlight)
  local from = pos + #padding
  local size = #text
  local group = {
    name = highlight,
    from = from,
    to = from + size,
  }
  return group.to, string.format("%s%s", padding, text), group
end

---@param node Yat.Node
---@param context Yat.Ui.RenderContext
---@param renderers Yat.Trees.Ui.Renderer[]
---@return string text, Yat.Ui.HighlightGroup[] highlights
function M.render_node(node, context, renderers)
  ---@type string[], Yat.Ui.HighlightGroup[]
  local content, highlights, pos = {}, {}, 0

  for _, renderer in ipairs(renderers) do
    local results = renderer.fn(node, context, renderer.config)
    if results then
      for _, result in ipairs(results) do
        if result.text then
          if not result.highlight then
            log.error("renderer %s didn't return a highlight name for node %q, renderer returned %s", renderer.name, node.path, result)
          end
          pos, content[#content + 1], highlights[#highlights + 1] = line_part(pos, result.padding or "", result.text, result.highlight)
        end
      end
    end
  end

  return table.concat(content), highlights
end

return M

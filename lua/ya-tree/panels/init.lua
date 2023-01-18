local log = require("ya-tree.log").get("panels")
local utils = require("ya-tree.utils")

---@class Yat.Panel.Factory
---@field setup fun(config: Yat.Config): boolean
---@field create_panel async fun(sidebar: Yat.Sidebar, config: Yat.Config, ...: any): Yat.Panel
---@field keymap table<string, Yat.Action>

local M = {
  ---@private
  ---@type table<Yat.Panel.Type, Yat.Panel.Factory>
  _registered_panels = {},
  ---@private
  ---@type table<Yat.Panel.Type, table<string, Yat.Action>>
  _keymaps = {}
}

---@async
---@param sidebar Yat.Sidebar
---@param _type Yat.Panel.Type
---@param config Yat.Config
---@return Yat.Panel? panel
function M.create_panel(sidebar, _type, config)
  local panel = M._registered_panels[_type]
  if panel then
    log.debug("creating panel type %q", _type)
    return panel.create_panel(sidebar, config)
  else
    log.info("no panel of type %q is registered", _type)
  end
end

---@return table<Yat.Panel.Type, table<string, Yat.Action>> keymaps
function M.keymaps()
  return vim.deepcopy(M._keymaps)
end

---@param config Yat.Config
function M.setup(config)
  M._registered_panels = {}
  M._keymaps = {}
  for panel_type in pairs(config.panels) do
    if panel_type ~= "global_mappings" then
      ---@type boolean, Yat.Panel.Factory?
      local ok, panel = pcall(require, "ya-tree.panels." .. panel_type)
      if ok and type(panel) == "table" and type(panel.setup) == "function" and type(panel.create_panel) == "function" then
        if panel.setup(config) then
          log.debug("registered panel %q", panel_type)
          M._registered_panels[panel_type] = panel
          M._keymaps[panel_type] = panel.keymap
        else
          log.warn("panel %q failed to setup", panel_type)
        end
      else
        log.error("failed to require panel of type %q: %s", panel_type, panel)
        utils.warn(string.format("Panel of type %q is configured, but cannot be required", panel_type))
      end
    end
  end
end

return M

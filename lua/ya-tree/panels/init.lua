local log = require("ya-tree.log").get("panels")

---@class Yat.Panel.Factory
---@field setup fun(config: Yat.Config): boolean
---@field create_panel async fun(sidebar: Yat.Sidebar, config: Yat.Config, ...: any): Yat.Panel
---@field keymap table<string, Yat.Action>
---@field complete_command? fun(current: string, args: string[]): string[]
---@field parse_commmand_arguments? fun(args: string[]): string[]|nil

local M = {
  ---@private
  ---@type table<Yat.Panel.Type, Yat.Panel.Factory>
  _registered_panels = {},
  ---@private
  ---@type table<Yat.Panel.Type, table<string, Yat.Action>>
  _keymaps = {},
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

---@param panel_type Yat.Panel.Type
---@param current string
---@param args string[]
---@return string[]
function M.complete_command(panel_type, current, args)
  local panel = M._registered_panels[panel_type]
  if panel and panel.complete_command then
    return panel.complete_command(current, args)
  else
    return {}
  end
end

---@param panel_type Yat.Panel.Type
---@param args string[]
---@return table<string, string>|nil panel_args
function M.parse_command_arguments(panel_type, args)
  local panel = M._registered_panels[panel_type]
  if panel and panel.parse_commmand_arguments then
    return panel.parse_commmand_arguments(args)
  end
end

---@param config Yat.Config
---@param configured_panels Yat.Panel[]
---@return Yat.Panel.Type[] available_panels
function M.setup(config, configured_panels)
  M._registered_panels = {}
  M._keymaps = {}
  for panel_type in pairs(config.panels) do
    ---@cast panel_type Yat.Panel.Type
    if vim.tbl_contains(configured_panels, panel_type) then
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
        require("ya-tree.utils").warn(string.format("Panel of type %q is configured, but cannot be required", panel_type))
      end
    end
  end

  ---@param name Yat.Actions.Name
  local function remove_keymap(name)
    for _, keymap in pairs(M._keymaps) do
      for key, action in pairs(keymap) do
        if action.name == name then
          keymap[key] = nil
        end
      end
    end
  end

  local builtin = require("ya-tree.actions.builtin")
  if not M._registered_panels["buffers"] then
    remove_keymap(builtin.general.open_buffers_panel)
  end
  if not M._registered_panels["git_status"] then
    remove_keymap(builtin.general.open_git_status_panel)
  end
  if not M._registered_panels["symbols"] then
    remove_keymap(builtin.general.open_symbols_panel)
  end
  if not M._registered_panels["call_hierarchy"] then
    remove_keymap(builtin.general.open_call_hierarchy_panel)
  end

  return vim.tbl_keys(M._registered_panels)
end

return M

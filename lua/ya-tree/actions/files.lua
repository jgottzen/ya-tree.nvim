local fs = require("ya-tree.fs")
local job = require("ya-tree.job")
local log = require("ya-tree.log").get("actions")
local node_actions = require("ya-tree.actions.nodes")
local Path = require("ya-tree.path")
local scheduler = require("ya-tree.async").scheduler
local ui = require("ya-tree.ui")
local utils = require("ya-tree.utils")

local api = vim.api

local M = {}

---@alias Yat.Action.Files.Open.Mode "edit"|"vsplit"|"split"|"tabnew"

---@async
---@param panel Yat.Panel.Tree
function M.open(panel)
  local nodes = panel:get_selected_nodes()
  if #nodes == 1 then
    local node = nodes[1]
    if node:has_children() then
      node_actions.toggle_node(panel, node)
    elseif node:is_editable() then
      panel:open_node(node, "edit")
    end
  else
    for _, node in ipairs(nodes) do
      if node:is_editable() then
        panel:open_node(node, "edit")
      end
    end
  end
end

---@async
---@param panel Yat.Panel.Tree
---@param node Yat.Node
function M.vsplit(panel, node)
  if node:is_editable() then
    panel:open_node(node, "vsplit")
  end
end

---@async
---@param panel Yat.Panel.Tree
---@param node Yat.Node
function M.split(panel, node)
  if node:is_editable() then
    panel:open_node(node, "split")
  end
end

---@async
---@param panel Yat.Panel.Tree
---@param node Yat.Node
---@param focus boolean
local function preview(panel, node, focus)
  if node:is_editable() then
    local already_loaded = vim.fn.bufloaded(node.path) > 0
    panel:open_node(node, "edit")

    -- taken from nvim-tree
    if not already_loaded then
      local bufnr = api.nvim_get_current_buf()
      vim.bo.bufhidden = "delete"
      api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
        group = api.nvim_create_augroup("YaTreeRemoveBufHidden", { clear = true }),
        buffer = bufnr,
        once = true,
        callback = function()
          vim.bo.bufhidden = ""
        end,
        desc = "Clear bufhidden for edited previewed file",
      })
    end

    if not focus then
      -- a scheduler call is required here for the event loop to to update the ui state
      -- otherwise the focus will happen before the buffer is opened, and the buffer will keep the focus
      scheduler()
      panel:focus()
    end
  end
end

---@async
---@param panel Yat.Panel.Tree
---@param node Yat.Node
function M.preview(panel, node)
  preview(panel, node, false)
end

---@async
---@param panel Yat.Panel.Tree
---@param node Yat.Node
function M.preview_and_focus(panel, node)
  preview(panel, node, true)
end

---@async
---@param panel Yat.Panel.Tree
---@param node Yat.Node
function M.tabnew(panel, node)
  if node:is_editable() then
    panel:open_node(node, "tabnew")
  end
end

---@async
---@param panel Yat.Panel.Files
---@param node Yat.Node
---@param path string
local function prepare_add_rename(panel, node, path)
  local parent = Path:new(path):parent():absolute() --[[@as string]]
  if panel.root:is_ancestor_of(path) or panel.root.path == parent then
    -- expand to the parent path so the tree will detect and display the added file/directory
    if parent ~= node.path then
      panel.root:expand({ to = parent })
      vim.schedule(function()
        panel:draw()
      end)
    end
    panel.focus_path_on_fs_event = path
  end
end

---@async
---@param panel Yat.Panel.Files
---@param node Yat.Node
function M.add(panel, node)
  if not node:is_directory() then
    node = node.parent --[[@as Yat.Node]]
  end

  local title = " New file (an ending " .. utils.os_sep .. " will create a directory): "
  local path = ui.nui_input({ title = title, default = node.path .. utils.os_sep, completion = "file", width = #title + 4 })
  if not path then
    return
  elseif fs.exists(path) then
    utils.warn(string.format("%q already exists!", path))
    return
  end

  local is_directory = path:sub(-1) == utils.os_sep
  if is_directory then
    path = path:sub(1, -2)
  end

  prepare_add_rename(panel, node, path)
  local success
  if is_directory then
    success = fs.create_dir(path)
  else
    success = fs.create_file(path)
  end
  if success then
    utils.notify(string.format("Created %s %q.", is_directory and "directory" or "file", path))
  else
    panel.focus_path_on_fs_event = nil
    utils.warn(string.format("Failed to create %s %q!", is_directory and "directory" or "file", path))
  end
end

---@async
---@param panel Yat.Panel.Files|Yat.Panel.GitStatus
---@param node Yat.Node
function M.rename(panel, node)
  -- prohibit renaming the root node
  if panel.root == node then
    return
  end

  local path = ui.nui_input({ title = " New name: ", default = node.path, completion = "file" })
  if not path then
    return
  elseif fs.exists(path) then
    utils.warn(string.format("%q already exists!", path))
    return
  end

  if panel.TYPE == "files" then
    prepare_add_rename(panel --[[@as Yat.Panel.Files]], node, path)
  end
  if node.repo then
    local err = node.repo:index():move(node.path, path)
    if not err then
      utils.notify(string.format("Renamed %q to %q.", node.path, path))
      return
    end
    -- if the `git mv` failed - probably due to the file not being under version control by git,
    -- fall through to a regular fs rename
  end

  if fs.rename(node.path, path) then
    utils.notify(string.format("Renamed %q to %q.", node.path, path))
  else
    panel.focus_path_on_fs_event = nil
    utils.warn(string.format("Failed to rename %q to %q!", node.path, path))
  end
end

---@async
---@param selected_nodes Yat.Node[]
---@param root_path string
---@param confirm boolean
---@param title_prefix string
---@return Yat.Node[] nodes, Yat.Node? node_to_focus
local function get_nodes_to_delete(selected_nodes, root_path, confirm, title_prefix)
  ---@type Yat.Node[]
  local nodes = {}
  for _, node in ipairs(selected_nodes) do
    -- prohibit deleting the root node
    if node.path == root_path then
      utils.warn(string.format("Path %q is the root of the panel, skipping it.", node.path))
    else
      if confirm then
        local response = ui.select({ "Yes", "No" }, { kind = "confirmation", prompt = title_prefix .. "" .. node.path .. "?" })
        if response == "Yes" then
          nodes[#nodes + 1] = node
        end
      else
        nodes[#nodes + 1] = node
      end
    end
  end

  local config = require("ya-tree.config").config

  ---@type Yat.Node
  local node_to_focus
  local first_node = nodes[1]
  if first_node then
    for _, node in first_node.parent:iterate_children({ from = first_node, reverse = true }) do
      if node and not node:is_hidden(config) then
        node_to_focus = node
        break
      end
    end
    if not node_to_focus then
      local last_node = nodes[#nodes]
      if last_node then
        for _, node in last_node.parent:iterate_children({ from = last_node }) do
          if node and not node:is_hidden(config) then
            node_to_focus = node
            break
          end
        end
      end
    end
    if not node_to_focus then
      node_to_focus = first_node.parent
    end
  end

  return nodes, node_to_focus
end

---@async
---@param panel Yat.Panel.Files
---@param _ Yat.Node
function M.delete(panel, _)
  local nodes, node_to_focus = get_nodes_to_delete(panel:get_selected_nodes(), panel.root.path, true, "Delete")
  if #nodes == 0 then
    return
  end

  local was_deleted = false
  panel.focus_path_on_fs_event = node_to_focus and node_to_focus.path
  for _, node in ipairs(nodes) do
    local ok = node:is_directory() and fs.remove_dir(node.path) or fs.remove_file(node.path)
    if ok then
      utils.notify(string.format("Deleted %q.", node.path))
    else
      utils.warn(string.format("Failed to delete %q!", node.path))
    end
    was_deleted = ok or was_deleted
  end
  if not was_deleted then
    panel.focus_path_on_fs_event = nil
  end
end

---@async
---@param panel Yat.Panel.Files
---@param _ Yat.Node
function M.trash(panel, _)
  local trash = require("ya-tree.config").config.trash
  if not trash.enable then
    return
  end

  local nodes, node_to_focus = get_nodes_to_delete(panel:get_selected_nodes(), panel.root.path, trash.require_confirm, "Trash")
  if #nodes == 0 then
    return
  end

  ---@param node Yat.Node
  local files = vim.tbl_map(function(node)
    return node.path
  end, nodes) --[=[@as string[]]=]

  if #files > 0 then
    panel.focus_path_on_fs_event = node_to_focus and node_to_focus.path
    log.debug("trashing files %s", files)
    local code, _, stderr = job.async_run({ cmd = "trash", args = files })
    if code ~= 0 then
      panel.focus_path_on_fs_event = nil
      log.error("%q with args %s failed with code %s and message %s", "trash", files, code, stderr)
      utils.warn(string.format("Failed to trash some of the files:\n%s\n\nMessage:\n%s", table.concat(files, "\n"), stderr))
    end
  end
end

---@async
---@param _ Yat.Panel.Tree
---@param node Yat.Node
function M.system_open(_, node)
  local config = require("ya-tree.config").config
  if not config.system_open.cmd then
    utils.warn("No sytem open command set, or OS cannot be recognized!")
    return
  end

  local args = vim.deepcopy(config.system_open.args or {}) --[=[@as string[]]=]
  table.insert(args, node.absolute_link_to or node.path)
  local code, _, stderr = job.async_run({ cmd = config.system_open.cmd, args = args, detached = true })
  if code ~= 0 then
    log.error("%q with args %s failed with code %s and message %s", config.system_open.cmd, args, code, stderr)
    utils.warn(string.format("%q returned error code %q and message:\n\n%s", config.system_open.cmd, code, stderr))
  end
end

return M

local void = require("plenary.async").void
local scheduler = require("plenary.async.util").scheduler

local lib = require("ya-tree.lib")
local job = require("ya-tree.job")
local fs = require("ya-tree.filesystem")
local node_actions = require("ya-tree.actions.nodes")
local ui = require("ya-tree.ui")
local Input = require("ya-tree.ui.input")
local utils = require("ya-tree.utils")
local log = require("ya-tree.log")("actions")

local api = vim.api

local M = {}

---@alias Yat.Action.Files.Open.Mode "edit" | "vsplit" | "split" | "tabnew"

---@async
---@param tree Yat.Tree
function M.open(tree)
  local nodes = ui.get_selected_nodes()
  if #nodes == 1 then
    local node = nodes[1]
    if node:has_children() then
      node_actions.toggle_node(tree, node)
    elseif node:is_file() then
      ui.open_file(node.path, "edit")
    elseif node:node_type() == "Buffer" then
      ---@cast node Yat.Nodes.Buffer
      if node:is_terminal() then
        for _, win in ipairs(api.nvim_list_wins()) do
          if api.nvim_win_get_buf(win) == node.bufnr then
            api.nvim_set_current_win(win)
            return
          end
        end
        local id = node:toggleterm_id()
        if id then
          pcall(vim.cmd, id .. "ToggleTerm")
        end
      end
    end
  else
    for _, node in ipairs(nodes) do
      if node:is_file() then
        ui.open_file(node.path, "edit")
      end
    end
  end
end

---@async
---@param _ Yat.Tree
---@param node Yat.Node
function M.vsplit(_, node)
  if node:is_file() then
    ui.open_file(node.path, "vsplit")
  end
end

---@async
---@param _ Yat.Tree
---@param node Yat.Node
function M.split(_, node)
  if node:is_file() then
    ui.open_file(node.path, "split")
  end
end

---@async
---@param node Yat.Node
---@param focus boolean
local function preview(node, focus)
  if node:is_file() then
    local already_loaded = vim.fn.bufloaded(node.path) > 0
    ui.open_file(node.path, "edit")

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
      })
    end

    if not focus then
      -- a scheduler call is required here for the event loop to to update the ui state
      -- otherwise the focus will happen before the buffer is opened, and the buffer will keep the focus
      scheduler()
      ui.focus()
    end
  end
end

---@async
---@param _ Yat.Tree
---@param node Yat.Node
function M.preview(_, node)
  preview(node, false)
end

---@async
---@param _ Yat.Tree
---@param node Yat.Node
function M.preview_and_focus(_, node)
  preview(node, true)
end

---@async
---@param _ Yat.Tree
---@param node Yat.Node
function M.tabnew(_, node)
  if node:is_file() then
    ui.open_file(node.path, "tabnew")
  end
end

---@async
---@param tree Yat.Tree
---@param node Yat.Node
function M.add(tree, node)
  if node:is_file() then
    node = node.parent --[[@as Yat.Node]]
  end

  local border = require("ya-tree.config").config.view.popups.border
  local title = "New file (an ending " .. utils.os_sep .. " will create a directory):"
  local input = Input:new({ prompt = title, default = node.path .. utils.os_sep, completion = "file", width = #title + 4, border = border }, {
    ---@param path string
    on_submit = void(function(path)
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

      if is_directory and fs.create_dir(path) or fs.create_file(path) then
        log.debug("created %s %q", is_directory and "directory" or "file", path)
        utils.notify(string.format("Created %s %q.", is_directory and "directory" or "file", path))
        local new_node = tree.root:add_node(path)
        if new_node and new_node.repo then
          new_node.repo:refresh_status({ ignored = true })
        end
        scheduler()
        tree.root:expand({ to = path })
        ui.update(tree, new_node)
      else
        log.error("failed to create %s %q", is_directory and "directory" or "file", path)
        utils.warn(string.format("Failed to create %s %q!", is_directory and "directory" or "file", path))
      end
    end),
  })
  input:open()
end

---@async
---@param tree Yat.Tree
---@param node Yat.Node
function M.rename(tree, node)
  -- prohibit renaming the root node
  if tree.root == node then
    return
  end

  local path = ui.input({ prompt = "New name:", default = node.path, completion = "file" })
  if not path then
    return
  elseif fs.exists(path) then
    utils.warn(string.format("%q already exists!", path))
    return
  end

  if fs.rename(node.path, path) then
    log.debug("renamed %q to %q", node.path, path)
    utils.notify(string.format("Renamed %q to %q.", node.path, path))
    tree.root:remove_node(node.path)
    local new_node = tree.root:add_node(path)
    if node.repo then
      node.repo:refresh_status({ ignored = true })
      if new_node and new_node.repo and new_node.repo ~= node.repo then
        new_node.repo:refresh_status({ ignored = true })
      end
    elseif new_node and new_node.repo then
      new_node.repo:refresh_status({ ignored = true })
    end
    tree.root:expand({ to = path })
    scheduler()
    ui.update(tree, new_node)
  else
    log.error("failed to rename %q to %q", node.path, path)
    utils.warn(string.format("Failed to rename %q to %q!", node.path, path))
  end
end

---@param root_path string
---@return Yat.Node[] nodes, string common_parent
local function get_nodes_to_delete(root_path)
  local nodes = ui.get_selected_nodes()

  ---@type string[]
  local parents = {}
  for i = #nodes, 1, -1 do
    local node = nodes[i]
    -- prohibit deleting the root node
    if node.path == root_path then
      utils.warn(string.format("Path %q is the root of the tree, skipping it.", node.path))
      table.remove(nodes, i)
    else
      if node.parent then
        parents[#parents + 1] = node.parent.path
      end
    end
  end
  local common_parent = utils.find_common_ancestor(parents) or (#nodes > 0 and nodes[1].path or root_path)

  return nodes, common_parent
end

---@async
---@param tree Yat.Tree
function M.delete(tree)
  ---@type table<Yat.Git.Repo, boolean>
  local repos = {}

  ---@async
  ---@param node Yat.Node
  ---@return boolean
  local function delete_node(node)
    local response = ui.select({ "Yes", "No" }, { kind = "confirmation", prompt = "Delete " .. node.path .. "?" })
    if response == "Yes" then
      local ok = node:is_directory() and fs.remove_dir(node.path) or fs.remove_file(node.path)
      if ok then
        log.debug("deleted %q", node.path)
        tree.root:remove_node(node.path)
        if node.repo then
          repos[node.repo] = true
        end
        utils.notify(string.format("Deleted %q.", node.path))
      else
        log.error("failed to delete %q", node.path)
        utils.warn(string.format("Failed to delete %q!", node.path))
      end
      return true
    else
      return false
    end
  end

  local nodes, common_parent = get_nodes_to_delete(tree.root.path)
  if #nodes == 0 then
    return
  end

  local was_deleted = false
  for _, node in ipairs(nodes) do
    was_deleted = delete_node(node) or was_deleted
  end
  if was_deleted then
    local node = tree.root:expand({ to = common_parent })
    for repo in pairs(repos) do
      repo:refresh_status({ ignored = true })
    end
    -- let the event loop catch up if there were a very large amount of files deleted
    scheduler()
    ui.update(tree, node)
  end
end

---@async
---@param tree Yat.Tree
function M.trash(tree)
  local config = require("ya-tree.config").config
  if not config.trash.enable then
    return
  end

  local nodes, common_parent = get_nodes_to_delete(tree.root.path)
  if #nodes == 0 then
    return
  end

  ---@type string[]
  local files = {}
  if config.trash.require_confirm then
    for _, node in ipairs(nodes) do
      local response = ui.select({ "Yes", "No" }, { kind = "confirmation", prompt = "Trash " .. node.path .. "?" })
      if response == "Yes" then
        files[#files + 1] = node.path
      end
    end
  else
    ---@param n Yat.Node
    files = vim.tbl_map(function(n)
      return n.path
    end, nodes) --[=[@as string[]]=]
  end

  if #files > 0 then
    log.debug("trashing files %s", files)
    job.run({ cmd = "trash", args = files, async_callback = true }, function(code, _, stderr)
      if code == 0 then
        lib.refresh_tree_and_goto_path(tree, common_parent)
      else
        log.error("%q with args %s failed with code %s and message %s", "trash", files, code, stderr)
        utils.warn(string.format("Failed to trash some of the files:\n%s\n\nMessage:\n%s", table.concat(files, "\n"), stderr))
      end
    end)
  end
end

---@async
---@param _ Yat.Tree
---@param node Yat.Node
function M.system_open(_, node)
  local config = require("ya-tree.config").config
  if not config.system_open.cmd then
    utils.warn("No sytem open command set, or OS cannot be recognized!")
    return
  end

  local args = vim.deepcopy(config.system_open.args or {}) --[=[@as string[]]=]
  table.insert(args, node.absolute_link_to or node.path)
  job.run({ cmd = config.system_open.cmd, args = args, detached = true }, function(code, _, stderr)
    if code ~= 0 then
      log.error("%q with args %s failed with code %s and message %s", config.system_open.cmd, args, code, stderr)
      utils.warn(string.format("%q returned error code %q and message:\n\n%s", config.system_open.cmd, code, stderr))
    end
  end)
end

return M

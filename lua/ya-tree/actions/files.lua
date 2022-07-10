local void = require("plenary.async.async").void
local scheduler = require("plenary.async.util").scheduler

local lib = require("ya-tree.lib")
local job = require("ya-tree.job")
local fs = require("ya-tree.filesystem")
local ui = require("ya-tree.ui")
local Input = require("ya-tree.ui.input")
local utils = require("ya-tree.utils")
local log = require("ya-tree.log")

local api = vim.api

local M = {}

---@alias cmd_mode "edit" | "vsplit" | "split" | "tabnew"

---@async
function M.open()
  local nodes = ui.get_selected_nodes()
  if #nodes == 1 then
    local node = nodes[1]
    if node:is_container() then
      lib.toggle_node(node)
    elseif node:is_file() then
      ui.open_file(node.path, "edit")
    elseif node:node_type() == "Buffer" then
      ---@cast node YaTreeBufferNode
      if node:is_terminal() then
        for _, win in ipairs(api.nvim_list_wins()) do
          if api.nvim_win_get_buf(win) == node.bufnr then
            api.nvim_set_current_win(win)
            return
          end
        end
        local id = node:get_toggleterm_id()
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
---@param node YaTreeNode
function M.vsplit(node)
  if node:is_file() then
    ui.open_file(node.path, "vsplit")
  end
end

---@async
---@param node YaTreeNode
function M.split(node)
  if node:is_file() then
    ui.open_file(node.path, "split")
  end
end

---@async
---@param node YaTreeNode
function M.preview(node)
  if node:is_file() then
    ---@type boolean
    local already_loaded = vim.fn.bufloaded(node.path) > 0
    ui.open_file(node.path, "edit")

    -- taken from nvim-tree
    if not already_loaded then
      local bufnr = api.nvim_get_current_buf()
      vim.bo.bufhidden = "delete"
      local group = api.nvim_create_augroup("YaTreeRemoveBufHidden", { clear = true })
      api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
        group = group,
        buffer = bufnr,
        once = true,
        callback = function()
          vim.bo.bufhidden = ""
        end,
      })
    end

    -- a scheduler call is required here for the event loop to to update the ui state
    -- otherwise the focus will happen before the buffer is opened, and the buffer will keep the focus
    scheduler()
    ui.focus()
  end
end

---@async
---@param node YaTreeNode
function M.tabnew(node)
  if node:is_file() then
    ui.open_file(node.path, "tabnew")
  end
end

---@async
---@param node YaTreeNode
function M.add(node)
  if node:is_file() then
    node = node.parent --[[@as YaTreeNode]]
  end

  local title = "New file (an ending " .. utils.os_sep .. " will create a directory):"
  local input = Input:new({ prompt = title, default = node.path .. utils.os_sep, completion = "file", width = #title + 4 }, {
    ---@param path string
    on_submit = void(function(path)
      if not path then
        return
      elseif fs.exists(path) then
        utils.warn(string.format("%q already exists!", path))
        return
      end

      local is_directory = vim.endswith(path, utils.os_sep)
      if is_directory then
        path = path:sub(1, -2)
      end

      if is_directory and fs.create_dir(path) or fs.create_file(path) then
        utils.notify(string.format("Created %s %q.", is_directory and "directory" or "file", path))
        lib.refresh_tree(path)
      else
        utils.warn(string.format("Failed to create %s %q!", is_directory and "directory" or "file", path))
      end
    end),
  })
  input:open()
end

---@async
---@param node YaTreeNode
function M.rename(node)
  -- prohibit renaming the root node
  if lib.is_node_root(node) then
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
    utils.notify(string.format("Renamed %q to %q.", node.path, path))
    lib.refresh_tree(path)
  else
    utils.warn(string.format("Failed to rename %q to %q!", node.path, path))
  end
end

---@return YaTreeNode[] nodes, string common_parent
local function get_nodes_to_delete()
  local nodes = ui.get_selected_nodes()
  local root_path = lib.get_root_path()

  ---@type string[]
  local parents = {}
  for index, node in ipairs(nodes) do
    -- prohibit deleting the root node
    if node.path == root_path then
      utils.warn(string.format("Path %q is the root of the tree, skipping it.", node.path))
      table.remove(nodes, index)
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
---@param node YaTreeNode
---@return boolean
local function delete_node(node)
  local response = ui.select({ "Yes", "No" }, { prompt = "Delete " .. node.path .. "?" })
  if response == "Yes" then
    local ok = node:is_directory() and fs.remove_dir(node.path) or fs.remove_file(node.path)
    if ok then
      utils.notify(string.format("Deleted %q.", node.path))
    else
      utils.warn(string.format("Failed to delete %q!", node.path))
    end
    return true
  else
    return false
  end
end

---@async
function M.delete()
  local nodes, common_parent = get_nodes_to_delete()
  if #nodes == 0 then
    return
  end

  local refresh = false
  for _, node in ipairs(nodes) do
    refresh = delete_node(node) or refresh
  end
  -- let the event loop catch up if there were a very large amount of files deleted
  scheduler()
  if refresh then
    lib.refresh_tree(common_parent)
  end
end

---@async
function M.trash()
  local config = require("ya-tree.config").config
  if not config.trash.enable then
    return
  end

  local nodes, common_parent = get_nodes_to_delete()
  if #nodes == 0 then
    return
  end

  ---@type string[]
  local files = {}
  if config.trash.require_confirm then
    for _, node in ipairs(nodes) do
      local response = ui.select({ "Yes", "No" }, { prompt = "Trash " .. node.path .. "?" })
      if response == "Yes" then
        files[#files + 1] = node.path
      end
    end
  else
    ---@param n YaTreeNode
    files = vim.tbl_map(function(n)
      return n.path
    end, nodes) --[[@as string[] ]]
  end

  if #files > 0 then
    log.debug("trashing files %s", files)
    job.run({ cmd = "trash", args = files, async_callback = true }, function(code, _, stderr)
      if code == 0 then
        lib.refresh_tree(common_parent)
      else
        log.error("%q with args %s failed with code %s and message %s", "trash", files, code, stderr)
        utils.warn(string.format("Failed to trash some of the files:\n%s\n\nMessage:\n%s", table.concat(files, "\n"), stderr))
      end
    end)
  end
end

---@async
---@param node YaTreeNode
function M.system_open(node)
  local config = require("ya-tree.config").config
  if not config.system_open.cmd then
    utils.warn("No sytem open command set, or OS cannot be recognized!")
    return
  end

  ---@type string[]
  local args = vim.deepcopy(config.system_open.args or {})
  table.insert(args, node.link_to or node.path)
  job.run({ cmd = config.system_open.cmd, args = args, detached = true }, function(code, _, stderr)
    if code ~= 0 then
      log.error("%q with args %s failed with code %s and message %s", config.system_open.cmd, args, code, stderr)
      utils.warn(string.format("%q returned error code %q and message:\n\n%s", config.system_open.cmd, code, stderr))
    end
  end)
end

return M

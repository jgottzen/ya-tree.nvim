local bit = require("plenary.bit")
local void = require("plenary.async").void
local scheduler = require("plenary.async.util").scheduler
local Path = require("plenary.path")

local lib = require("ya-tree.lib")
local job = require("ya-tree.job")
local fs = require("ya-tree.filesystem")
local ui = require("ya-tree.ui")
local Popup = require("ya-tree.ui.popup")
local hl = require("ya-tree.ui.highlights")
local Input = require("ya-tree.ui.input")
local utils = require("ya-tree.utils")
local log = require("ya-tree.log")

local api = vim.api

local M = {}

---@alias cmd_mode "edit" | "vsplit" | "split" | "tabnew"

---@async
---@param tree YaTree
function M.open(tree)
  local nodes = ui.get_selected_nodes()
  if #nodes == 1 then
    local node = nodes[1]
    if node:is_container() then
      lib.toggle_node(tree, node)
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
---@param _ YaTree
---@param node YaTreeNode
function M.vsplit(_, node)
  if node:is_file() then
    ui.open_file(node.path, "vsplit")
  end
end

---@async
---@param _ YaTree
---@param node YaTreeNode
function M.split(_, node)
  if node:is_file() then
    ui.open_file(node.path, "split")
  end
end

---@async
---@param _ YaTree
---@param node YaTreeNode
function M.preview(_, node)
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

    -- a scheduler call is required here for the event loop to to update the ui state
    -- otherwise the focus will happen before the buffer is opened, and the buffer will keep the focus
    scheduler()
    ui.focus()
  end
end

---@async
---@param _ YaTree
---@param node YaTreeNode
function M.tabnew(_, node)
  if node:is_file() then
    ui.open_file(node.path, "tabnew")
  end
end

---@async
---@param tree YaTree
---@param node YaTreeNode
function M.add(tree, node)
  if node:is_file() then
    node = node.parent --[[@as YaTreeNode]]
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

      local is_directory = vim.endswith(path, utils.os_sep)
      if is_directory then
        path = path:sub(1, -2)
      end

      if is_directory and fs.create_dir(path) or fs.create_file(path) then
        utils.notify(string.format("Created %s %q.", is_directory and "directory" or "file", path))
        scheduler()
        lib.refresh_tree_and_goto_path(tree, path)
      else
        utils.warn(string.format("Failed to create %s %q!", is_directory and "directory" or "file", path))
      end
    end),
  })
  input:open()
end

---@async
---@param tree YaTree
---@param node YaTreeNode
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
    utils.notify(string.format("Renamed %q to %q.", node.path, path))
    scheduler()
    lib.refresh_tree_and_goto_path(tree, path)
  else
    utils.warn(string.format("Failed to rename %q to %q!", node.path, path))
  end
end

---@param root_path string
---@return YaTreeNode[] nodes, string common_parent
local function get_nodes_to_delete(root_path)
  local nodes = ui.get_selected_nodes()

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
  local response = ui.select({ "Yes", "No" }, { kind = "confirmation", prompt = "Delete " .. node.path .. "?" })
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
---@param tree YaTree
function M.delete(tree)
  local nodes, common_parent = get_nodes_to_delete(tree.root.path)
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
    lib.refresh_tree_and_goto_path(tree, common_parent)
  end
end

---@async
---@param tree YaTree
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
    ---@param n YaTreeNode
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
---@param _ YaTree
---@param node YaTreeNode
function M.system_open(_, node)
  local config = require("ya-tree.config").config
  if not config.system_open.cmd then
    utils.warn("No sytem open command set, or OS cannot be recognized!")
    return
  end

  ---@type string[]
  local args = vim.deepcopy(config.system_open.args or {})
  table.insert(args, node.absolute_link_to or node.path)
  job.run({ cmd = config.system_open.cmd, args = args, detached = true }, function(code, _, stderr)
    if code ~= 0 then
      log.error("%q with args %s failed with code %s and message %s", config.system_open.cmd, args, code, stderr)
      utils.warn(string.format("%q returned error code %q and message:\n\n%s", config.system_open.cmd, code, stderr))
    end
  end)
end

do
  ---@type table<file_type, string>
  local node_type_map = {
    directory = "Directory",
    file = "File",
    link = "Symbolic Link",
    fifo = "Fifo (Named Pipe)",
    socket = "Socket",
    char = "Character Device",
    block = "Block Device",
    unknown = "Unknown",
  }

  -- taken from https://github.com/nvim-lua/plenary.nvim/blob/master/lua/plenary/scandir.lua
  local get_username, get_groupname
  do
    if jit and utils.os_sep ~= "\\" then
      local ffi = require("ffi")

      ffi.cdef([[
        typedef unsigned int __uid_t;
        typedef __uid_t uid_t;
        typedef unsigned int __gid_t;
        typedef __gid_t gid_t;

        typedef struct {
          char *pw_name;
          char *pw_passwd;
          __uid_t pw_uid;
          __gid_t pw_gid;
          char *pw_gecos;
          char *pw_dir;
          char *pw_shell;
        } passwd;

        passwd *getpwuid(uid_t uid);
      ]])

      ---@param id integer
      ---@return string username
      get_username = function(id)
        ---@diagnostic disable-next-line:undefined-field
        local struct = ffi.C.getpwuid(id)
        local name
        if struct == nil then
          name = tostring(id)
        else
          name = ffi.string(struct.pw_name)
        end
        return name
      end

      ffi.cdef([[
        typedef unsigned int __gid_t;
        typedef __gid_t gid_t;

        typedef struct {
          char *gr_name;
          char *gr_passwd;
          __gid_t gr_gid;
          char **gr_mem;
        } group;
        group *getgrgid(gid_t gid);
      ]])

      ---@param id integer
      ---@return string groupname
      get_groupname = function(id)
        ---@diagnostic disable-next-line:undefined-field
        local struct = ffi.C.getgrgid(id)
        local name
        if struct == nil then
          name = tostring(id)
        else
          name = ffi.string(struct.gr_name)
        end
        return name
      end
    else
      ---@param id integer
      ---@return string username
      get_username = function(id)
        return tostring(id)
      end

      ---@param id integer
      ---@return string groupname
      get_groupname = function(id)
        return tostring(id)
      end
    end
  end

  local permissions_tbl = { [0] = "---", "--x", "-w-", "-wx", "r--", "r-x", "rw-", "rwx" }
  local permission_hls = {
    ["-"] = hl.INFO_PERMISSION_NONE,
    r = hl.INFO_PERMISSION_READ,
    w = hl.INFO_PERMISSION_WRITE,
    x = hl.INFO_PERMISSION_EXECUTE,
  }

  ---@type integer
  local augroup = api.nvim_create_augroup("YaTreeNodeInfoPopup", { clear = true })

  ---@class NodeInfoPopup
  ---@field winid integer
  ---@field bufnr integer
  ---@field path string

  ---@type NodeInfoPopup?
  local popup = nil

  local function close_popup()
    if popup ~= nil then
      api.nvim_win_close(popup.winid, true)
      popup = nil
    end
  end

  ---@async
  ---@param node YaTreeNode
  ---@param stat uv_fs_stat
  ---@return string[] lines
  ---@return highlight_group[][] highlights
  local function create_fs_info(node, stat)
    local format_string = "%13s: %s "
    local left_column_end = 13
    local right_column_start = 15

    ---@type string[]
    local lines = {
      string.format(format_string, "Name", node.name),
      "",
      string.format(format_string, "Type", node:is_link() and "Symbolic Link" or node_type_map[node.type] or "Unknown"),
      string.format(format_string, "Location", node.parent and node.parent.path or Path:new(node.path):parent().filename),
      string.format(format_string, "Size", utils.format_size(stat.size)),
      "",
    }
    ---@type highlight_group[][]
    local highlights = {
      { { name = "Label", from = 1, to = left_column_end }, { name = "Title", from = right_column_start, to = -1 } },
      {},
      { { name = "Label", from = 1, to = left_column_end }, { name = "Type", from = right_column_start, to = -1 } },
      { { name = "Label", from = 1, to = left_column_end }, { name = "Directory", from = right_column_start, to = -1 } },
      { { name = "Label", from = 1, to = left_column_end }, { name = hl.INFO_SIZE, from = right_column_start, to = -1 } },
      {},
    }

    if node:is_link() then
      lines[#lines + 1] = string.format(format_string, "Points to", node.absolute_link_to)
      lines[#lines + 1] = ""
      local highlight = node.link_orphan and "Error" or (node:is_directory() and "Directory" or hl.FILE_NAME)
      highlights[#highlights + 1] =
        { { name = "Label", from = 1, to = left_column_end }, { name = highlight, from = right_column_start, to = -1 } }
      highlights[#highlights + 1] = {}
    end

    lines[#lines + 1] = string.format(format_string, "User", get_username(stat.uid))
    highlights[#highlights + 1] =
      { { name = "Label", from = 1, to = left_column_end }, { name = hl.INFO_USER, from = right_column_start, to = -1 } }
    lines[#lines + 1] = string.format(format_string, "Group", get_groupname(stat.gid))
    highlights[#highlights + 1] =
      { { name = "Label", from = 1, to = left_column_end }, { name = hl.INFO_GROUP, from = right_column_start, to = -1 } }

    local user_perms = bit.rshift(bit.band(fs.st_mode_masks.user_permissions_mask, stat.mode), 6)
    local group_perms = bit.rshift(bit.band(fs.st_mode_masks.group_permissions_mask, stat.mode), 3)
    local others_perms = bit.band(fs.st_mode_masks.others_permissions_mask, stat.mode)
    local permissions = string.format("%s %s %s", permissions_tbl[user_perms], permissions_tbl[group_perms], permissions_tbl[others_perms])
    lines[#lines + 1] = string.format(format_string, "Permissions", permissions)
    lines[#lines + 1] = ""
    local permission_highligts = { { name = "Label", from = 1, to = left_column_end } }
    for i = 1, #permissions do
      local permission = permissions:sub(i, i)
      permission_highligts[#permission_highligts + 1] =
        { name = permission_hls[permission] or "None", from = right_column_start - 1 + i, to = right_column_start + i }
    end
    highlights[#highlights + 1] = permission_highligts
    highlights[#highlights + 1] = {}

    lines[#lines + 1] = string.format(format_string, "Created", os.date("%Y-%m-%d %H:%M:%S", stat.birthtime.sec))
    highlights[#highlights + 1] =
      { { name = "Label", from = 1, to = left_column_end }, { name = hl.INFO_DATE, from = right_column_start, to = -1 } }
    lines[#lines + 1] = string.format(format_string, "Modified", os.date("%Y-%m-%d %H:%M:%S", stat.mtime.sec))
    highlights[#highlights + 1] =
      { { name = "Label", from = 1, to = left_column_end }, { name = hl.INFO_DATE, from = right_column_start, to = -1 } }
    lines[#lines + 1] = string.format(format_string, "Accessed", os.date("%Y-%m-%d %H:%M:%S", stat.atime.sec))
    highlights[#highlights + 1] =
      { { name = "Label", from = 1, to = left_column_end }, { name = hl.INFO_DATE, from = right_column_start, to = -1 } }

    return lines, highlights
  end

  ---@param node YaTreeBufferNode
  ---@return string[] lines
  ---@return highlight_group[][] highlights
  local function create_terminal_info(node)
    local format_string = "%5s: %s "
    local left_column_end = 5
    local right_column_start = 7

    ---@type string[]
    local lines = {
      string.format(format_string, "Name", node.name),
      "",
      string.format(format_string, "Type", "Terminal"),
      string.format(format_string, "Buf#", node.bufnr),
    }
    ---@type highlight_group[][]
    local highlights = {
      { { name = "Label", from = 1, to = left_column_end }, { name = "Title", from = right_column_start, to = -1 } },
      {},
      { { name = "Label", from = 1, to = left_column_end }, { name = "Type", from = right_column_start, to = -1 } },
      { { name = "Label", from = 1, to = left_column_end }, { name = hl.BUFFER_NUMBER, from = right_column_start, to = -1 } },
    }

    return lines, highlights
  end

  ---@async
  ---@param _ YaTree
  ---@param node YaTreeNode
  function M.show_node_info(_, node)
    if popup ~= nil then
      if node.path == popup.path then
        api.nvim_clear_autocmds({ group = augroup })
        api.nvim_set_current_win(popup.winid)
      else
        close_popup()
      end
      return
    end

    ---@type string[], highlight_group[][]
    local lines, highlight_groups
    if node:node_type() == "Buffer" and node.extension == "terminal" then
      ---@cast node YaTreeBufferNode
      if node:is_terminal() then
        lines, highlight_groups = create_terminal_info(node)
      else
        return
      end
    else
      local stat = node:fs_stat()
      scheduler()
      if not stat then
        utils.warn(string.format("Could not read filesystem data for %q", node.path))
        return
      end
      lines, highlight_groups = create_fs_info(node, stat)
    end

    ---@type NodeInfoPopup
    popup = { path = node.path }
    popup.winid, popup.bufnr = Popup.new(lines, highlight_groups)
      :close_with({ "q", "<ESC>" })
      :close_on_focus_loss()
      :on_close(function()
        popup = nil
      end)
      :open()

    api.nvim_create_autocmd("CursorMoved", {
      group = augroup,
      callback = close_popup,
      once = true,
    })
  end
end

return M

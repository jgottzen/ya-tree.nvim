local bit = require("plenary.bit")
local scheduler = require("plenary.async.util").scheduler
local Path = require("plenary.path")

local fs = require("ya-tree.filesystem")
local hl = require("ya-tree.ui.highlights")
local Popup = require("ya-tree.ui.popup")
local utils = require("ya-tree.utils")

local api = vim.api

local M = {}

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

  local augroup = api.nvim_create_augroup("YaTreeNodeInfoPopup", { clear = true }) --[[@as integer]]

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

    local user_perms = bit.band(fs.st_mode_masks.permissions_mask, bit.rshift(stat.mode, 6))
    local group_perms = bit.band(fs.st_mode_masks.permissions_mask, bit.rshift(stat.mode, 3))
    local others_perms = bit.band(fs.st_mode_masks.permissions_mask, stat.mode)
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
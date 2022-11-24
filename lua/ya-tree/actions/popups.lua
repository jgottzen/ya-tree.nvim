local bit = require("plenary.bit")
local scheduler = require("plenary.async.util").scheduler
local Path = require("plenary.path")

local fs = require("ya-tree.fs")
local hl = require("ya-tree.ui.highlights")
local Popup = require("ya-tree.ui.popup")
local utils = require("ya-tree.utils")

local api = vim.api

local M = {}

---@type table<Luv.FileType, string>
local NODE_TYPE_MAP = {
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

local PERMISSIONS_TBL = { [0] = "---", "--x", "-w-", "-wx", "r--", "r-x", "rw-", "rwx" }
local PERMISSION_HLS = {
  ["-"] = hl.INFO_PERMISSION_NONE,
  r = hl.INFO_PERMISSION_READ,
  w = hl.INFO_PERMISSION_WRITE,
  x = hl.INFO_PERMISSION_EXECUTE,
}

local augroup = api.nvim_create_augroup("YaTreeNodeInfoPopup", { clear = true })

---@class Yat.Action.Popup.NodeInfo : Yat.Ui.Popup
---@field path string

---@type Yat.Action.Popup.NodeInfo?
local popup = nil

local function close_popup()
  if popup ~= nil then
    api.nvim_win_close(popup.winid, true)
    popup = nil
  end
end

---@async
---@param node Yat.Node
---@param stat Luv.Fs.Stat
---@return string[] lines
---@return Yat.Ui.HighlightGroup[][] highlights
local function create_fs_info(node, stat)
  local format_string = "%13s: %s "
  local left_column_end = 13
  local right_column_start = 15

  local is_directory = node:is_directory() and not node:is_link()
  ---@type string[]
  local lines = {
    string.format(format_string, "Name", node.name),
    "",
    string.format(format_string, "Type", node:is_link() and "Symbolic Link" or NODE_TYPE_MAP[node:type()] or "Unknown"),
    string.format(format_string, "Location", node.parent and node.parent.path or Path:new(node.path):parent().filename),
    string.format(format_string, "Size", is_directory and "-" or utils.format_size(stat.size)),
    "",
  }
  ---@type Yat.Ui.HighlightGroup[][]
  local highlights = {
    { { name = "Label", from = 1, to = left_column_end }, { name = "Title", from = right_column_start, to = -1 } },
    {},
    { { name = "Label", from = 1, to = left_column_end }, { name = "Type", from = right_column_start, to = -1 } },
    { { name = "Label", from = 1, to = left_column_end }, { name = "Directory", from = right_column_start, to = -1 } },
    {
      { name = "Label", from = 1, to = left_column_end },
      { name = is_directory and hl.DIM_TEXT or hl.INFO_SIZE, from = right_column_start, to = -1 },
    },
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

  local user_perms = bit.band(fs.st_mode_masks.PERMISSIONS_MASK, bit.rshift(stat.mode, 6))
  local group_perms = bit.band(fs.st_mode_masks.PERMISSIONS_MASK, bit.rshift(stat.mode, 3))
  local others_perms = bit.band(fs.st_mode_masks.PERMISSIONS_MASK, stat.mode)
  local permissions = string.format("%s %s %s", PERMISSIONS_TBL[user_perms], PERMISSIONS_TBL[group_perms], PERMISSIONS_TBL[others_perms])
  lines[#lines + 1] = string.format(format_string, "Permissions", permissions)
  lines[#lines + 1] = ""
  local permission_highligts = { { name = "Label", from = 1, to = left_column_end } }
  for i = 1, #permissions do
    local permission = permissions:sub(i, i)
    permission_highligts[#permission_highligts + 1] =
      { name = PERMISSION_HLS[permission] or "None", from = right_column_start - 1 + i, to = right_column_start + i }
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

---@param node Yat.Nodes.Buffer
---@return string[] lines
---@return Yat.Ui.HighlightGroup[][] highlights
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
  ---@type Yat.Ui.HighlightGroup[][]
  local highlights = {
    { { name = "Label", from = 1, to = left_column_end }, { name = "Title", from = right_column_start, to = -1 } },
    {},
    { { name = "Label", from = 1, to = left_column_end }, { name = "Type", from = right_column_start, to = -1 } },
    { { name = "Label", from = 1, to = left_column_end }, { name = hl.BUFFER_NUMBER, from = right_column_start, to = -1 } },
  }

  return lines, highlights
end

---@async
---@param _ Yat.Tree
---@param node Yat.Node
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
    ---@cast node Yat.Nodes.Buffer
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

  popup = Popup.new(lines, highlight_groups)
    :close_with({ "q", "<ESC>" })
    :close_on_focus_loss()
    :on_close(function()
      popup = nil
    end)
    :open() --[[@as Yat.Action.Popup.NodeInfo]]
  popup.path = node.path

  api.nvim_create_autocmd("CursorMoved", {
    group = augroup,
    callback = close_popup,
    once = true,
    desc = "Auto-close popup",
  })
end

return M

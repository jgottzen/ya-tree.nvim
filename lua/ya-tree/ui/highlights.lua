local api = vim.api

local M = {
  ROOT_NAME = "YaTreeRootName",

  INDENT_MARKER = "YaTreeIndentMarker",

  DIRECTORY_ICON = "YaTreeDirectoryIcon",
  SYMBOLIC_DIRECTORY_ICON = "YaTreeSymbolicDirectoryIcon",

  DIRECTORY_NAME = "YaTreeDirectoryName",
  EMPTY_DIRECTORY_NAME = "YaTreeEmptyDirectoryName",
  SYMBOLIC_DIRECTORY_NAME = "YaTreeSymbolicDirectoryName",
  EMPTY_SYMBOLIC_DIRECTORY_NAME = "YaTreeEmptySymbolicDirectoryName",

  DEFAULT_FILE_ICON = "YaTreeDefaultFileIcon",
  SYMBOLIC_FILE_ICON = "YaTreeSymbolicFileIcon",
  FIFO_FILE_ICON = "YaTreeFifoFileIcon",
  SOCKET_FILE_ICON = "YaTreeSocketFileIcon",
  CHAR_DEVICE_FILE_ICON = "YaTreeCharDeviceFileIcon",
  BLOCK_DEVICE_FILE_ICON = "YaTreeBlockDeviceFileIcon",

  FILE_NAME = "YaTreeFileName",
  SYMBOLIC_FILE_NAME = "YaTreeSymbolicFileName",
  FIFO_FILE_NAME = "YaTreeFifoFileName",
  SOCKET_FILE_NAME = "YaTreeSocketFileName",
  CHAR_DEVICE_FILE_NAME = "YaTreeCharDeviceFileName",
  BLOCK_DEVICE_FILE_NAME = "YaTreeBlockDeviceFileName",
  EXECUTABLE_FILE_NAME = "YaTreeExecutableFileName",
  OPENED_FILE_NAME = "YaTreeOpenedFileName",
  ERROR_FILE_NAME = "YaTreeErrorFileName",

  MODIFIED = "YaTreeFileModified",

  SYMBOLIC_LINK = "YaTreeSymbolicLink",

  BUFFER_NUMBER = "YaTreeBufferNumber",
  BUFFER_HIDDEN = "YaTreeBufferHidden",

  CLIPBOARD_STATUS = "YaTreeClipboardStatus",

  TEXT = "YaTreeText",
  DIM_TEXT = "YaTreeDimText",
  SEARCH_TERM = "YaTreeSearchTerm",

  NORMAL = "YaTreeNormal",
  NORMAL_NC = "YaTreeNormalNC",
  CURSOR_LINE = "YaTreeCursorLine",
  VERTICAL_SPLIT = "YaTreeVertSplit",
  STATUS_LINE = "YaTreeStatusLine",
  STATUS_LINE_NC = "YaTreeStatusLineNC",

  GIT_REPO_TOPLEVEL = "YaTreeGitRepoToplevel",
  GIT_UNMERGED_COUNT = "YaTreeGitUnmergedCount",
  GIT_STASH_COUNT = "YaTreeGitStashCount",
  GIT_AHEAD_COUNT = "YaTreeGitAheadCount",
  GIT_BEHIND_COUNT = "YaTreeGitBehindCound",
  GIT_STAGED_COUNT = "YaTreeGitStagedCount",
  GIT_UNSTAGED_COUNT = "YaTreeGitUnstagedCount",
  GIT_UNTRACKED_COUNT = "YaTreeGitUntrackedCount",

  GIT_STAGED = "YaTreeGitStaged",
  GIT_DIRTY = "YaTreeGitDirty",
  GIT_NEW = "YaTreeGitNew",
  GIT_MERGE = "YaTreeGitMerge",
  GIT_RENAMED = "YaTreeGitRenamed",
  GIT_DELETED = "YaTreeGitDeleted",
  GIT_IGNORED = "YaTreeGitIgnored",
  GIT_UNTRACKED = "YaTreeGitUntracked",

  INFO_SIZE = "YaTreeInfoSize",
  INFO_USER = "YaTreeInfoUser",
  INFO_GROUP = "YaTreeInfoGroup",
  INFO_PERMISSION_NONE = "YaTreeInfoPermissionNone",
  INFO_PERMISSION_READ = "YaTreeInfoPermissionRead",
  INFO_PERMISSION_WRITE = "YaTreeInfoPermissionWrite",
  INFO_PERMISSION_EXECUTE = "YaTreeInfoPermissionExecute",
  INFO_DATE = "YaTreeInfoDate",
}

---@param name string
---@param links? string[]
---@param highlight? {fg: string, bg?: string, bold?: boolean, italic?: boolean}
---@param fallback? string
local function create_highlight(name, links, highlight, fallback)
  if links then
    for _, link in ipairs(links) do
      local ok = pcall(api.nvim_get_hl_by_name, link, true)
      if ok then
        api.nvim_set_hl(0, name, { default = true, link = link })
        return
      end
    end
    if not fallback then
      api.nvim_set_hl(0, name, { default = true, link = links[1] })
      return
    else
      highlight = { fg = fallback, default = true }
    end
  end

  ---@cast highlight table<string, any>
  highlight.default = true
  api.nvim_set_hl(0, name, highlight)
end

function M.setup()
  create_highlight(M.ROOT_NAME, nil, { fg = "#ddc7a1", bold = true })

  create_highlight(M.INDENT_MARKER, nil, { fg = "#5a524c" })

  create_highlight(M.DIRECTORY_ICON, { "Directory" })
  create_highlight(M.SYMBOLIC_DIRECTORY_ICON, { M.DIRECTORY_ICON })

  create_highlight(M.DIRECTORY_NAME, { "Directory" })
  create_highlight(M.SYMBOLIC_DIRECTORY_NAME, { M.DIRECTORY_NAME })
  create_highlight(M.EMPTY_DIRECTORY_NAME, { M.DIRECTORY_NAME })
  create_highlight(M.EMPTY_SYMBOLIC_DIRECTORY_NAME, { M.DIRECTORY_NAME })

  create_highlight(M.DEFAULT_FILE_ICON, { "Normal" })
  create_highlight(M.SYMBOLIC_FILE_ICON, { M.SYMBOLIC_FILE_ICON })
  create_highlight(M.FIFO_FILE_ICON, nil, { fg = "#af0087" })
  create_highlight(M.SOCKET_FILE_ICON, nil, { fg = "#ff005f" })
  create_highlight(M.CHAR_DEVICE_FILE_ICON, nil, { fg = "#87d75f" })
  create_highlight(M.BLOCK_DEVICE_FILE_ICON, nil, { fg = "#5f87d7" })

  create_highlight(M.FILE_NAME, { "Normal" })
  create_highlight(M.SYMBOLIC_FILE_NAME, { M.FILE_NAME })
  create_highlight(M.FIFO_FILE_NAME, { M.FIFO_FILE_ICON })
  create_highlight(M.SOCKET_FILE_NAME, { M.SOCKET_FILE_ICON })
  create_highlight(M.CHAR_DEVICE_FILE_NAME, { M.CHAR_DEVICE_FILE_ICON })
  create_highlight(M.BLOCK_DEVICE_FILE_NAME, { M.BLOCK_DEVICE_FILE_ICON })
  create_highlight(M.EXECUTABLE_FILE_NAME, { M.FILE_NAME })
  create_highlight(M.OPENED_FILE_NAME, { "TSKeyword" }, nil, "#d3869b")
  create_highlight(M.ERROR_FILE_NAME, nil, { fg = "#080808", bg = "#ff0000" })

  create_highlight(M.MODIFIED, nil, { fg = "#cb8327", bold = true })

  create_highlight(M.SYMBOLIC_LINK, nil, { fg = "#7daea3", italic = true })

  create_highlight(M.BUFFER_NUMBER, { "SpecialChar" })
  create_highlight(M.BUFFER_HIDDEN, { "WarningMsg" })

  create_highlight(M.CLIPBOARD_STATUS, { "Comment" })

  create_highlight(M.TEXT, { "Normal" })
  create_highlight(M.DIM_TEXT, { "Comment" })
  create_highlight(M.SEARCH_TERM, { "SpecialChar" })

  create_highlight(M.NORMAL, { "Normal" })
  create_highlight(M.NORMAL_NC, { "NormalNC" })
  create_highlight(M.CURSOR_LINE, { "CursorLine" })
  create_highlight(M.VERTICAL_SPLIT, { "VertSplit" })
  create_highlight(M.STATUS_LINE, { "StatusLine" })
  create_highlight(M.STATUS_LINE_NC, { "StatusLineNC" })

  create_highlight(M.GIT_REPO_TOPLEVEL, { "Character" }, nil, "#a9b665")
  create_highlight(M.GIT_UNMERGED_COUNT, { "GitSignsDelete", "GitGutterDelete" }, nil, "#ea6962")
  create_highlight(M.GIT_STASH_COUNT, { "Character" }, nil, "#a9b665")
  create_highlight(M.GIT_AHEAD_COUNT, { "Character" }, nil, "#a9b665")
  create_highlight(M.GIT_BEHIND_COUNT, { "Character" }, nil, "#a9b665")
  create_highlight(M.GIT_STAGED_COUNT, { "Type" }, nil, "#d8a657")
  create_highlight(M.GIT_UNSTAGED_COUNT, { "Type" }, nil, "#d8a657")
  create_highlight(M.GIT_UNTRACKED_COUNT, { "Title" }, nil, "#7daea3")

  create_highlight(M.GIT_STAGED, { "Character" }, nil, "#a9b665")
  create_highlight(M.GIT_DIRTY, { "GitSignsChange", "GitGutterChange" }, nil, "#cb8327")
  create_highlight(M.GIT_NEW, { "GitSignsAdd", "GitGutterAdd" }, nil, "#6f8352")
  create_highlight(M.GIT_MERGE, { "Statement" }, nil, "#d3869b")
  create_highlight(M.GIT_RENAMED, { "Title" }, nil, "#7daea3")
  create_highlight(M.GIT_DELETED, { "GitSignsDelete", "GitGutterDelete" }, nil, "#ea6962")
  create_highlight(M.GIT_IGNORED, { "Comment" })
  create_highlight(M.GIT_UNTRACKED, { "Type" }, nil, "#d8a657")

  create_highlight(M.INFO_SIZE, { "TelescopePreviewSize" })
  create_highlight(M.INFO_USER, { "TelescopePreviewUser" })
  create_highlight(M.INFO_GROUP, { "TelescopePreviewGroup" })
  create_highlight(M.INFO_PERMISSION_NONE, { "TelescopePreviewHyphen" })
  create_highlight(M.INFO_PERMISSION_READ, { "TelescopePreviewRead" })
  create_highlight(M.INFO_PERMISSION_WRITE, { "TelescopePreviewWrite" })
  create_highlight(M.INFO_PERMISSION_EXECUTE, { "TelescopePreviewExecute" })
  create_highlight(M.INFO_DATE, { "TelescopePreviewDate" })
end

return M

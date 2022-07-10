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

  FILE_NAME = "YaTreeFileName",
  SYMBOLIC_FILE_NAME = "YaTreeSymbolicFileName",
  EXECUTABLE_FILE_NAME = "YaTreeExecutableFileName",
  OPENED_FILE_NAME = "YaTreeOpenedFileName",

  SYMBOLIC_LINK = "YaTreeSymbolicLink",

  BUFFER_NUMBER = "YaTreeBufferNumber",
  BUFFER_HIDDEN = "YaTreeBufferHidden",

  CLIPBOARD_STATUS = "YaTreeClipboardStatus",

  TEXT = "YaTreeText",
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
}

---@type table<string, string>
local hl_links = {
  [M.DIRECTORY_ICON] = "Directory",
  [M.SYMBOLIC_DIRECTORY_ICON] = M.DIRECTORY_ICON,
  [M.DIRECTORY_NAME] = "Directory",
  [M.SYMBOLIC_DIRECTORY_NAME] = M.DIRECTORY_NAME,
  [M.EMPTY_DIRECTORY_NAME] = M.DIRECTORY_NAME,
  [M.EMPTY_SYMBOLIC_DIRECTORY_NAME] = M.DIRECTORY_NAME,
  [M.FILE_NAME] = "Normal",
  [M.SYMBOLIC_FILE_NAME] = M.FILE_NAME,
  [M.EXECUTABLE_FILE_NAME] = M.FILE_NAME,
  [M.BUFFER_NUMBER] = "SpecialChar",
  [M.BUFFER_HIDDEN] = "WarningMsg",
  [M.CLIPBOARD_STATUS] = "Comment",
  [M.TEXT] = "Comment",
  [M.SEARCH_TERM] = "SpecialChar",

  [M.NORMAL] = "Normal",
  [M.NORMAL_NC] = "NormalNC",
  [M.CURSOR_LINE] = "CursorLine",
  [M.VERTICAL_SPLIT] = "VertSplit",
  [M.STATUS_LINE] = "StatusLine",
  [M.STATUS_LINE_NC] = "StatusLineNC",

  [M.GIT_IGNORED] = "Comment",
}

---@param name string
---@param link? string
---@param highlight? {fg: string, bg?: string, bold?: boolean, italic?: boolean}
local function create_highlight(name, link, highlight)
  if link then
    api.nvim_set_hl(0, name, { default = true, link = link })
  else
    highlight.default = true
    ---@cast highlight table<string, any>
    api.nvim_set_hl(0, name, highlight)
  end
end

---@param number number
---@return string
local function dec_to_hex(number)
  return string.format("%06x", number)
end

---@param names string[]
---@param fallback string
---@return string
local function get_foreground_color_from_hl(names, fallback)
  for _, name in ipairs(names) do
    local success, group = pcall(api.nvim_get_hl_by_name, name, true)
    if success and group.foreground then
      return "#" .. dec_to_hex(group.foreground)
    end
  end

  return fallback
end

---@return table<string, {fg: string, bold?: boolean, italic?: boolean}>
local function get_groups()
  local git_add_fg = get_foreground_color_from_hl({ "GitSignsAdd", "GitGutterAdd" }, "#6f8352")
  local git_change_fg = get_foreground_color_from_hl({ "GitSignsChange", "GitGutterChange" }, "#cb8327")
  local git_delete_fg = get_foreground_color_from_hl({ "GitSignsDelete", "GitGutterDelete" }, "#ea6962")
  local title_fg = get_foreground_color_from_hl({ "Title" }, "#7daea3")
  local character_fg = get_foreground_color_from_hl({ "Character" }, "#a9b665")
  local type_fg = get_foreground_color_from_hl({ "Type" }, "#d8a657")

  return {
    [M.ROOT_NAME] = { fg = "#ddc7a1", bold = true },

    [M.INDENT_MARKER] = { fg = "#5a524c" },

    [M.OPENED_FILE_NAME] = { fg = get_foreground_color_from_hl({ "TSKeyword" }, "#d3869b") },

    [M.SYMBOLIC_LINK] = { fg = get_foreground_color_from_hl({ "TSInclude" }, "#7daea3"), italic = true },

    [M.GIT_REPO_TOPLEVEL] = { fg = character_fg },
    [M.GIT_UNMERGED_COUNT] = { fg = git_delete_fg },
    [M.GIT_STASH_COUNT] = { fg = character_fg },
    [M.GIT_AHEAD_COUNT] = { fg = character_fg },
    [M.GIT_BEHIND_COUNT] = { fg = character_fg },
    [M.GIT_STAGED_COUNT] = { fg = type_fg },
    [M.GIT_UNSTAGED_COUNT] = { fg = type_fg },
    [M.GIT_UNTRACKED_COUNT] = { fg = title_fg },

    [M.GIT_STAGED] = { fg = character_fg },
    [M.GIT_DIRTY] = { fg = git_change_fg },
    [M.GIT_NEW] = { fg = git_add_fg },
    [M.GIT_MERGE] = { fg = get_foreground_color_from_hl({ "Statement" }, "#d3869b") },
    [M.GIT_RENAMED] = { fg = title_fg },
    [M.GIT_DELETED] = { fg = git_delete_fg },
    [M.GIT_UNTRACKED] = { fg = type_fg },
  }
end

function M.setup()
  for name, group in pairs(get_groups()) do
    create_highlight(name, nil, group)
  end

  for name, link in pairs(hl_links) do
    create_highlight(name, link)
  end
end

return M

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

  SYMBOLIC_LINK = "YaTreeSymbolicLink",

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
  GIT_STAGED = "YaTreeGitStaged",
  GIT_DIRTY = "YaTreeGitDirty",
  GIT_NEW = "YaTreeGitNew",
  GIT_MERGE = "YaTreeGitMerge",
  GIT_RENAMED = "YaTreeGitRenamed",
  GIT_DELETED = "YaTreeGitDeleted",
  GIT_IGNORED = "YaTreeGitIgnored",
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
---@param highlight {fg: string, bg?: string, gui?: string}
local function create_highlight(name, link, highlight)
  if link then
    api.nvim_command("hi def link " .. name .. " " .. link)
  else
    local fg = highlight.fg and ("guifg=" .. highlight.fg .. "") or ""
    local bg = highlight.bg and ("guibg=" .. highlight.bg .. "") or ""
    local gui = highlight.gui and ("gui=" .. highlight.gui .. "") or ""
    api.nvim_command("hi def " .. name .. " " .. gui .. " " .. fg .. " " .. bg)
  end
end

---@param name string
---@param fallback string
---@return string
local function get_color_from_hl(name, fallback)
  local ok, id = pcall(vim.fn.hlID, name)
  if not ok or not id then
    return fallback
  end

  local fg = vim.fn.synIDattr(vim.fn.synIDtrans(id), "fg")
  if not fg or fg == "" then
    return fallback
  end

  return fg
end

---@return table<"'red'"|"'green'"|"'yellow'"|"'blue'"|"'purple'"|"'cyan'"|"'dark_red'"|"'orange'", string>
local function get_colors()
  return {
    red = vim.g.terminal_color_1 or get_color_from_hl("Identifier", "Red"),
    green = vim.g.terminal_color_2 or get_color_from_hl("Character", "Green"),
    yellow = vim.g.terminal_color_3 or get_color_from_hl("PreProc", "Yellow"),
    blue = vim.g.terminal_color_4 or get_color_from_hl("Include", "Blue"),
    purple = vim.g.terminal_color_5 or get_color_from_hl("Define", "Purple"),
    cyan = vim.g.terminal_color_6 or get_color_from_hl("Conditional", "Cyan"),
    dark_red = vim.g.terminal_color_9 or get_color_from_hl("Keyword", "DarkRed"),
    orange = vim.g.terminal_color_11 or get_color_from_hl("Number", "Orange"),
  }
end

---@return table<string, {fg: string, gui?: string}>
local function get_groups()
  local colors = get_colors()

  return {
    [M.ROOT_NAME] = { fg = colors.purple, gui = "bold,italic" },

    [M.INDENT_MARKER] = { fg = "#5a524c" },
    [M.SYMBOLIC_LINK] = { fg = colors.blue, gui = "italic" },

    [M.GIT_REPO_TOPLEVEL] = { fg = colors.red },
    [M.GIT_STAGED] = { fg = colors.green },
    [M.GIT_DIRTY] = { fg = colors.orange },
    [M.GIT_NEW] = { fg = colors.yellow },
    [M.GIT_MERGE] = { fg = colors.purple },
    [M.GIT_RENAMED] = { fg = colors.cyan },
    [M.GIT_DELETED] = { fg = colors.red },
  }
end

function M.setup()
  for k, v in pairs(get_groups()) do
    create_highlight(k, nil, v)
  end

  for k, v in pairs(hl_links) do
    create_highlight(k, v)
  end
end

return M

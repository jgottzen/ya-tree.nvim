---@type boolean
local icons_availble
---@type fun(filename: string, extension: string, opts?: {default?: boolean}): string, string
local get_icon
do
  local icons
  icons_availble, icons = pcall(require, "nvim-web-devicons")
  if icons_availble then
    get_icon = icons.get_icon
  end
end

local hl = require("ya-tree.ui.highlights")
local utils = require("ya-tree.utils")

local fn = vim.fn

local M = {
  helpers = {},
}

---@class RenderResult
---@field padding string
---@field text string
---@field highlight string

---@type table<number, boolean>
local marker_at = {}

---@param node YaTreeNode
---@param _ YaTreeConfig
---@param renderer YaTreeConfig.Renderers.Indentation
---@return RenderResult?
function M.indentation(node, _, renderer)
  if node.depth == 0 then
    return
  end

  local text = ""
  if renderer.use_marker then
    marker_at[node.depth] = not node.last_child
    for i = 1, node.depth do
      local marker = (i == node.depth and node.last_child) and renderer.last_indent_marker or renderer.indent_marker

      if marker_at[i] or i == node.depth then
        text = text .. marker .. " "
      else
        text = text .. "  "
      end
    end
  else
    text = string.rep("  ", node.depth)
  end

  return {
    padding = renderer.padding,
    text = text,
    highlight = hl.INDENT_MARKER,
  }
end

---@param node YaTreeNode
---@param _ YaTreeConfig
---@param renderer YaTreeConfig.Renderers.Icon
---@return RenderResult?
function M.icon(node, _, renderer)
  if node.depth == 0 then
    return
  end

  ---@type string
  local icon, highlight
  if node:is_directory() then
    local custom_icon = renderer.directory.custom[node.name]
    if custom_icon then
      icon = custom_icon
      highlight = node:is_link() and hl.SYMBOLIC_DIRECTORY_ICON or hl.DIRECTORY_ICON
    else
      if node:is_link() then
        icon = node.expanded and renderer.directory.symlink_expanded or renderer.directory.symlink
        highlight = hl.SYMBOLIC_DIRECTORY_ICON
      else
        if node.expanded then
          icon = node:is_empty() and renderer.directory.empty_expanded or renderer.directory.expanded
        else
          icon = node:is_empty() and renderer.directory.empty or renderer.directory.default
        end
        highlight = hl.DIRECTORY_ICON
      end
    end
  else
    if icons_availble then
      if node:is_link() then
        if node.link_name and node.link_extension then
          icon, highlight = get_icon(node.link_name, node.link_extension)
        else
          icon = renderer.file.symlink and renderer.file.symlink or renderer.file.default
          highlight = renderer.file.symlink and hl.SYMBOLIC_FILE_ICON or hl.DEFAULT_FILE_ICON
        end
      else
        icon, highlight = get_icon(node.name, node.extension)
      end

      -- if the icon lookup didn't return anything use the defaults
      if not icon then
        icon = renderer.file.default
      end
      if not highlight then
        highlight = hl.DEFAULT_FILE_ICON
      end
    else
      icon = (node:is_link() and renderer.file.symlink) and renderer.file.symlink or renderer.file.default
      highlight = (node:is_link() and renderer.file.symlink) and hl.SYMBOLIC_FILE_ICON or hl.DEFAULT_FILE_ICON
    end
  end

  return {
    padding = renderer.padding,
    text = icon,
    highlight = highlight,
  }
end

---@param node YaTreeSearchNode
---@param _ YaTreeConfig
---@param renderer YaTreeConfig.Renderers.Filter
---@return RenderResult[]?
function M.filter(node, _, renderer)
  if node.search_term then
    return {
      {
        padding = renderer.padding,
        text = "Find ",
        highlight = hl.TEXT,
      },
      {
        padding = "",
        text = string.format("%q", node.search_term),
        highlight = hl.SEARCH_TERM,
      },
      {
        padding = "",
        text = " in ",
        highlight = hl.TEXT,
      },
    }
  end
end

---@param node YaTreeNode
---@param config YaTreeConfig
---@param renderer YaTreeConfig.Renderers.Name
---@return RenderResult
function M.name(node, config, renderer)
  if node.depth == 0 then
    local text = fn.fnamemodify(node.path, renderer.root_folder_format)

    return {
      padding = "",
      text = text,
      highlight = hl.ROOT_NAME,
    }
  end

  ---@type string
  local highlight
  if renderer.use_git_status_colors then
    local git_status = node:get_git_status()
    if git_status then
      highlight = M.helpers.get_git_status_highlight(git_status)
    end
  end

  if renderer.highlight_open_file and node:is_file() and fn.bufloaded(node.path) > 0 then
    highlight = hl.OPENED_FILE_NAME
  end

  if not highlight then
    if node:is_link() then
      highlight = hl.SYMBOLIC_LINK
    elseif node:is_directory() then
      highlight = hl.DIRECTORY_NAME
    elseif node:is_file() then
      highlight = hl.FILE_NAME
    end

    if config.git.show_ignored then
      if node:is_git_ignored() then
        highlight = hl.GIT_IGNORED
      end
    end
  end

  local name = node.name
  if renderer.trailing_slash and node:is_directory() then
    name = name .. utils.os_sep
  end

  return {
    padding = renderer.padding,
    text = name,
    highlight = highlight,
  }
end

---@param node YaTreeNode
---@param _ YaTreeConfig
---@param renderer YaTreeConfig.Renderers.Repository
---@return RenderResult[]?
function M.repository(node, _, renderer)
  if node:is_git_repository_root() or (node.depth == 0 and node.repo) then
    ---@type GitRepo
    local repo = node.repo
    local icon = renderer.icons.remote.default
    if repo.remote_url then
      for k, v in pairs(renderer.icons.remote) do
        if k ~= "default" then
          if repo.remote_url:find(k, 1, true) then
            icon = v
            break
          end
        end
      end
    end

    ---@type RenderResult[]
    local result = { {
      padding = renderer.padding,
      text = icon .. " ",
      highlight = hl.GIT_REPO_TOPLEVEL,
    } }

    if renderer.show_status then
      if repo.behind > 0 then
        result[#result + 1] = {
          padding = renderer.padding,
          text = renderer.icons.behind .. repo.behind,
          highlight = hl.GIT_BEHIND_COUNT,
        }
      end
      if repo.ahead > 0 then
        result[#result + 1] = {
          padding = repo.behind and "" or renderer.padding,
          text = renderer.icons.ahead .. repo.ahead,
          highlight = hl.GIT_AHEAD_COUNT,
        }
      end
      if repo.stashed > 0 then
        result[#result + 1] = {
          padding = renderer.padding,
          text = renderer.icons.stashed .. repo.stashed,
          highlight = hl.GIT_STASH_COUNT,
        }
      end
      if repo.unmerged > 0 then
        result[#result + 1] = {
          padding = renderer.padding,
          text = renderer.icons.unmerged .. repo.unmerged,
          highlight = hl.GIT_UNMERGED_COUNT,
        }
      end
      if repo.staged > 0 then
        result[#result + 1] = {
          padding = renderer.padding,
          text = renderer.icons.staged .. repo.staged,
          highlight = hl.GIT_STAGED_COUNT,
        }
      end
      if repo.unstaged > 0 then
        result[#result + 1] = {
          padding = renderer.padding,
          text = renderer.icons.unstaged .. repo.unstaged,
          highlight = hl.GIT_UNSTAGED_COUNT,
        }
      end
      if repo.untracked > 0 then
        result[#result + 1] = {
          padding = renderer.padding,
          text = renderer.icons.untracked .. repo.untracked,
          highlight = hl.GIT_UNTRACKED_COUNT,
        }
      end
    end

    return result
  end
end

---@param node YaTreeNode
---@param _ YaTreeConfig
---@param renderer YaTreeConfig.Renderers.SymlinkTarget
---@return RenderResult?
function M.symlink_target(node, _, renderer)
  if node:is_link() then
    return {
      padding = renderer.padding,
      text = renderer.arrow_icon .. " " .. node.link_to,
      highlight = hl.SYMBOLIC_LINK,
    }
  end
end

---@param node YaTreeNode
---@param config YaTreeConfig
---@param renderer YaTreeConfig.Renderers.GitStatus
---@return RenderResult[]?
function M.git_status(node, config, renderer)
  if config.git.enable then
    local git_status = node:get_git_status()
    if git_status then
      ---@type RenderResult[]
      local result = {}
      local icons_and_hl = M.helpers.get_git_icons_and_highlights(git_status)
      if icons_and_hl then
        for _, v in ipairs(icons_and_hl) do
          result[#result + 1] = {
            padding = renderer.padding,
            text = v.icon,
            highlight = v.highlight,
          }
        end
      end

      return result
    end
  end
end

---@param node YaTreeNode
---@param config YaTreeConfig
---@param renderer YaTreeConfig.Renderers.Diagnostics
---@return RenderResult
function M.diagnostics(node, config, renderer)
  if config.diagnostics.enable then
    local severity = node:get_diagnostics_severity()
    if severity then
      if renderer.min_severity == nil or severity <= renderer.min_severity then
        local diagnostic = M.helpers.get_diagnostic_icon_and_highligt(severity)
        if diagnostic then
          return {
            padding = renderer.padding,
            text = diagnostic.text,
            highlight = diagnostic.highlight,
          }
        end
      end
    end
  end
end

---@param node YaTreeNode
---@param _ YaTreeConfig
---@param renderer YaTreeConfig.Renderers.Clipboard
---@return RenderResult
function M.clipboard(node, _, renderer)
  if node.clipboard_status then
    return {
      padding = renderer.padding,
      text = "(" .. node.clipboard_status .. ")",
      highlight = hl.CLIPBOARD_STATUS,
    }
  end
end

do
  ---@type table<string, string>
  local git_staus_to_hl

  ---@param status string
  ---@return string
  function M.helpers.get_git_status_highlight(status)
    return git_staus_to_hl[status]
  end

  ---@class IconAndHighlight
  ---@field icon string
  ---@field highlight string

  ---@class GitIconsAndHighLights
  ---@field dirty IconAndHighlight[]
  ---@field staged IconAndHighlight[]
  ---@field [string] IconAndHighlight[]
  local git_icons_and_hl

  ---@param status string
  ---@return IconAndHighlight[]
  function M.helpers.get_git_icons_and_highlights(status)
    return git_icons_and_hl[status] or git_icons_and_hl.dirty
  end

  ---@class TextAndHighlight
  ---@field text string
  ---@field highlight string

  ---@type table<number, TextAndHighlight>
  local diagnostic_icon_and_hl

  ---@param severity number
  ---@return TextAndHighlight
  function M.helpers.get_diagnostic_icon_and_highligt(severity)
    return diagnostic_icon_and_hl[severity]
  end

  ---@param config YaTreeConfig
  function M.setup(config)
    local icons = config.renderers.git_status.icons
    ---@type GitIconsAndHighLights
    git_icons_and_hl = {}

    git_icons_and_hl["M."] = { { icon = icons.staged, highlight = hl.GIT_STAGED } }
    git_icons_and_hl["MM"] = { { icon = icons.staged, highlight = hl.GIT_STAGED }, { icon = icons.modified, highlight = hl.GIT_DIRTY } }
    git_icons_and_hl["MT"] = { { icon = icons.staged, highlight = hl.GIT_STAGED }, { icon = icons.type_changed, highlight = hl.GIT_DIRTY } }
    git_icons_and_hl["MD"] = { { icon = icons.staged, highlight = hl.GIT_STAGED }, { icon = icons.deleted, highlight = hl.GIT_DIRTY } }

    git_icons_and_hl["T."] = { { icon = icons.type_changed, highlight = hl.GIT_STAGED } }
    git_icons_and_hl["TM"] = {
      { icon = icons.type_changed, highlight = hl.GIT_STAGED },
      { icon = icons.modified, highlight = hl.GIT_DIRTY },
    }
    git_icons_and_hl["TT"] = {
      { icon = icons.type_changed, highlight = hl.GIT_STAGED },
      { icon = icons.type_changed, highlight = hl.GIT_DIRTY },
    }
    git_icons_and_hl["TD"] = {
      { icon = icons.type_changed, highlight = hl.GIT_STAGED },
      { icon = icons.deleted, highlight = hl.GIT_DIRTY },
    }

    git_icons_and_hl["A."] = { { icon = icons.added, highlight = hl.GIT_STAGED } }
    git_icons_and_hl["AM"] = { { icon = icons.added, highlight = hl.GIT_STAGED }, { icon = icons.modified, highlight = hl.GIT_DIRTY } }
    git_icons_and_hl["AT"] = { { icon = icons.added, highlight = hl.GIT_STAGED }, { icon = icons.type_changed, highlight = hl.GIT_DIRTY } }
    git_icons_and_hl["AD"] = { { icon = icons.added, highlight = hl.GIT_STAGED }, { icon = icons.deleted, highlight = hl.GIT_DIRTY } }

    git_icons_and_hl["D."] = { { icon = icons.deleted, highlight = hl.GIT_STAGED } }

    git_icons_and_hl["R."] = { { icon = icons.renamed, highlight = hl.GIT_STAGED } }
    git_icons_and_hl["RM"] = { { icon = icons.renamed, highlight = hl.GIT_STAGED }, { icon = icons.modified, highlight = hl.GIT_DIRTY } }
    git_icons_and_hl["RT"] = {
      { icon = icons.renamed, highlight = hl.GIT_STAGED },
      { icon = icons.type_changed, highlight = hl.GIT_DIRTY },
    }
    git_icons_and_hl["RD"] = { { icon = icons.renamed, highlight = hl.GIT_STAGED }, { icon = icons.deleted, highlight = hl.GIT_DIRTY } }

    git_icons_and_hl["C."] = { { icon = icons.copied, highlight = hl.GIT_STAGED } }
    git_icons_and_hl["CM"] = { { icon = icons.copied, highlight = hl.GIT_STAGED }, { icon = icons.modified, highlight = hl.GIT_DIRTY } }
    git_icons_and_hl["CT"] = { { icon = icons.copied, highlight = hl.GIT_STAGED }, { icon = icons.type_changed, highlight = hl.GIT_DIRTY } }
    git_icons_and_hl["CD"] = { { icon = icons.copied, highlight = hl.GIT_STAGED }, { icon = icons.deleted, highlight = hl.GIT_DIRTY } }

    git_icons_and_hl[".A"] = { { icon = icons.added, highlight = hl.GIT_NEW } }
    git_icons_and_hl[".M"] = { { icon = icons.modified, highlight = hl.GIT_DIRTY } }
    git_icons_and_hl[".T"] = { { icon = icons.type_changed, highlight = hl.GIT_DIRTY } }
    git_icons_and_hl[".D"] = { { icon = icons.deleted, highlight = hl.GIT_DELETED } }
    git_icons_and_hl[".R"] = { { icon = icons.renamed, highlight = hl.GIT_RENAMED } }

    git_icons_and_hl["DD"] = {
      { icon = icons.unmerged, highlight = hl.GIT_MERGE },
      { icon = icons.merge.both, highlight = hl.GIT_DELETED },
    }
    git_icons_and_hl["DU"] = { { icon = icons.unmerged, highlight = hl.GIT_MERGE }, { icon = icons.merge.us, highlight = hl.GIT_DELETED } }
    git_icons_and_hl["UD"] = {
      { icon = icons.unmerged, highlight = hl.GIT_MERGE },
      { icon = icons.merge.them, highlight = hl.GIT_DELETED },
    }

    git_icons_and_hl["AA"] = { { icon = icons.unmerged, highlight = hl.GIT_MERGE }, { icon = icons.merge.both, highlight = hl.GIT_NEW } }
    git_icons_and_hl["AU"] = { { icon = icons.unmerged, highlight = hl.GIT_MERGE }, { icon = icons.merge.us, highlight = hl.GIT_NEW } }
    git_icons_and_hl["UA"] = { { icon = icons.unmerged, highlight = hl.GIT_MERGE }, { icon = icons.merge.them, highlight = hl.GIT_NEW } }

    git_icons_and_hl["UU"] = { { icon = icons.unmerged, highlight = hl.GIT_MERGE }, { icon = icons.merge.both, highlight = hl.GIT_DIRTY } }

    git_icons_and_hl["!"] = { { icon = icons.ignored, highlight = hl.GIT_IGNORED } }
    git_icons_and_hl["?"] = { { icon = icons.untracked, highlight = hl.GIT_UNTRACKED } }

    git_icons_and_hl.dirty = { { icon = icons.modified, highlight = hl.GIT_DIRTY } }
    git_icons_and_hl.staged = { { icon = icons.staged, highlight = hl.GIT_STAGED } }

    git_staus_to_hl = {}
    for k, v in pairs(git_icons_and_hl) do
      if #v == 1 then
        git_staus_to_hl[k] = v[1].highlight
      elseif #v == 2 then
        git_staus_to_hl[k] = v[2].highlight
      end
    end

    ---@type table<number, TextAndHighlight>
    diagnostic_icon_and_hl = {}

    ---@type table<number, string[]>
    local map = {}
    map[vim.diagnostic.severity.ERROR] = { "Error", "Error" }
    map[vim.diagnostic.severity.WARN] = { "Warn", "Warning" }
    map[vim.diagnostic.severity.INFO] = { "Info", "Information" }
    map[vim.diagnostic.severity.HINT] = { "Hint", "Hint" }
    for k, v in pairs(map) do
      local sign = fn.sign_getdefined("DiagnosticSign" .. v[1])
      sign = sign and sign[1]
      if sign then
        diagnostic_icon_and_hl[k] = {
          text = sign.text,
          highlight = sign.texthl,
        }
      else
        diagnostic_icon_and_hl[k] = {
          text = v[2]:sub(1, 1),
          highlight = "LspDiagnosticsDefault" .. v[2],
        }
      end
    end
  end
end

return M

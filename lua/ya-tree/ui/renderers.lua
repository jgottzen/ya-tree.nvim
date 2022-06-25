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

---@class RenderingContext
---@field view_mode YaTreeCanvasViewMode
---@field config YaTreeConfig

---@class RenderResult
---@field padding string
---@field text string
---@field highlight string

do
  ---@type table<number, boolean>
  local marker_at = {}

  ---@param node YaTreeNode
  ---@param _ RenderingContext
  ---@param renderer YaTreeConfig.Renderers.Indentation
  ---@return RenderResult? result
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
end

---@param node YaTreeNode
---@param _ RenderingContext
---@param renderer YaTreeConfig.Renderers.Icon
---@return RenderResult? result
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

---@param node YaTreeNode|YaTreeSearchNode
---@param context RenderingContext
---@param renderer YaTreeConfig.Renderers.Name
---@return RenderResult[] results
function M.name(node, context, renderer)
  if node.depth == 0 then
    local text = fn.fnamemodify(node.path, renderer.root_folder_format)
    if text:sub(-1) ~= utils.os_sep then
      text = text .. utils.os_sep
    end
    ---@type RenderResult
    local root = {
      padding = "",
      text = text,
      highlight = hl.ROOT_NAME,
    }

    ---@type RenderResult[]
    local results
    if context.view_mode == "search" and node.search_term then
      results = {
        {
          padding = "",
          text = 'Find "',
          highlight = hl.TEXT,
        },
        {
          padding = "",
          text = node.search_term,
          highlight = hl.SEARCH_TERM,
        },
        {
          padding = "",
          text = '" in: ',
          highlight = hl.TEXT,
        },
        root,
      }
    elseif context.view_mode == "buffers" then
      results = {
        {
          padding = "",
          text = "Buffers: ",
          highlight = hl.TEXT,
        },
        root,
      }
    elseif context.view_mode == "git_status" and node.repo then
      results = {
        {
          padding = "",
          text = "Git Status: ",
          highlight = hl.TEXT,
        },
        {
          padding = "",
          text = fn.fnamemodify(node.repo.toplevel, renderer.root_folder_format),
          highlight = hl.ROOT_NAME,
        },
      }
    else
      results = { root }
    end

    return results
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

    if context.config.git.show_ignored then
      if node:is_git_ignored() then
        highlight = hl.GIT_IGNORED
      end
    end
  end

  local name = node.name
  if renderer.trailing_slash and node:is_directory() then
    name = name .. utils.os_sep
  end

  return { {
    padding = renderer.padding,
    text = name,
    highlight = highlight,
  } }
end

---@param node YaTreeNode
---@param _ RenderingContext
---@param renderer YaTreeConfig.Renderers.Repository
---@return RenderResult[]? results
function M.repository(node, _, renderer)
  if node:is_git_repository_root() or (node.depth == 0 and node.repo) then
    local repo = node.repo
    ---@cast repo -?
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
    local results = { {
      padding = renderer.padding,
      text = icon .. " ",
      highlight = hl.GIT_REPO_TOPLEVEL,
    } }

    if renderer.show_status then
      if repo.behind > 0 and renderer.icons.behind ~= "" then
        results[#results + 1] = {
          padding = renderer.padding,
          text = renderer.icons.behind .. repo.behind,
          highlight = hl.GIT_BEHIND_COUNT,
        }
      end
      if repo.ahead > 0 and renderer.icons.ahead ~= "" then
        results[#results + 1] = {
          padding = repo.behind and "" or renderer.padding,
          text = renderer.icons.ahead .. repo.ahead,
          highlight = hl.GIT_AHEAD_COUNT,
        }
      end
      if repo.stashed > 0 and renderer.icons.stashed ~= "" then
        results[#results + 1] = {
          padding = renderer.padding,
          text = renderer.icons.stashed .. repo.stashed,
          highlight = hl.GIT_STASH_COUNT,
        }
      end
      if repo.unmerged > 0 and renderer.icons.unmerged ~= "" then
        results[#results + 1] = {
          padding = renderer.padding,
          text = renderer.icons.unmerged .. repo.unmerged,
          highlight = hl.GIT_UNMERGED_COUNT,
        }
      end
      if repo.staged > 0 and renderer.icons.staged ~= "" then
        results[#results + 1] = {
          padding = renderer.padding,
          text = renderer.icons.staged .. repo.staged,
          highlight = hl.GIT_STAGED_COUNT,
        }
      end
      if repo.unstaged > 0 and renderer.icons.unstaged ~= "" then
        results[#results + 1] = {
          padding = renderer.padding,
          text = renderer.icons.unstaged .. repo.unstaged,
          highlight = hl.GIT_UNSTAGED_COUNT,
        }
      end
      if repo.untracked > 0 and renderer.icons.untracked ~= "" then
        results[#results + 1] = {
          padding = renderer.padding,
          text = renderer.icons.untracked .. repo.untracked,
          highlight = hl.GIT_UNTRACKED_COUNT,
        }
      end
    end

    return results
  end
end

---@param node YaTreeNode
---@param _ RenderingContext
---@param renderer YaTreeConfig.Renderers.SymlinkTarget
---@return RenderResult? result
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
---@param context RenderingContext
---@param renderer YaTreeConfig.Renderers.GitStatus
---@return RenderResult[]? results
function M.git_status(node, context, renderer)
  if context.config.git.enable then
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
---@param context RenderingContext
---@param renderer YaTreeConfig.Renderers.Diagnostics
---@return RenderResult? result
function M.diagnostics(node, context, renderer)
  if context.config.diagnostics.enable then
    local severity = node:get_diagnostics_severity()
    if severity and (renderer.min_severity == nil or severity <= renderer.min_severity) then
      local diagnostic = M.helpers.get_diagnostic_icon_and_highligt(severity)
      if diagnostic then
        return {
          padding = renderer.padding,
          text = diagnostic.icon,
          highlight = diagnostic.highlight,
        }
      end
    end
  end
end

---@param node YaTreeNode
---@param _ RenderingContext
---@param renderer YaTreeConfig.Renderers.BufferNumber
---@return RenderResult? result
function M.buffer_number(node, _, renderer)
  local bufnr = -1
  if node:node_type() == "Buffer" then
    ---@cast node YaTreeBufferNode
    bufnr = node.bufnr or -1
  elseif fn.bufloaded(node.path) > 0 then
    bufnr = fn.bufnr(node.path)
  end

  if bufnr > 0 then
    return {
      padding = renderer.padding,
      text = "#" .. bufnr,
      highlight = hl.BUFFER_NUMBER,
    }
  end
end

---@param node YaTreeNode
---@param _ RenderingContext
---@param renderer YaTreeConfig.Renderers.Clipboard
---@return RenderResult? result
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
  local git_staus_to_hl = {}

  ---@param status string
  ---@return string
  function M.helpers.get_git_status_highlight(status)
    return git_staus_to_hl[status]
  end

  ---@class IconAndHighlight
  ---@field icon string
  ---@field highlight string

  ---@type table<string, IconAndHighlight[]>
  local git_icons_and_hl = {}

  ---@param status string
  ---@return IconAndHighlight[]
  function M.helpers.get_git_icons_and_highlights(status)
    return git_icons_and_hl[status] or git_icons_and_hl.dirty
  end

  ---@type table<number, IconAndHighlight>
  local diagnostic_icon_and_hl = {}

  ---@param severity number
  ---@return IconAndHighlight
  function M.helpers.get_diagnostic_icon_and_highligt(severity)
    return diagnostic_icon_and_hl[severity]
  end

  ---@param config YaTreeConfig
  function M.setup(config)
    local icons = config.renderers.git_status.icons
    ---@type table<string, IconAndHighlight[]>
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

    ---@type table<string, string>
    git_staus_to_hl = {}
    for k, v in pairs(git_icons_and_hl) do
      ---@cast k string
      if #v == 1 then
        git_staus_to_hl[k] = v[1].highlight
      elseif #v == 2 then
        git_staus_to_hl[k] = v[2].highlight
      end
    end

    ---@type table<number, IconAndHighlight>
    diagnostic_icon_and_hl = {}

    local map = {
      [vim.diagnostic.severity.ERROR] = { "Error", "Error" },
      [vim.diagnostic.severity.WARN] = { "Warn", "Warning" },
      [vim.diagnostic.severity.INFO] = { "Info", "Information" },
      [vim.diagnostic.severity.HINT] = { "Hint", "Hint" },
    }
    for k, v in pairs(map) do
      local sign = fn.sign_getdefined("DiagnosticSign" .. v[1])
      sign = sign[1]
      if sign then
        diagnostic_icon_and_hl[k] = {
          ---@type string
          icon = sign.text,
          ---@type string
          highlight = sign.texthl,
        }
      else
        diagnostic_icon_and_hl[k] = {
          ---@type string
          icon = v[2]:sub(1, 1),
          highlight = "LspDiagnosticsDefault" .. v[2],
        }
      end
    end
  end
end

return M

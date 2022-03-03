local icons_availble, get_icon
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
local helpers = M.helpers

local marker_at = {}
function M.indentation(node, _, renderer)
  if node.depth == 0 then
    return
  end

  marker_at[node.depth] = not node.last_child
  local text = ""
  if renderer.use_marker then
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

function M.icon(node, _, renderer)
  if node.depth == 0 then
    return
  end

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
          icon = renderer.symlink and renderer.symlink or renderer.default
          highlight = renderer.symlink and hl.SYMBOLIC_FILE_ICON or hl.DEFAULT_FILE_ICON
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

function M.name(node, config, renderer)
  if node.depth == 0 then
    local text = fn.fnamemodify(node.path, renderer.root_folder_format)
    if not text:sub(-1) == utils.os_sep then
      text = text .. utils.os_sep
    end
    return {
      padding = "",
      text = text .. "..",
      highlight = hl.ROOT_NAME,
    }
  end

  local highlight
  if renderer.use_git_status_colors then
    highlight = helpers.get_git_status_hl(node:get_git_status())
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

function M.repository(node, _, renderer)
  if node:is_git_repository_root() then
    return {
      padding = renderer.padding,
      text = renderer.icon,
      highlight = hl.GIT_REPO_TOPLEVEL,
    }
  end
end

function M.symlink_target(node, _, renderer)
  if node:is_link() then
    return {
      padding = renderer.padding,
      text = renderer.arrow_icon .. " " .. node.link_to,
      highlight = hl.SYMBOLIC_LINK,
    }
  end
end

function M.git_status(node, config, renderer)
  if config.git.enable then
    local git_status = node:get_git_status()
    if git_status then
      local result = {}
      local icons_and_hl = helpers.get_git_icons_and_hls(git_status)
      if icons_and_hl then
        for _, v in ipairs(icons_and_hl) do
          result[#result + 1] = {
            padding = renderer.padding,
            text = v.icon,
            highlight = v.hl,
          }
        end
      end

      return result
    end
  end
end

function M.diagnostics(node, config, renderer)
  if config.diagnostics.enable then
    local severity = node:get_diagnostics_severity()
    if severity then
      if renderer.min_severity == nil or severity <= renderer.min_severity then
        local diagnostic = helpers.get_diagnostic_icon_and_hl(severity)
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
  local git_staus_to_hl = {}
  function M.helpers.get_git_status_hl(status)
    return git_staus_to_hl[status]
  end

  local git_icons_and_hl
  function M.helpers.get_git_icons_and_hls(status)
    return git_icons_and_hl[status] or git_icons_and_hl.dirty
  end

  local diagnostic_icon_and_hl = {}
  function M.helpers.get_diagnostic_icon_and_hl(severity)
    return diagnostic_icon_and_hl[severity]
  end

  function M.setup(config)
    local icons = config.renderers.git_status.icons
    git_icons_and_hl = {
      ["M "] = { { icon = icons.staged, hl = hl.GIT_STAGED } },
      [" M"] = { { icon = icons.unstaged, hl = hl.GIT_DIRTY } },
      ["C "] = { { icon = icons.staged, hl = hl.GIT_STAGED } },
      [" C"] = { { icon = icons.unstaged, hl = hl.GIT_DIRTY } },
      ["CM"] = { { icon = icons.unstaged, hl = hl.GIT_DIRTY } },
      [" T"] = { { icon = icons.unstaged, hl = hl.GIT_DIRTY } },
      ["MM"] = {
        { icon = icons.staged, hl = hl.GIT_STAGED },
        { icon = icons.unstaged, hl = hl.GIT_DIRTY },
      },
      ["MD"] = { { icon = icons.staged, hl = hl.GIT_STAGED } },
      ["A "] = { { icon = icons.staged, hl = hl.GIT_STAGED } },
      ["AD"] = { { icon = icons.staged, hl = hl.GIT_STAGED } },
      [" A"] = { { icon = icons.untracked, hl = hl.GIT_NEW } },
      ["AA"] = {
        { icon = icons.unmerged, hl = hl.GIT_MERGE },
        { icon = icons.untracked, hl = hl.GIT_STAGED },
      },
      ["AU"] = {
        { icon = icons.unmerged, hl = hl.GIT_MERGE },
        { icon = icons.untracked, hl = hl.GIT_STAGED },
      },
      ["AM"] = {
        { icon = icons.staged, hl = hl.GIT_STAGED },
        { icon = icons.unstaged, hl = hl.GIT_DIRTY },
      },
      ["??"] = { { icon = icons.untracked, hl = hl.GIT_NEW } },
      ["R "] = { { icon = icons.renamed, hl = hl.GIT_RENAMED } },
      [" R"] = { { icon = icons.renamed, hl = hl.GIT_RENAMED } },
      ["RM"] = {
        { icon = icons.unstaged, hl = hl.GIT_DIRTY },
        { icon = icons.renamed, hl = hl.GIT_RENAMED },
      },
      ["UU"] = { { icon = icons.unmerged, hl = hl.GIT_MERGE } },
      ["UD"] = { { icon = icons.unmerged, hl = hl.GIT_MERGE } },
      ["UA"] = { { icon = icons.unmerged, hl = hl.GIT_MERGE } },
      [" D"] = { { icon = icons.deleted, hl = hl.GIT_DELETED } },
      ["D "] = { { icon = icons.deleted, hl = hl.GIT_DELETED } },
      ["RD"] = { { icon = icons.deleted, hl = hl.GIT_DELETED } },
      ["DD"] = { { icon = icons.deleted, hl = hl.GIT_DELETED } },
      ["DU"] = {
        { icon = icons.deleted, hl = hl.GIT_DELETED },
        { icon = icons.unmerged, hl = hl.GIT_MERGE },
      },
      ["!!"] = { { icon = icons.ignored, hl = hl.GIT_IGNORED } },
      dirty = { { icon = icons.unstaged, hl = hl.GIT_DIRTY } },
    }

    for k, v in pairs(git_icons_and_hl) do
      if #v == 1 then
        git_staus_to_hl[k] = v[1].hl
      elseif #v == 2 then
        git_staus_to_hl[k] = v[2].hl
      end
    end

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

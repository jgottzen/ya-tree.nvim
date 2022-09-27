local get_icon
do
  local icons_availble, icons = pcall(require, "nvim-web-devicons")

  ---@param filename string
  ---@param extension string
  ---@param fallback_icon string
  ---@param fallback_highlight string
  ---@return string icon, string highlight
  get_icon = function(filename, extension, fallback_icon, fallback_highlight)
    if icons_availble then
      return icons.get_icon(filename, extension)
    else
      return fallback_icon, fallback_highlight
    end
  end
end

local hl = require("ya-tree.ui.highlights")
local utils = require("ya-tree.utils")

local fn = vim.fn

local M = {
  helpers = {},
}

---@class Yat.Ui.RenderResult
---@field padding string
---@field text string
---@field highlight string

do
  ---@type table<number, boolean>
  local marker_at = {}

  ---@param node Yat.Node
  ---@param context Yat.Ui.RenderContext
  ---@param renderer Yat.Config.Renderers.Indentation
  ---@return Yat.Ui.RenderResult|nil result
  function M.indentation(node, context, renderer)
    local text
    if context.depth == 0 then
      text = ""
    else
      if renderer.use_indent_marker then
        text = ""
        marker_at[context.depth] = not context.last_child
        for i = 1, context.depth do
          local marker
          if i == context.depth and renderer.use_expander_marker and node:is_container() then
            marker = node.expanded and renderer.expanded_marker or renderer.collapsed_marker
          else
            marker = (i == context.depth and context.last_child) and renderer.last_indent_marker or renderer.indent_marker
          end

          if marker_at[i] or i == context.depth then
            text = text .. marker .. " "
          else
            text = text .. "  "
          end
        end
      elseif renderer.use_expander_marker then
        if node:is_container() then
          text = string.rep("  ", context.depth - 1) .. (node.expanded and renderer.expanded_marker or renderer.collapsed_marker) .. " "
        else
          text = string.rep("  ", context.depth)
        end
      else
        text = string.rep("  ", context.depth)
      end
    end

    return {
      padding = renderer.padding,
      text = text,
      highlight = hl.INDENT_MARKER,
    }
  end
end

---@param node Yat.Node
---@param context Yat.Ui.RenderContext
---@param renderer Yat.Config.Renderers.Icon
---@return Yat.Ui.RenderResult|nil result
function M.icon(node, context, renderer)
  if context.depth == 0 then
    return
  end

  local icon, highlight
  if node:is_container() then
    if node:node_type() == "Buffer" and node.extension == "terminal" then
      icon = get_icon(node.name, node.extension, renderer.directory.expanded, hl.DIRECTORY_ICON)
      highlight = hl.DIRECTORY_ICON
    else
      icon = renderer.directory.custom[node.name]
      if not icon then
        if node:is_link() then
          icon = node.expanded and renderer.directory.symlink_expanded or renderer.directory.symlink
        else
          if node.expanded then
            icon = node:is_empty() and renderer.directory.empty_expanded or renderer.directory.expanded
          else
            icon = node:is_empty() and renderer.directory.empty or renderer.directory.default
          end
        end
      end
      highlight = node:is_link() and hl.SYMBOLIC_DIRECTORY_ICON or hl.DIRECTORY_ICON
    end
  elseif node:is_fifo() then
    icon = renderer.file.fifo
    highlight = hl.FIFO_FILE_ICON
  elseif node:is_socket() then
    icon = renderer.file.socket
    highlight = hl.SOCKET_FILE_ICON
  elseif node:is_char_device() then
    icon = renderer.file.char
    highlight = hl.CHAR_DEVICE_FILE_ICON
  elseif node:is_block_device() then
    icon = renderer.file.block
    highlight = hl.BLOCK_DEVICE_FILE_ICON
  else
    if node:is_link() then
      if node.link_name and node.link_extension then
        icon, highlight = get_icon(node.link_name, node.link_extension, renderer.file.symlink, hl.SYMBOLIC_FILE_ICON)
      else
        icon = renderer.file.symlink
        highlight = hl.SYMBOLIC_FILE_ICON
      end
    else
      icon, highlight = get_icon(node.name, node.extension, renderer.file.default, hl.DEFAULT_FILE_ICON)
    end

    -- if the icon lookup didn't return anything use the defaults
    if not icon then
      icon = node:is_link() and renderer.file.symlink or renderer.file.default
    end
    if not highlight then
      highlight = node:is_link() and hl.SYMBOLIC_FILE_ICON or hl.DEFAULT_FILE_ICON
    end
  end

  return {
    padding = renderer.padding,
    text = icon,
    highlight = highlight,
  }
end

---@param node Yat.Node
---@param context Yat.Ui.RenderContext
---@param renderer Yat.Config.Renderers.Name
---@return Yat.Ui.RenderResult[] results
function M.name(node, context, renderer)
  if context.depth == 0 then
    local text = fn.fnamemodify(node.path, renderer.root_folder_format)
    if text:sub(-1) ~= utils.os_sep then
      text = text .. utils.os_sep
    end

    ---@type Yat.Ui.RenderResult[]
    local results
    if context.tree_type == "search" then
      ---@cast node Yat.Nodes.Search
      results = {
        {
          padding = "",
          text = 'Find "',
          highlight = hl.DIM_TEXT,
        },
        {
          padding = "",
          text = node.search_term or "",
          highlight = hl.SEARCH_TERM,
        },
        {
          padding = "",
          text = '" in: ',
          highlight = hl.DIM_TEXT,
        },
      }
    elseif context.tree_type == "buffers" then
      results = {
        {
          padding = "",
          text = "Buffers: ",
          highlight = hl.DIM_TEXT,
        },
      }
    elseif context.tree_type == "git" then
      results = {
        {
          padding = "",
          text = "Git: ",
          highlight = hl.DIM_TEXT,
        },
      }
    else
      results = {}
    end

    results[#results + 1] = {
      padding = "",
      text = text,
      highlight = hl.ROOT_NAME,
    }
    return results
  end

  local highlight
  if renderer.use_git_status_colors then
    local git_status = node:git_status()
    if git_status then
      highlight = M.helpers.get_git_status_highlight(git_status)
    end
  end

  if renderer.highlight_open_file and node:is_file() and fn.bufloaded(node.path) > 0 then
    highlight = hl.OPENED_FILE_NAME
  end

  if not highlight then
    if node:is_container() then
      highlight = hl.DIRECTORY_NAME
    elseif node:is_file() then
      highlight = hl.FILE_NAME
    elseif node:is_fifo() then
      highlight = hl.FIFO_FILE_NAME
    elseif node:is_socket() then
      highlight = hl.SOCKET_FILE_NAME
    elseif node:is_char_device() then
      highlight = hl.CHAR_DEVICE_FILE_NAME
    elseif node:is_block_device() then
      highlight = hl.BLOCK_DEVICE_FILE_NAME
    elseif node:node_type() == "Buffer" then
      ---@cast node Yat.Nodes.Buffer
      if node:is_terminal() then
        highlight = node.hidden and hl.GIT_IGNORED or hl.FILE_NAME
      end
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

---@param node Yat.Node
---@param _ Yat.Ui.RenderContext
---@param renderer Yat.Config.Renderers.Modified
---@return Yat.Ui.RenderResult|nil result
function M.modified(node, _, renderer)
  if node.modified then
    return {
      padding = renderer.padding,
      text = renderer.icon,
      highlight = hl.MODIFIED,
    }
  end
end

---@param node Yat.Node
---@param context Yat.Ui.RenderContext
---@param renderer Yat.Config.Renderers.Repository
---@return Yat.Ui.RenderResult[]|nil results
function M.repository(node, context, renderer)
  if node:is_git_repository_root() or (context.depth == 0 and node.repo) then
    local repo = node.repo --[[@as Yat.Git.Repo]]
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

    local results = { {
      padding = renderer.padding,
      text = icon .. " ",
      highlight = hl.GIT_REPO_TOPLEVEL,
    } }

    if renderer.show_status then
      local status = repo:meta_status()
      if status.behind > 0 and renderer.icons.behind ~= "" then
        results[#results + 1] = {
          padding = renderer.padding,
          text = renderer.icons.behind .. status.behind,
          highlight = hl.GIT_BEHIND_COUNT,
        }
      end
      if status.ahead > 0 and renderer.icons.ahead ~= "" then
        results[#results + 1] = {
          padding = status.behind and "" or renderer.padding,
          text = renderer.icons.ahead .. status.ahead,
          highlight = hl.GIT_AHEAD_COUNT,
        }
      end
      if status.stashed > 0 and renderer.icons.stashed ~= "" then
        results[#results + 1] = {
          padding = renderer.padding,
          text = renderer.icons.stashed .. status.stashed,
          highlight = hl.GIT_STASH_COUNT,
        }
      end
      if status.unmerged > 0 and renderer.icons.unmerged ~= "" then
        results[#results + 1] = {
          padding = renderer.padding,
          text = renderer.icons.unmerged .. status.unmerged,
          highlight = hl.GIT_UNMERGED_COUNT,
        }
      end
      if status.staged > 0 and renderer.icons.staged ~= "" then
        results[#results + 1] = {
          padding = renderer.padding,
          text = renderer.icons.staged .. status.staged,
          highlight = hl.GIT_STAGED_COUNT,
        }
      end
      if status.unstaged > 0 and renderer.icons.unstaged ~= "" then
        results[#results + 1] = {
          padding = renderer.padding,
          text = renderer.icons.unstaged .. status.unstaged,
          highlight = hl.GIT_UNSTAGED_COUNT,
        }
      end
      if status.untracked > 0 and renderer.icons.untracked ~= "" then
        results[#results + 1] = {
          padding = renderer.padding,
          text = renderer.icons.untracked .. status.untracked,
          highlight = hl.GIT_UNTRACKED_COUNT,
        }
      end
    end

    return results
  end
end

---@param node Yat.Node
---@param _ Yat.Ui.RenderContext
---@param renderer Yat.Config.Renderers.SymlinkTarget
---@return Yat.Ui.RenderResult|nil result
function M.symlink_target(node, _, renderer)
  if node:is_link() then
    if node.link_orphan then
      return {
        {
          padding = renderer.padding,
          text = renderer.arrow_icon .. " ",
          highlight = hl.SYMBOLIC_LINK_TARGET,
        },
        {
          padding = "",
          text = node.relative_link_to,
          highlight = hl.ERROR_FILE_NAME,
        },
      }
    else
      return {
        padding = renderer.padding,
        text = renderer.arrow_icon .. " " .. node.relative_link_to,
        highlight = node.link_orphan and hl.ERROR_FILE_NAME or hl.SYMBOLIC_LINK_TARGET,
      }
    end
  end
end

---@param node Yat.Node
---@param context Yat.Ui.RenderContext
---@param renderer Yat.Config.Renderers.GitStatus
---@return Yat.Ui.RenderResult[]|nil results
function M.git_status(node, context, renderer)
  if context.config.git.enable then
    local git_status = node:git_status()
    if git_status then
      local results = {}
      local icons_and_hl = M.helpers.get_git_icons_and_highlights(git_status)
      if icons_and_hl then
        for _, v in ipairs(icons_and_hl) do
          results[#results + 1] = {
            padding = renderer.padding,
            text = v.icon,
            highlight = v.highlight,
          }
        end
      end

      return results
    end
  end
end

---@param node Yat.Node
---@param context Yat.Ui.RenderContext
---@param renderer Yat.Config.Renderers.Diagnostics
---@return Yat.Ui.RenderResult|nil result
function M.diagnostics(node, context, renderer)
  if context.config.diagnostics.enable then
    local severity = node:diagnostics_severity()
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

---@param node Yat.Node|Yat.Nodes.Buffer
---@param _ Yat.Ui.RenderContext
---@param renderer Yat.Config.Renderers.BufferInfo
---@return Yat.Ui.RenderResult[]|nil results
function M.buffer_info(node, _, renderer)
  local bufnr = -1
  local hidden = false
  if node:node_type() == "Buffer" then
    bufnr = node.bufnr or -1
    hidden = node.hidden or false
  elseif fn.bufloaded(node.path) > 0 then
    bufnr = fn.bufnr(node.path)
  end

  local results = {}
  if bufnr > 0 then
    results[#results + 1] = {
      padding = renderer.padding,
      text = "#" .. bufnr,
      highlight = hl.BUFFER_NUMBER,
    }
  end
  if hidden then
    results[#results + 1] = {
      padding = renderer.padding,
      text = renderer.hidden_icon,
      highlight = hl.BUFFER_HIDDEN,
    }
  end

  if #results > 0 then
    return results
  end
end

---@param node Yat.Node
---@param _ Yat.Ui.RenderContext
---@param renderer Yat.Config.Renderers.Clipboard
---@return Yat.Ui.RenderResult|nil result
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

  ---@class Yat.Ui.IconAndHighlight
  ---@field icon string
  ---@field highlight string

  ---@type table<string, Yat.Ui.IconAndHighlight[]>
  local git_icons_and_hl = {}

  ---@param status string
  ---@return Yat.Ui.IconAndHighlight[]
  function M.helpers.get_git_icons_and_highlights(status)
    return git_icons_and_hl[status] or git_icons_and_hl.dirty
  end

  ---@type table<number, Yat.Ui.IconAndHighlight>
  local diagnostic_icon_and_hl = {}

  ---@param severity number
  ---@return Yat.Ui.IconAndHighlight
  function M.helpers.get_diagnostic_icon_and_highligt(severity)
    return diagnostic_icon_and_hl[severity]
  end

  ---@param config Yat.Config
  function M.setup(config)
    local icons = config.renderers.git_status.icons
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
          icon = sign.text, --[[@as string]]
          highlight = sign.texthl, --[[@as string]]
        }
      else
        diagnostic_icon_and_hl[k] = {
          icon = v[2]:sub(1, 1),
          highlight = "LspDiagnosticsDefault" .. v[2],
        }
      end
    end
  end
end

return M

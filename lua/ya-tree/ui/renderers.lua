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
local symbol_kind = require("ya-tree.lsp.symbol_kind")
local utils = require("ya-tree.utils")
local log = require("ya-tree.log")("ui")

---@class Yat.Ui.RenderContext
---@field tree_type Yat.Trees.Type
---@field config Yat.Config
---@field depth integer
---@field last_child boolean
---@field indent_markers table<integer, boolean>

---@alias Yat.Ui.RendererFunction fun(node: Yat.Node, context: Yat.Ui.RenderContext, renderer: Yat.Config.BaseRendererConfig): Yat.Ui.RenderResult[]|nil

---@class Yat.Ui.Renderer.Renderer
---@field fn Yat.Ui.RendererFunction
---@field config Yat.Config.BaseRendererConfig

local M = {
  helpers = {},
  ---@private
  ---@type table<Yat.Ui.Renderer.Name, Yat.Ui.Renderer.Renderer>
  _renderers = {},
}

---@param name Yat.Ui.Renderer.Name
---@param fn Yat.Ui.RendererFunction
---@param config Yat.Config.BaseRendererConfig
function M.define_renderer(name, fn, config)
  local renderer = {
    fn = fn,
    config = config,
  }
  if M._renderers[name] then
    log.info("overriding renderer %q with %s", name, renderer)
  end
  M._renderers[name] = renderer
end

---@param name Yat.Ui.Renderer.Name
---@return Yat.Ui.Renderer.Renderer|nil
function M.get_renderer(name)
  return M._renderers[name]
end

local fn = vim.fn

---@class Yat.Ui.RenderResult
---@field padding string
---@field text string
---@field highlight string

---@param node Yat.Node
---@param context Yat.Ui.RenderContext
---@param renderer Yat.Config.Renderers.Builtin.Indentation
---@return Yat.Ui.RenderResult[] result
function M.indentation(node, context, renderer)
  local marker_at = context.indent_markers
  ---@type Yat.Ui.RenderResult[]
  local results = {}
  local text
  if renderer.use_indent_marker then
    if context.depth == 0 then
      if node:has_children() then
        results[#results + 1] = {
          padding = renderer.padding,
          text = (node.expanded and renderer.expanded_marker or renderer.collapsed_marker) .. " ",
          highlight = hl.INDENT_EXPANDER,
        }
      end
    else
      marker_at[context.depth] = not context.last_child
      results[#results + 1] = {
        padding = renderer.padding,
        text = renderer.use_expander_marker and "  " or "",
        highlight = hl.INDENT_MARKER,
      }
      for i = 1, context.depth do
        local marker
        local highlight = hl.INDENT_MARKER
        if i == context.depth and renderer.use_expander_marker and node:has_children() then
          marker = node.expanded and renderer.expanded_marker or renderer.collapsed_marker
          highlight = hl.INDENT_EXPANDER
        else
          marker = ((i == context.depth or context.depth == 1) and context.last_child) and renderer.last_indent_marker
            or renderer.indent_marker
        end

        if marker_at[i] or i == context.depth then
          text = marker .. " "
        else
          text = "  "
        end
        results[#results + 1] = {
          padding = "",
          text = text,
          highlight = highlight,
        }
      end
    end
  elseif renderer.use_expander_marker then
    local highlight = hl.INDENT_MARKER
    if node:has_children() then
      text = string.rep("  ", context.depth) .. (node.expanded and renderer.expanded_marker or renderer.collapsed_marker) .. " "
      highlight = hl.INDENT_EXPANDER
    else
      text = string.rep("  ", context.depth + 1)
    end
    results[#results + 1] = {
      padding = renderer.padding,
      text = text,
      highlight = highlight,
    }
  else
    text = string.rep("  ", context.depth)
    results[#results + 1] = {
      padding = renderer.padding,
      text = text,
      highlight = hl.INDENT_MARKER,
    }
  end

  return results
end

---@param node Yat.Node
---@param context Yat.Ui.RenderContext
---@param renderer Yat.Config.Renderers.Builtin.Icon
---@return Yat.Ui.RenderResult[]|nil result
function M.icon(node, context, renderer)
  if context.depth == 0 then
    return
  end

  local icon, highlight
  if
    node:node_type() == "buffer" and node--[[@as Yat.Nodes.Buffer]]:is_terminals_container()
  then
    icon = get_icon(node.name, node.extension, renderer.directory.expanded, hl.DIRECTORY_ICON)
    highlight = hl.DIRECTORY_ICON
  elseif node:node_type() == "symbol" then
    ---@cast node Yat.Nodes.Symbol
    icon = M.helpers.get_lsp_symbols_kind_icon(node.kind)
    highlight = M.helpers.get_lsp_symbol_highlight(node.kind)
  elseif node:is_directory() then
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

  return { {
    padding = renderer.padding,
    text = icon,
    highlight = highlight,
  } }
end

---@param node Yat.Node
---@param context Yat.Ui.RenderContext
---@param renderer Yat.Config.Renderers.Builtin.Name
---@return Yat.Ui.RenderResult[] results
function M.name(node, context, renderer)
  if context.depth == 0 then
    local padding, text, highlight = "", nil, hl.ROOT_NAME
    if node:node_type() == "text" then
      padding = renderer.padding
      text = node.name
      highlight = hl.DIM_TEXT
    elseif node:node_type() == "symbol" then
      text = node.name
    else
      text = fn.fnamemodify(node.path, renderer.root_folder_format)
      if text:sub(-1) ~= utils.os_sep then
        text = text .. utils.os_sep
      end
    end
    return { {
      padding = padding,
      text = text,
      highlight = highlight,
    } }
  end

  local highlight
  if renderer.use_git_status_colors then
    local git_status = node:git_status()
    if git_status then
      highlight = M.helpers.get_git_status_highlight(git_status)
    end
  end

  if not highlight then
    if node:is_directory() then
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
    elseif node:node_type() == "buffer" then
      ---@cast node Yat.Nodes.Buffer
      if node:is_terminal() then
        highlight = node.bufhidden and hl.GIT_IGNORED or hl.FILE_NAME
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
---@param renderer Yat.Config.Renderers.Builtin.Modified
---@return Yat.Ui.RenderResult[]|nil result
function M.modified(node, _, renderer)
  if node.modified then
    return { {
      padding = renderer.padding,
      text = renderer.icon,
      highlight = hl.MODIFIED,
    } }
  end
end

---@param node Yat.Node
---@param context Yat.Ui.RenderContext
---@param renderer Yat.Config.Renderers.Builtin.Repository
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
      local status = repo:status():meta()
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
---@param renderer Yat.Config.Renderers.Builtin.SymlinkTarget
---@return Yat.Ui.RenderResult[]|nil result
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
        {
          padding = renderer.padding,
          text = renderer.arrow_icon .. " " .. node.relative_link_to,
          highlight = node.link_orphan and hl.ERROR_FILE_NAME or hl.SYMBOLIC_LINK_TARGET,
        },
      }
    end
  end
end

---@param node Yat.Node
---@param context Yat.Ui.RenderContext
---@param renderer Yat.Config.Renderers.Builtin.GitStatus
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
---@param renderer Yat.Config.Renderers.Builtin.Diagnostics
---@return Yat.Ui.RenderResult[]|nil result
function M.diagnostics(node, context, renderer)
  if context.config.diagnostics.enable then
    local severity = node:diagnostic_severity()
    if severity and (severity <= (node:is_directory() and renderer.directory_min_severity or renderer.file_min_severity)) then
      local diagnostic = M.helpers.get_diagnostic_icon_and_highligt(severity)
      if diagnostic then
        return {
          {
            padding = renderer.padding,
            text = diagnostic.icon,
            highlight = diagnostic.highlight,
          },
        }
      end
    end
  end
end

---@param node Yat.Node
---@param _ Yat.Ui.RenderContext
---@param renderer Yat.Config.Renderers.Builtin.BufferInfo
---@return Yat.Ui.RenderResult[] results
function M.buffer_info(node, _, renderer)
  local bufnr = -1
  local hidden = false
  if node:node_type() == "buffer" then
    ---@cast node Yat.Nodes.Buffer
    bufnr = node.bufnr or -1
    hidden = node.bufhidden or false
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

  return results
end

---@param node Yat.Node
---@param _ Yat.Ui.RenderContext
---@param renderer Yat.Config.Renderers.Builtin.Clipboard
---@return Yat.Ui.RenderResult[]|nil result
function M.clipboard(node, _, renderer)
  if node:clipboard_status() then
    return {
      {
        padding = renderer.padding,
        text = "(" .. node:clipboard_status() .. ")",
        highlight = hl.CLIPBOARD_STATUS,
      },
    }
  end
end

---@param node Yat.Nodes.Symbol
---@param _ Yat.Ui.RenderContext
---@param renderer Yat.Config.Renderers.Builtin.SymbolDetails
---@return Yat.Ui.RenderResult[]|nil result
function M.symbol_details(node, _, renderer)
  if node.detail then
    return {
      {
        padding = renderer.padding,
        text = node.detail,
        highlight = hl.DIM_TEXT,
      },
    }
  end
end

do
  ---@type table<string, string>
  local GIT_STATUS_TO_HL = {}

  ---@param status string
  ---@return string
  function M.helpers.get_git_status_highlight(status)
    return GIT_STATUS_TO_HL[status]
  end

  ---@class Yat.Ui.IconAndHighlight
  ---@field icon string
  ---@field highlight string

  ---@type table<string, Yat.Ui.IconAndHighlight[]>
  local GIT_ICONS_AND_HL = {}

  ---@param status string
  ---@return Yat.Ui.IconAndHighlight[]
  function M.helpers.get_git_icons_and_highlights(status)
    return GIT_ICONS_AND_HL[status] or GIT_ICONS_AND_HL.dirty
  end

  ---@type table<integer, Yat.Ui.IconAndHighlight>
  local DIAGNOSTIC_ICONS_AND_HL = {}

  ---@param severity integer
  ---@return Yat.Ui.IconAndHighlight
  function M.helpers.get_diagnostic_icon_and_highligt(severity)
    return DIAGNOSTIC_ICONS_AND_HL[severity]
  end

  ---@type table<Lsp.Symbol.Kind, string>
  local LSP_KIND_ICONS = {
    [2] = "",
    [3] = "",
    [4] = "",
    [5] = "𝓒",
    [6] = "ƒ",
    [7] = "",
    [8] = "",
    [9] = "",
    [10] = "ℰ",
    [11] = "",
    [12] = "",
    [13] = "",
    [14] = "",
    [15] = "",
    [16] = "",
    [17] = "⊨",
    [18] = "",
    [19] = "⦿",
    [20] = "",
    [21] = "ﳠ",
    [22] = "",
    [23] = "𝓢",
    [24] = "",
    [25] = "",
    [26] = "",
  }

  ---@param kind Lsp.Symbol.Kind
  function M.helpers.get_lsp_symbols_kind_icon(kind)
    return LSP_KIND_ICONS[kind]
  end

  ---@type table<Lsp.Symbol.Kind, string>
  local LSP_KIND_HIGHLIGHTS = {
    [2] = "@namespace",
    [3] = "@namespace",
    [4] = "@namespace",
    [5] = "@type",
    [6] = "@method",
    [7] = "@property",
    [8] = "@field",
    [9] = "@constructor",
    [10] = "@type",
    [11] = "@type",
    [12] = "@function",
    [13] = "@constant",
    [14] = "@constant",
    [15] = "@string",
    [16] = "@number",
    [17] = "@boolean",
    [18] = "@type",
    [19] = "@type",
    [20] = "@type",
    [21] = "@type",
    [22] = "@field",
    [23] = "@type",
    [24] = "@type",
    [25] = "@operator",
    [26] = "@type",
  }

  ---@param kind Lsp.Symbol.Kind
  function M.helpers.get_lsp_symbol_highlight(kind)
    return LSP_KIND_HIGHLIGHTS[kind]
  end

  ---@param icons Yat.Config.Renderers.GitStatus.Icons
  local function setup_highlights(icons)
    GIT_ICONS_AND_HL = {}

    GIT_ICONS_AND_HL["M."] = { { icon = icons.staged, highlight = hl.GIT_STAGED } }
    GIT_ICONS_AND_HL["MM"] = { { icon = icons.staged, highlight = hl.GIT_STAGED }, { icon = icons.modified, highlight = hl.GIT_DIRTY } }
    GIT_ICONS_AND_HL["MT"] = { { icon = icons.staged, highlight = hl.GIT_STAGED }, { icon = icons.type_changed, highlight = hl.GIT_DIRTY } }
    GIT_ICONS_AND_HL["MD"] = { { icon = icons.staged, highlight = hl.GIT_STAGED }, { icon = icons.deleted, highlight = hl.GIT_DIRTY } }

    GIT_ICONS_AND_HL["T."] = { { icon = icons.type_changed, highlight = hl.GIT_STAGED } }
    GIT_ICONS_AND_HL["TM"] = {
      { icon = icons.type_changed, highlight = hl.GIT_STAGED },
      { icon = icons.modified, highlight = hl.GIT_DIRTY },
    }
    GIT_ICONS_AND_HL["TT"] = {
      { icon = icons.type_changed, highlight = hl.GIT_STAGED },
      { icon = icons.type_changed, highlight = hl.GIT_DIRTY },
    }
    GIT_ICONS_AND_HL["TD"] = {
      { icon = icons.type_changed, highlight = hl.GIT_STAGED },
      { icon = icons.deleted, highlight = hl.GIT_DIRTY },
    }

    GIT_ICONS_AND_HL["A."] = { { icon = icons.added, highlight = hl.GIT_NEW } }
    GIT_ICONS_AND_HL["AM"] = { { icon = icons.added, highlight = hl.GIT_STAGED }, { icon = icons.modified, highlight = hl.GIT_DIRTY } }
    GIT_ICONS_AND_HL["AT"] = { { icon = icons.added, highlight = hl.GIT_STAGED }, { icon = icons.type_changed, highlight = hl.GIT_DIRTY } }
    GIT_ICONS_AND_HL["AD"] = { { icon = icons.added, highlight = hl.GIT_STAGED }, { icon = icons.deleted, highlight = hl.GIT_DIRTY } }

    GIT_ICONS_AND_HL["D."] = { { icon = icons.deleted, highlight = hl.GIT_DELETED } }

    GIT_ICONS_AND_HL["R."] = { { icon = icons.renamed, highlight = hl.GIT_RENAMED } }
    GIT_ICONS_AND_HL["RM"] = { { icon = icons.renamed, highlight = hl.GIT_STAGED }, { icon = icons.modified, highlight = hl.GIT_DIRTY } }
    GIT_ICONS_AND_HL["RT"] = {
      { icon = icons.renamed, highlight = hl.GIT_STAGED },
      { icon = icons.type_changed, highlight = hl.GIT_DIRTY },
    }
    GIT_ICONS_AND_HL["RD"] = { { icon = icons.renamed, highlight = hl.GIT_STAGED }, { icon = icons.deleted, highlight = hl.GIT_DIRTY } }

    GIT_ICONS_AND_HL["C."] = { { icon = icons.copied, highlight = hl.GIT_STAGED } }
    GIT_ICONS_AND_HL["CM"] = { { icon = icons.copied, highlight = hl.GIT_STAGED }, { icon = icons.modified, highlight = hl.GIT_DIRTY } }
    GIT_ICONS_AND_HL["CT"] = { { icon = icons.copied, highlight = hl.GIT_STAGED }, { icon = icons.type_changed, highlight = hl.GIT_DIRTY } }
    GIT_ICONS_AND_HL["CD"] = { { icon = icons.copied, highlight = hl.GIT_STAGED }, { icon = icons.deleted, highlight = hl.GIT_DIRTY } }

    GIT_ICONS_AND_HL[".A"] = { { icon = icons.added, highlight = hl.GIT_NEW } }
    GIT_ICONS_AND_HL[".M"] = { { icon = icons.modified, highlight = hl.GIT_DIRTY } }
    GIT_ICONS_AND_HL[".T"] = { { icon = icons.type_changed, highlight = hl.GIT_DIRTY } }
    GIT_ICONS_AND_HL[".D"] = { { icon = icons.modified, highlight = hl.GIT_DIRTY }, { icon = icons.deleted, highlight = hl.GIT_DELETED } }
    GIT_ICONS_AND_HL[".R"] = { { icon = icons.renamed, highlight = hl.GIT_DIRTY } }

    GIT_ICONS_AND_HL["DD"] = {
      { icon = icons.unmerged, highlight = hl.GIT_MERGE },
      { icon = icons.merge.both, highlight = hl.GIT_DELETED },
    }
    GIT_ICONS_AND_HL["DU"] = { { icon = icons.unmerged, highlight = hl.GIT_MERGE }, { icon = icons.merge.us, highlight = hl.GIT_DELETED } }
    GIT_ICONS_AND_HL["UD"] = {
      { icon = icons.unmerged, highlight = hl.GIT_MERGE },
      { icon = icons.merge.them, highlight = hl.GIT_DELETED },
    }

    GIT_ICONS_AND_HL["AA"] = { { icon = icons.unmerged, highlight = hl.GIT_MERGE }, { icon = icons.merge.both, highlight = hl.GIT_NEW } }
    GIT_ICONS_AND_HL["AU"] = { { icon = icons.unmerged, highlight = hl.GIT_MERGE }, { icon = icons.merge.us, highlight = hl.GIT_NEW } }
    GIT_ICONS_AND_HL["UA"] = { { icon = icons.unmerged, highlight = hl.GIT_MERGE }, { icon = icons.merge.them, highlight = hl.GIT_NEW } }

    GIT_ICONS_AND_HL["UU"] = { { icon = icons.unmerged, highlight = hl.GIT_MERGE }, { icon = icons.merge.both, highlight = hl.GIT_DIRTY } }

    GIT_ICONS_AND_HL["!"] = { { icon = icons.ignored, highlight = hl.GIT_IGNORED } }
    GIT_ICONS_AND_HL["?"] = { { icon = icons.untracked, highlight = hl.GIT_UNTRACKED } }

    GIT_ICONS_AND_HL.dirty = { { icon = icons.modified, highlight = hl.GIT_DIRTY } }
    GIT_ICONS_AND_HL.staged = { { icon = icons.staged, highlight = hl.GIT_STAGED } }

    GIT_STATUS_TO_HL = {}
    for k, v in pairs(GIT_ICONS_AND_HL) do
      if #v == 1 then
        GIT_STATUS_TO_HL[k] = v[1].highlight
      elseif #v == 2 then
        GIT_STATUS_TO_HL[k] = v[2].highlight
      end
    end

    DIAGNOSTIC_ICONS_AND_HL = {}

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
        DIAGNOSTIC_ICONS_AND_HL[k] = {
          icon = sign.text, --[[@as string]]
          highlight = sign.texthl, --[[@as string]]
        }
      else
        DIAGNOSTIC_ICONS_AND_HL[k] = {
          icon = v[2]:sub(1, 1),
          highlight = "LspDiagnosticsDefault" .. v[2],
        }
      end
    end
  end

  ---@param renderers Yat.Config.Renderers
  local function define_renderers(renderers)
    M._renderers = {}

    M.define_renderer("indentation", M.indentation, renderers.builtin.indentation)
    M.define_renderer("icon", M.icon, renderers.builtin.icon)
    M.define_renderer("name", M.name, renderers.builtin.name)
    M.define_renderer("modified", M.modified, renderers.builtin.modified)
    M.define_renderer("repository", M.repository, renderers.builtin.repository)
    M.define_renderer("symlink_target", M.symlink_target, renderers.builtin.symlink_target)
    M.define_renderer("git_status", M.git_status, renderers.builtin.git_status)
    M.define_renderer("diagnostics", M.diagnostics, renderers.builtin.diagnostics)
    M.define_renderer("buffer_info", M.buffer_info, renderers.builtin.buffer_info)
    M.define_renderer("clipboard", M.clipboard, renderers.builtin.clipboard)
    M.define_renderer("symbol_details", M.symbol_details, renderers.builtin.symbol_details)

    for name, renderer in pairs(renderers) do
      if name ~= "builtin" then
        log.debug("creating renderer %q, %s", name, renderer)
        M.define_renderer(name, renderer.fn, renderer.config)
      end
    end
  end

  ---@param config Yat.Config
  function M.setup(config)
    define_renderers(config.renderers)
    setup_highlights(config.renderers.builtin.git_status.icons)
  end
end

return M

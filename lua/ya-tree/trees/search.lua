local fs = require("ya-tree.fs")
local git = require("ya-tree.git")
local SearchNode = require("ya-tree.nodes.search_node")
local Tree = require("ya-tree.trees.tree")
local tree_utils = require("ya-tree.trees.utils")
local hl = require("ya-tree.ui.highlights")
local utils = require("ya-tree.utils")
local log = require("ya-tree.log")("trees")

---@class Yat.Trees.Search : Yat.Tree
---@field TYPE "search"
---@field root Yat.Nodes.Search
---@field current_node Yat.Nodes.Search
---@field supported_actions Yat.Trees.Search.SupportedActions[]
---@field supported_events { autocmd: Yat.Trees.AutocmdEventsLookupTable, git: Yat.Trees.GitEventsLookupTable, yatree: Yat.Trees.YaTreeEventsLookupTable }
---@field complete_func fun(self: Yat.Trees.Search, bufnr: integer)
local SearchTree = { TYPE = "search" }
SearchTree.__index = SearchTree
SearchTree.__eq = Tree.__eq
SearchTree.__tostring = Tree.__tostring
setmetatable(SearchTree, { __index = Tree })

---@alias Yat.Trees.Search.SupportedActions
---| "cd_to"
---| "toggle_ignored"
---| "toggle_filter"
---
---| "search_for_node_in_tree"
---| "search_interactively"
---| "search_once"
---
---| "goto_node_in_filesystem_tree"
---
---| "check_node_for_git"
---| "focus_prev_git_item"
---| "focus_next_git_item"
---| "git_stage"
---| "git_unstage"
---| "git_revert"
---
---| "focus_prev_diagnostic_item"
---| "focus_next_diagnostic_item"
---
---| Yat.Trees.Tree.SupportedActions

---@param config Yat.Config
function SearchTree.setup(config)
  SearchTree.complete_func = Tree.complete_func_loaded_nodes
  SearchTree.renderers = tree_utils.create_renderers(SearchTree.TYPE, config)

  local builtin = require("ya-tree.actions.builtin")
  SearchTree.supported_actions = utils.tbl_unique({
    builtin.files.cd_to,
    builtin.files.toggle_ignored,
    builtin.files.toggle_filter,

    builtin.search.search_for_node_in_tree,
    builtin.search.search_interactively,
    builtin.search.search_once,

    builtin.tree_specific.goto_node_in_filesystem_tree,

    builtin.git.check_node_for_git,
    builtin.git.focus_prev_git_item,
    builtin.git.focus_next_git_item,
    builtin.git.git_stage,
    builtin.git.git_unstage,
    builtin.git.git_revert,

    builtin.diagnostics.focus_prev_diagnostic_item,
    builtin.diagnostics.focus_next_diagnostic_item,

    unpack(vim.deepcopy(Tree.supported_actions)),
  })

  local ae = require("ya-tree.events.event").autocmd
  local ge = require("ya-tree.events.event").git
  local ye = require("ya-tree.events.event").ya_tree
  SearchTree.supported_events = {
    autocmd = { [ae.BUFFER_MODIFIED] = SearchTree.on_buffer_modified },
    git = {},
    yatree = {},
  }
  if config.update_on_buffer_saved then
    SearchTree.supported_events.autocmd[ae.BUFFER_SAVED] = SearchTree.on_buffer_saved
  end
  if config.git.enable then
    SearchTree.supported_events.git[ge.DOT_GIT_DIR_CHANGED] = SearchTree.on_git_event
  end
  if config.diagnostics.enable then
    SearchTree.supported_events.yatree[ye.DIAGNOSTICS_CHANGED] = SearchTree.on_diagnostics_event
  end
end

---@async
---@param tabpage integer
---@param path? string
---@param kwargs? table<string, any>
---@return Yat.Trees.Search|nil tree
function SearchTree:new(tabpage, path, kwargs)
  if not path then
    return
  end
  local this = Tree.new(self, tabpage, path)
  this:_init(path)
  if kwargs and kwargs.term then
    local matches_or_error = this:search(kwargs.term)
    if type(matches_or_error) == "string" then
      utils.warn(string.format("Failed with message:\n\n%s", matches_or_error))
      return
    end
  end

  log.info("created new tree %s", tostring(this))
  return this
end

---@async
---@private
---@param self Yat.Trees.Search
---@param path string
function SearchTree:_init(path)
  local fs_node = fs.node_for(path) --[[@as Yat.Fs.Node]]
  self.root = SearchNode:new(fs_node)
  self.current_node = self.root
  self.root.repo = git.get_repo_for_path(self.root.path)
end

---@return string line
---@return Yat.Ui.HighlightGroup[][] highlights
function SearchTree:render_header()
  if self.root.search_term then
    local end_of_name = #self.section_icon + 2 + #self.section_name
    return self.section_icon .. "  " .. self.section_name .. " for '" .. self.root.search_term .. "'",
      {
        { name = hl.SECTION_ICON, from = 0, to = #self.section_icon + 2 },
        { name = hl.SECTION_NAME, from = #self.section_icon + 2, to = end_of_name },
        { name = hl.DIM_TEXT, from = end_of_name + 1, to = end_of_name + 6 },
        { name = hl.SEARCH_TERM, from = end_of_name + 6, to = end_of_name + 6 + #self.root.search_term },
        { name = hl.DIM_TEXT, from = end_of_name + 6 + #self.root.search_term, to = -1 },
      }
  end
  return Tree.render_header(self)
end

---@async
---@param path string
---@return boolean
---@nodiscard
function SearchTree:change_root_node(path)
  if self.root.path ~= path then
    local old_root = self.root
    self:_init(path)
    log.debug("updated tree to %s, old root was %s", tostring(self), tostring(old_root))
  end
  return true
end

---@async
---@param term string
---@return integer|string matches_or_error
function SearchTree:search(term)
  local result_node, matches_or_error = self.root:search(term)
  if result_node then
    self.current_node = result_node
  end
  return matches_or_error
end

function SearchTree:reset()
  self.root:clear()
  self.current_node = self.root
end

return SearchTree

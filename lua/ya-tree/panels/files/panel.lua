local defer = require("ya-tree.async").defer
local fs = require("ya-tree.fs")
local fs_watcher = require("ya-tree.fs.watcher")
local git = require("ya-tree.git")
local hl = require("ya-tree.ui.highlights")
local log = require("ya-tree.log").get("panels")
local meta = require("ya-tree.meta")
local Node = require("ya-tree.nodes.node")
local Path = require("ya-tree.path")
local scheduler = require("ya-tree.async").scheduler
local SearchNode = require("ya-tree.nodes.search_node")
local TreePanel = require("ya-tree.panels.tree_panel")
local utils = require("ya-tree.utils")

local api = vim.api
local uv = vim.loop

---@class Yat.Panel.Files : Yat.Panel.Tree
---@field new async fun(self: Yat.Panel.Files, sidebar: Yat.Sidebar, config: Yat.Config.Panels.Files, keymap: table<string, Yat.Action>, renderers: Yat.Panel.TreeRenderers): Yat.Panel.Files
---@overload async fun(sidebar: Yat.Sidebar, config: Yat.Config.Panels.Files, keymap: table<string, Yat.Action>, renderers: Yat.Panel.TreeRenderers): Yat.Panel.Files
---@field class fun(self: Yat.Panel.Files): Yat.Panel.Files
---@field static Yat.Panel.Files
---@field super Yat.Panel.Tree
---
---@field public TYPE "files"
---@field public root Yat.Node|Yat.Nodes.Search
---@field public current_node Yat.Node|Yat.Nodes.Search
---@field private files_root Yat.Node
---@field private files_current_node Yat.Node
---@field public focus_path_on_fs_event? string|"expand"
---@field private mode "files"|"search"
local FilesPanel = meta.create_class("Yat.Panel.Files", TreePanel)

---Creates a new filesystem node tree root.
---@async
---@param path string the path
---@param old_root? Yat.Node the previous root
---@return Yat.Node root
local function create_root_node(path, old_root)
  local fs_node = fs.node_for(path) --[[@as Yat.Fs.Node]]
  local root = Node:new(fs_node)

  -- if the tree root was moved on level up, i.e the new root is the parent of the old root, add it to the tree
  if old_root and Path:new(old_root.path):parent().filename == root.path then
    root:add_child(old_root)
    old_root.parent = root
    local repo = old_root.repo
    if repo and root.path:find(repo.toplevel, 1, true) then
      root.repo = repo
    end
  end

  return root
end

---@async
---@private
---@param sidebar Yat.Sidebar
---@param config Yat.Config.Panels.Files
---@param keymap table<string, Yat.Action>
---@param renderers Yat.Panel.TreeRenderers
function FilesPanel:init(sidebar, config, keymap, renderers)
  local path = uv.cwd() --[[@as string]]
  local root = create_root_node(path)
  self.super:init("files", sidebar, config.title, config.icon, keymap, renderers, root)
  defer(function()
    self.root:expand({ force_scan = true })
    self:draw(self.current_node)
  end)
  self.mode = "files"
  self.files_root = self.root
  self.files_current_node = self.current_node
  self:check_node_for_git_repo(self.root)
  self:register_buffer_modified_event()
  self:register_buffer_saved_event()
  self:register_buffer_enter_event()
  self:register_dir_changed_event()
  self:register_dot_git_dir_changed_event()
  self:register_diagnostics_changed_event()
  self:register_fs_changed_event()

  log.info("created panel %s", tostring(self))
end

---@param node Yat.Node
local function maybe_remove_watchers(node)
  ---@diagnostic disable-next-line:invisible
  if node:is_directory() and node._fs_event_registered then
    ---@diagnostic disable-next-line:invisible
    node._fs_event_registered = false
    fs_watcher.remove_watcher(node.path)
  end
end

function FilesPanel:delete()
  self.files_root:walk(maybe_remove_watchers)
  maybe_remove_watchers(self.files_root)
  self.super:delete()
end

---@async
---@private
---@param dir string
---@param filenames string[]
function FilesPanel:on_fs_changed_event(dir, filenames)
  log.debug("fs_event for dir %q, with files %s, focus=%q", dir, filenames, self.focus_path_on_fs_event)
  local is_open = self:is_open()

  local repo = git.get_repo_for_path(dir)
  if repo then
    repo:status():refresh({ ignored = true })
  end

  -- if the watched directory was deleted, the parent directory will handle any updates
  if not fs.exists(dir) or not (self.files_root:is_ancestor_of(dir) or self.files_root.path == dir) then
    return
  end

  local dir_node = self.files_root:get_child_if_loaded(dir)
  if dir_node then
    dir_node:refresh()
    if is_open then
      local new_node = nil
      if self.focus_path_on_fs_event then
        if self.focus_path_on_fs_event == "expand" then
          dir_node:expand()
        else
          local parent = self.files_root:expand({ to = Path:new(self.focus_path_on_fs_event):parent().filename })
          new_node = parent and parent:get_child_if_loaded(self.focus_path_on_fs_event)
        end
        if not new_node then
          local os_sep = Path.path.sep
          for _, filename in ipairs(filenames) do
            local path = dir .. os_sep .. filename
            local child = dir_node:get_child_if_loaded(path)
            if child then
              log.debug("setting current node to %q", path)
              new_node = child
              break
            end
          end
        end
      end
      if self.root == self.files_root and self.path_lookup[dir_node.path] then
        scheduler()
        self:draw(new_node or self:get_current_node())
      end
    end

    if self.focus_path_on_fs_event then
      log.debug("resetting focus_path_on_fs_event=%q dir=%q, filenames=%s", self.focus_path_on_fs_event, dir, filenames)
      self.focus_path_on_fs_event = nil
    end
  end
end

---@async
---@param new_cwd string
function FilesPanel:on_cwd_changed(new_cwd)
  if new_cwd ~= self.files_root.path then
    self:change_root_node(new_cwd)
  end
end

---@async
---@private
---@param new_root string
---@return boolean `false` if the current tree cannot walk up or down to reach the specified directory.
function FilesPanel:update_tree_root_node(new_root)
  if self.files_root.path ~= new_root then
    local root
    if self.files_root:is_ancestor_of(new_root) then
      log.debug("current root %s is ancestor of new root %q, expanding to it", tostring(self.files_root), new_root)
      -- the new root is located 'below' the current root,
      -- if it's already loaded in the tree, use that node as the root, else expand to it
      root = self.files_root:get_child_if_loaded(new_root)
      if root then
        root:expand({ force_scan = true })
      else
        root = self.files_root:expand({ force_scan = true, to = new_root })
      end
    elseif self.files_root.path:find(Path:new(new_root):absolute(), 1, true) then
      log.debug("current root %s is a child of new root %q, creating parents up to it", tostring(self.files_root), new_root)
      -- the new root is located 'above' the current root,
      -- walk upwards from the current root's parent and see if it's already loaded, if so, us it
      root = self.files_root
      while root.parent do
        root = root.parent --[[@as Yat.Node]]
        root:refresh()
        if root.path == new_root then
          break
        end
      end

      while root.path ~= new_root do
        root = create_root_node(Path:new(root.path):parent().filename, root)
        root:expand()
      end
    else
      log.debug("current root %s is not a child or ancestor of %q", tostring(self.files_root), new_root)
    end

    if not root then
      log.debug("cannot walk the root to find a node for %q", new_root)
      return false
    else
      self.files_root = root
    end
  else
    log.debug("the new root %q is the same as the current root %s, skipping", new_root, tostring(self.files_root))
  end
  return true
end

---@async
---@param path string
function FilesPanel:change_root_node(path)
  if not fs.is_directory(path) then
    path = Path:new(path):parent():absolute() --[[@as string]]
  end
  if path == self.files_root.path then
    return
  end
  local old_root = self.files_root
  log.debug("setting new tree root to %q", path)
  if not self:update_tree_root_node(path) then
    local root = self.files_root
    while root.parent do
      root = root.parent --[[@as Yat.Node]]
    end
    root:walk(maybe_remove_watchers)
    maybe_remove_watchers(root)
    self.files_root = create_root_node(path, self.files_root)
    self.files_root:expand()
  end

  if not self.files_root.repo then
    self:check_node_for_git_repo(self.files_root)
  end
  log.debug("updated tree root to %s, old root was %s", tostring(self.files_root), tostring(old_root))
  self.root = self.files_root
  self.current_node = self.files_root:expand({ to = self.current_node.path }) or self.files_root
  self.mode = "files"
  self:draw(self.current_node)
end

---@return string line
---@return Yat.Ui.HighlightGroup[][] highlights
function FilesPanel:render_header()
  if self.mode == "search" and self.root.search_term then
    local end_of_name = #self.icon + 8
    return self.icon .. "  Search for '" .. self.root.search_term .. "'",
      {
        { name = hl.SECTION_ICON, from = 0, to = #self.icon + 2 },
        { name = hl.SECTION_NAME, from = #self.icon + 2, to = end_of_name },
        { name = hl.DIM_TEXT, from = end_of_name + 1, to = end_of_name + 6 },
        { name = hl.SEARCH_TERM, from = end_of_name + 6, to = end_of_name + 6 + #self.root.search_term },
        { name = hl.DIM_TEXT, from = end_of_name + 6 + #self.root.search_term, to = -1 },
      }
  end
  return self.super:render_header()
end

---@async
---@param path string
---@return Yat.Nodes.Search
local function create_search_root(path)
  local fs_node = fs.node_for(path) --[[@as Yat.Fs.Node]]
  local root = SearchNode:new(fs_node)
  root.repo = git.get_repo_for_path(root.path)
  return root
end

---@async
---@param path string
---@param term string
---@return integer|string matches_or_error
function FilesPanel:search(path, term)
  if self.mode == "files" then
    self.mode = "search"
    self.files_current_node = self.current_node
    self.root = create_search_root(path)
  elseif self.root.path ~= path then
    self.root = create_search_root(path)
  end
  self.current_node = self.root
  local result_node, matches_or_error = self.root:search(term)
  if result_node then
    self.current_node = result_node
    self:draw(self.current_node)
  end
  return matches_or_error
end

---@async
---@param draw? boolean
function FilesPanel:close_search(draw)
  if self.mode == "search" then
    self.mode = "files"
    self.root = self.files_root
    self.current_node = self.files_current_node
    if draw then
      scheduler()
      self:draw(self.current_node)
    end
  end
end

---@protected
---@param node Yat.Node
---@return fun(bufnr: integer, node?: Yat.Node)
---@return string search_root
function FilesPanel:get_complete_func_and_search_root(node)
  local config = require("ya-tree.config").config.panels.files
  local fn, search_root
  if type(config.completion.setup) == "function" then
    ---@param bufnr integer
    fn = function(bufnr)
      local completefunc = config.completion.setup(self, node)
      if completefunc then
        api.nvim_buf_set_option(bufnr, "completefunc", completefunc)
        api.nvim_buf_set_option(bufnr, "omnifunc", "")
      end
    end
    search_root = node.path
  else
    if config.completion.on == "node" then
      ---@param bufnr integer
      fn = function(bufnr)
        return self:complete_func_file_in_path(bufnr, node)
      end
      search_root = node.path
    else
      if config.completion.on ~= "root" then
        utils.warn(string.format("'panels.files.completion.on' is not a recognized value (%q), using 'root'", config.completion.on))
      end
      ---@param bufnr integer
      fn = function(bufnr)
        return self:complete_func_file_in_path(bufnr)
      end
      search_root = self.root.path
    end
  end

  return fn, search_root
end

return FilesPanel

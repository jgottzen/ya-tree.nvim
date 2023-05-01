local lazy = require("ya-tree.lazy")

local async = lazy.require("ya-tree.async") ---@module "ya-tree.async"
local Config = lazy.require("ya-tree.config") ---@module "ya-tree.config"
local fs = lazy.require("ya-tree.fs") ---@module "ya-tree.fs"
local FsNode = lazy.require("ya-tree.nodes.fs_node") ---@module "ya-tree.nodes.fs_node"
local git = lazy.require("ya-tree.git") ---@module "ya-tree.git"
local hl = lazy.require("ya-tree.ui.highlights") ---@module "ya-tree.ui.highlights"
local Logger = lazy.require("ya-tree.log") ---@module "ya-tree.log"
local Path = lazy.require("ya-tree.path") ---@module "ya-tree.path"
local SearchNode = lazy.require("ya-tree.nodes.search_node") ---@module "ya-tree.nodes.search_node"
local TreePanel = require("ya-tree.panels.tree_panel")
local utils = lazy.require("ya-tree.utils") ---@module "ya-tree.utils"

local api = vim.api
local uv = vim.loop

---@class Yat.Panel.Files : Yat.Panel.Tree
---@field new async fun(self: Yat.Panel.Files, sidebar: Yat.Sidebar, config: Yat.Config.Panels.Files, keymap: table<string, Yat.Action>, renderers: { directory: Yat.Panel.Tree.Ui.Renderer[], file: Yat.Panel.Tree.Ui.Renderer[] }): Yat.Panel.Files
---
---@field public TYPE "files"
---@field public root Yat.Node.Filesystem|Yat.Node.Search
---@field public current_node Yat.Node.Filesystem|Yat.Node.Search
---@field private files_root Yat.Node.Filesystem
---@field private files_current_node Yat.Node.Filesystem
---@field public focus_path_on_fs_event? string|"expand"
---@field private mode "files"|"search"
local FilesPanel = TreePanel:subclass("Yat.Panel.Files")

---Creates a new filesystem node tree root.
---@async
---@param path string the path
---@param old_root? Yat.Node.Filesystem the previous root
---@return Yat.Node.Filesystem root
local function create_root_node(path, old_root)
  local fs_node = fs.node_for(path) --[[@as Yat.Fs.Node]]
  local root = FsNode:new(fs_node)

  -- if the tree root was moved on level up, i.e the new root is the parent of the old root, add it to the tree
  if old_root and Path:new(old_root.path):parent().filename == root.path then
    root:add_child(old_root)
    old_root.parent = root
    local repo = old_root.repo
    if repo and vim.startswith(root.path, repo.toplevel) then
      root.repo = repo
    end
  end

  root:expand()
  return root
end

---@async
---@private
---@param sidebar Yat.Sidebar
---@param config Yat.Config.Panels.Files
---@param keymap table<string, Yat.Action>
---@param renderers { directory: Yat.Panel.Tree.Ui.Renderer[], file: Yat.Panel.Tree.Ui.Renderer[] }
function FilesPanel:init(sidebar, config, keymap, renderers)
  local path = uv.cwd() --[[@as string]]
  local root = create_root_node(path)
  local panel_renderers = { container = renderers.directory, leaf = renderers.file }
  TreePanel.init(self, "files", sidebar, config.title, config.icon, keymap, panel_renderers, root)
  self.mode = "files"
  self.files_root = root
  self.files_current_node = root
  self:check_node_for_git_repo(self.files_root)
  self:register_buffer_modified_event()
  self:register_buffer_saved_event()
  self:register_buffer_enter_event()
  self:register_dir_changed_event()
  self:register_dot_git_dir_changed_event()
  self:register_diagnostics_changed_event()
  self:register_fs_changed_event()

  Logger.get("panels").info("created panel %s", tostring(self))
end

---@async
---@private
---@param node Yat.Node.Filesystem
function FilesPanel:check_node_for_git_repo(node)
  Logger.get("panels").debug("checking if %s is in a git repository", node.path)
  local repo = git.create_repo(node.path)
  if repo then
    node:set_git_repo(repo)
    repo:status():refresh({ ignored = true })
  end
end

---@return boolean
function FilesPanel:is_in_search_mode()
  return self.mode == "search"
end

---@param repo Yat.Git.Repo
---@param path string
function FilesPanel:set_git_repo_for_path(repo, path)
  local log = Logger.get("panels")
  local node = self.root:get_node(path) or self.root:get_node(repo.toplevel)
  if node then
    log.debug("setting git repo for panel %s on node %s", self.TYPE, node.path)
    node:set_git_repo(repo)
    self:draw()
  end
  if self.mode == "search" then
    node = self.files_root:get_node(path) or self.files_root:get_node(repo.toplevel)
    if node then
      log.debug("setting git repo for panel %s on node %s", self.TYPE, node.path)
      node:set_git_repo(repo)
    end
  end
end

---@return Yat.Git.Repo[]
function FilesPanel:get_git_repos()
  ---@type table<Yat.Git.Repo, boolean>
  local found_toplevels = {}
  self.files_root:walk(function(node)
    if node.repo then
      if not found_toplevels[node.repo] then
        found_toplevels[node.repo] = true
      end
      if not node.repo:is_yadm() then
        return true
      end
    end
  end)
  return vim.tbl_keys(found_toplevels)
end

function FilesPanel:delete()
  self.files_root:remove_watcher(true)
  TreePanel.delete(self)
end

---@async
---@private
---@param dir string
---@param filenames string[]
function FilesPanel:on_fs_changed_event(dir, filenames)
  local log = Logger.get("panels")
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

  local dir_node = self.files_root:get_node(dir)
  if dir_node and dir_node:is_directory() then
    dir_node:refresh()
    if is_open then
      local new_node = nil
      if self.focus_path_on_fs_event then
        if self.focus_path_on_fs_event == "expand" then
          dir_node:expand()
        else
          local parent = self.files_root:expand({ to = Path:new(self.focus_path_on_fs_event):parent().filename })
          new_node = parent and parent:get_node(self.focus_path_on_fs_event)
        end
        if not new_node then
          local sep = Path.path.sep
          for _, filename in ipairs(filenames) do
            local path = dir .. sep .. filename
            local child = dir_node:get_node(path)
            if child then
              log.debug("setting current node to %q", path)
              new_node = child
              break
            end
          end
        end
      end
      if self.root == self.files_root and self.path_lookup[dir_node.path] then
        async.scheduler()
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

---@protected
function FilesPanel:on_win_opened()
  if Config.config.move_cursor_to_name then
    self:create_move_to_name_autocmd()
  end
  if Config.config.follow_focused_file then
    self:expand_to_current_buffer()
  end
end

---@async
---@param args table<string, string>
function FilesPanel:command_arguments(args)
  local log = Logger.get("panels")
  if args.path then
    local p = Path:new(args.path)
    local path = p:exists() and p:absolute() or nil
    if path then
      local config = Config.config
      local node = self.root:expand({ to = path })
      if node then
        local hidden, reason = node:is_hidden(config)
        if hidden and reason then
          if reason == "filter" then
            config.filters.enable = false
          elseif reason == "git" then
            config.git.show_ignored = true
          end
        end
        log.info("navigating to %q", path)
        self:draw(node)
      else
        log.info('cannot expand to path %q in the "files" panel, changing root', path)
        self:change_root_node(path)
        node = self.root:expand({ to = path })
        if config.cwd.update_from_panel then
          p = Path:new(path)
          path = p:is_dir() and p.filename or p:parent().filename
          log.debug("issueing tcd autocmd to %q", path)
          vim.cmd.tcd(vim.fn.fnameescape(path))
        end
      end
    end
  end
end

---@async
---@private
---@param new_root string
---@return boolean `false` if the current tree cannot walk up or down to reach the specified directory.
function FilesPanel:update_tree_root_node(new_root)
  local log = Logger.get("panels")
  new_root = Path:new(new_root):absolute()
  if self.files_root.path ~= new_root then
    local root --[[@as Yat.Node.Filesystem?]]
    if self.files_root:is_ancestor_of(new_root) then
      log.debug("current root %s is ancestor of new root %q, expanding to it", tostring(self.files_root), new_root)
      -- the new root is located 'below' the current root,
      -- if it's already loaded in the tree, use that node as the root, else expand to it
      root = self.files_root:get_node(new_root)
      if root then
        root:expand({ force_scan = true })
      else
        root = self.files_root:expand({ force_scan = true, to = new_root })
      end
    elseif vim.startswith(self.files_root.path, new_root) then
      log.debug("current root %s is a child of new root %q, creating parents up to it", tostring(self.files_root), new_root)
      -- the new root is located 'above' the current root,
      -- walk upwards from the current root's parent and see if it's already loaded, if so, us it
      root = self.files_root
      while root.parent do
        root = root.parent --[[@as Yat.Node.Filesystem]]
        root:refresh()
        if root.path == new_root then
          break
        end
      end

      while root.path ~= new_root do
        root = create_root_node(Path:new(root.path):parent().filename, root)
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
  local log = Logger.get("panels")
  if not fs.is_directory(path) then
    path = Path:new(path):parent():absolute()
  end
  if path == self.files_root.path then
    return
  end
  local old_root = self.files_root
  log.debug("setting new panel root to %q", path)
  if not self:update_tree_root_node(path) then
    local root = self.files_root
    while root.parent do
      root = root.parent --[[@as Yat.Node.Filesystem]]
    end
    root:remove_watcher(true)
    self.files_root = create_root_node(path, self.files_root)
  end

  if not self.files_root.repo then
    self:check_node_for_git_repo(self.files_root)
  end
  log.debug("updated panel root to %s, old root was %s", tostring(self.files_root), tostring(old_root))
  self.root = self.files_root
  self.current_node = self.files_root:expand({ to = self.current_node.path }) or self.files_root
  self.mode = "files"
  self:draw(self.current_node)
  self.sidebar:remove_unused_git_repos()
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
  return TreePanel.render_header(self)
end

---@async
---@param path string
---@return Yat.Node.Search
local function create_search_root(path)
  local fs_node = fs.node_for(path) --[[@as Yat.Fs.Node]]
  local root = SearchNode:new(fs_node)
  root.repo = git.get_repo_for_path(root.path)
  return root
end

---@async
---@param path string
---@param term string
---@param focus boolean
---@return integer|string matches_or_error
function FilesPanel:search(path, term, focus)
  if self.mode == "files" then
    self.mode = "search"
    self.files_current_node = self.current_node --[[@as Yat.Node.Filesystem]]
    self.root = create_search_root(path)
  elseif self.root.path ~= path then
    self.root = create_search_root(path)
  end
  local root = self.root --[[@as Yat.Node.Search]]
  self.current_node = root
  local result_node, matches_or_error = root:search(term)
  if result_node then
    self.current_node = result_node
    self:draw(focus and self.current_node or nil)
  end
  return matches_or_error
end

---@param draw? boolean
function FilesPanel:close_search(draw)
  if self.mode == "search" then
    self.mode = "files"
    self.root = self.files_root
    self.current_node = self.files_current_node
    if draw then
      async.scheduler()
      self:draw(self.current_node)
    end
  end
end

---@protected
---@param node? Yat.Node.Filesystem|Yat.Node.Search
---@return fun(bufnr: integer)
---@return string search_root
function FilesPanel:get_complete_func_and_search_root(node)
  local config = Config.config.panels.files
  node = node or self.root
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
        self:complete_func_file_in_path(bufnr, node.path)
      end
      search_root = node.path
    else
      if config.completion.on ~= "root" then
        utils.warn(string.format("'panels.files.completion.on' is not a recognized value (%q), using 'root'", config.completion.on))
      end
      ---@param bufnr integer
      fn = function(bufnr)
        self:complete_func_file_in_path(bufnr, self.root.path)
      end
      search_root = self.root.path
    end
  end

  return fn, search_root
end

return FilesPanel

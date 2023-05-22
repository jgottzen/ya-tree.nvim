local lazy = require("ya-tree.lazy")

local async = lazy.require("ya-tree.async") ---@module "ya-tree.async"
local Config = lazy.require("ya-tree.config") ---@module "ya-tree.config"
local fs = lazy.require("ya-tree.fs") ---@module "ya-tree.fs"
local fs_watcher = lazy.require("ya-tree.fs.watcher") ---@module "ya-tree.fs.watcher"
local git = lazy.require("ya-tree.git") ---@module "ya-tree.git"
local GitNode = lazy.require("ya-tree.nodes.git_node") ---@module "ya-tree.nodes.git_node"
local Logger = lazy.require("ya-tree.log") ---@module "ya-tree.log"
local Path = lazy.require("ya-tree.path") ---@module "ya-tree.path"
local TextNode = lazy.require("ya-tree.nodes.text_node") ---@module "ya-tree.nodes.text_node"
local TreePanel = require("ya-tree.panels.tree_panel")
local utils = lazy.require("ya-tree.utils") ---@module "ya-tree.utils"

local uv = vim.loop

---@class Yat.Panel.GitStatus : Yat.Panel.Tree
---@field new async fun(self: Yat.Panel.GitStatus, sidebar: Yat.Sidebar, config: Yat.Config.Panels.GitStatus, keymap: table<string, Yat.Action>, renderers: { directory: Yat.Panel.Tree.Ui.Renderer[], file: Yat.Panel.Tree.Ui.Renderer[] }, repo?: Yat.Git.Repo): Yat.Panel.GitStatus
---
---@field public TYPE "git_status"
---@field public root Yat.Node.Git|Yat.Node.Text
---@field public current_node Yat.Node.Git|Yat.Node.Text
local GitStatusPanel = TreePanel:subclass("Yat.Panel.GitStatus")

---@async
---@param repo Yat.Git.Repo
---@return Yat.Node.Git
local function create_root_node(repo)
  local fs_node = fs.node_for(repo.toplevel) --[[@as Yat.Fs.Node]]
  local root = GitNode:new(fs_node)
  root.repo = repo
  return root
end

---@async
---@private
---@param sidebar Yat.Sidebar
---@param config Yat.Config.Panels.GitStatus
---@param keymap table<string, Yat.Action>
---@param renderers { directory: Yat.Panel.Tree.Ui.Renderer[], file: Yat.Panel.Tree.Ui.Renderer[] }
---@param repo? Yat.Git.Repo
function GitStatusPanel:init(sidebar, config, keymap, renderers, repo)
  if not repo then
    local path = uv.cwd() --[[@as string]]
    repo = git.create_repo(path)
  end
  local root
  if repo then
    root = create_root_node(repo)
  else
    local path = uv.cwd() --[[@as string]]
    root = TextNode:new(path .. " is not a Git repository", "/")
  end
  local panel_renderers = { container = renderers.directory, leaf = renderers.file }
  TreePanel.init(self, "git_status", sidebar, config.title, config.icon, keymap, panel_renderers, root)
  self.current_node = self.root:refresh() or root
  self:register_buffer_modified_event()
  self:register_buffer_saved_event()
  self:register_buffer_enter_event()
  self:register_dot_git_dir_changed_event()
  self:register_diagnostics_changed_event()
  self:register_fs_changed_event()

  Logger.get("panels").info("created panel %s", tostring(self))
end

---@return Yat.Git.Repo[]|nil
function GitStatusPanel:get_git_repos()
  if self.root.TYPE == "git" then
    return { self.root.repo }
  end
end

---@async
---@param _ integer
---@param file string
function GitStatusPanel:on_buffer_saved(_, file)
  if self.root.TYPE == "git" and self.root:is_ancestor_of(file) then
    local root = self.root --[[@as Yat.Node.Git]]
    Logger.get("panels").debug("changed file %q is in tree %s", file, tostring(self))
    local node = root:get_node(file)
    if node then
      node.modified = false
    end
    if Config.config.dir_watcher.enable and fs_watcher.is_watched(Path:new(file):parent():absolute()) then
      -- the directory watcher is enabled, _AND_ the directory is watched, the update will be handled by that event handler
      return
    end
    local git_status = root.repo:status():refresh_path(file)
    if not node and git_status then
      root:add_node(file)
    elseif node and not git_status then
      root:remove_node(file, true)
    end
    self:draw(self:get_current_node())
  end
end

---@async
---@param repo Yat.Git.Repo
function GitStatusPanel:on_dot_git_dir_changed(repo)
  if vim.v.exiting == vim.NIL and self.root.repo == repo and not self.refreshing then
    self.refreshing = true
    Logger.get("panels").debug("git repo %s changed", tostring(self.root.repo))
    self.root:refresh({ refresh_git = false })
    self:draw(self:get_current_node())
    self.refreshing = false
  end
end

---@async
---@private
---@param dir string
---@param filenames string[]
function GitStatusPanel:on_fs_changed_event(dir, filenames)
  local log = Logger.get("panels")
  log.debug("fs_event for dir %q, with entries %s", dir, filenames)

  if not self.refreshing then
    if self.root.TYPE == "git" and self.root:is_ancestor_of(dir) or self.root.path == dir then
      local root = self.root --[[@as Yat.Node.Git]]
      for _, filename in ipairs(filenames) do
        local path = fs.join_path(dir, filename)
        local node = root:get_node(path)
        local git_status = root.repo:status():of(path, false)
        if not node and git_status then
          root:add_node(path)
        elseif node and not git_status then
          root:remove_node(path, true)
        end
      end
      self:draw(self:get_current_node())
    end
  else
    log.info("git tree is refreshing, skipping")
  end
end

---@protected
function GitStatusPanel:on_win_opened()
  if Config.config.move_cursor_to_name then
    self:create_move_to_name_autocmd()
  end
  if Config.config.follow_focused_file then
    self:expand_to_current_buffer()
  end
end

---@async
---@param args table<string, string>
function GitStatusPanel:command_arguments(args)
  if args.dir then
    local p = Path:new(args.dir)
    local path = (p:exists() and p:is_dir()) and p:absolute() or nil
    if path then
      self:change_root_node(path)
    else
      utils.notify(string.format("The path %q does not exist.", args.dir))
    end
  end
end

---@async
---@param path_or_repo string|Yat.Git.Repo
function GitStatusPanel:change_root_node(path_or_repo)
  local repo
  if type(path_or_repo) == "string" then
    repo = git.create_repo(path_or_repo)
  else
    repo = path_or_repo
  end
  if not repo then
    utils.notify(string.format("No Git repository found in %q.", path_or_repo))
    return
  elseif repo == self.root.repo then
    return
  end
  local old_root = self.root
  self.root = create_root_node(repo)
  self.current_node = self.root:refresh() --[[@as Yat.Node.Git]]
  Logger.get("panels").debug("updated tree root to %s, old root was %s", tostring(self.root), tostring(old_root))
  async.scheduler()
  self:draw()
end

---@async
---@param node? Yat.Node.Git
function GitStatusPanel:search_for_node(node)
  self:search_for_loaded_node(function(bufnr)
    local root = Config.config.panels.git_status.completion.on == "node" and node or self.root
    self:complete_func_loaded_nodes(bufnr, false, root)
  end)
end

return GitStatusPanel

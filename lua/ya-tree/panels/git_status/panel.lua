local fs = require("ya-tree.fs")
local git = require("ya-tree.git")
local GitNode = require("ya-tree.nodes.git_node")
local log = require("ya-tree.log").get("panels")
local meta = require("ya-tree.meta")
local scheduler = require("ya-tree.async").scheduler
local TextNode = require("ya-tree.nodes.text_node")
local TreePanel = require("ya-tree.panels.tree_panel")

local uv = vim.loop

---@class Yat.Panel.GitStatus : Yat.Panel.Tree
---@field new async fun(self: Yat.Panel.GitStatus, sidebar: Yat.Sidebar, config: Yat.Config.Panels.GitStatus, keymap: table<string, Yat.Action>, renderers: Yat.Panel.TreeRenderers, repo?: Yat.Git.Repo): Yat.Panel.GitStatus
---@overload async fun(sidebar: Yat.Sidebar, config: Yat.Config.Panels.GitStatus, keymap: table<string, Yat.Action>, renderers: Yat.Panel.TreeRenderers, repo?: Yat.Git.Repo): Yat.Panel.GitStatus
---@field class fun(self: Yat.Panel.GitStatus): Yat.Panel.GitStatus
---@field static Yat.Panel.GitStatus
---@field super Yat.Panel.Tree
---
---@field public TYPE "git_status"
---@field public root Yat.Nodes.Git|Yat.Nodes.Text
---@field public current_node Yat.Nodes.Git|Yat.Nodes.Text
local GitStatusPanel = meta.create_class("Yat.Panel.GitStatus", TreePanel)

---@async
---@param repo Yat.Git.Repo
---@return Yat.Nodes.Git
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
---@param renderers Yat.Panel.TreeRenderers
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
    root = TextNode:new(path .. " is not a Git repository", path, false)
  end
  self.super:init("git_status", sidebar, config.title, config.icon, keymap, renderers, root)
  self.current_node = self.root:refresh() or root
  self:register_buffer_modified_event()
  self:register_buffer_saved_event()
  self:register_buffer_enter_event()
  self:register_dot_git_dir_changed_event()
  self:register_diagnostics_changed_event()
  self:register_fs_changed_event()

  log.info("created panel %s", tostring(self))
end

---@async
---@param _ integer
---@param file string
function GitStatusPanel:on_buffer_saved(_, file)
  if self.root:is_ancestor_of(file) then
    log.debug("changed file %q is in tree %s", file, tostring(self))
    local node = self.root:get_child_if_loaded(file)
    if node then
      node.modified = false
    end
    local git_status = self.root.repo:status():refresh_path(file)
    if not node and git_status then
      self.root:add_node(file)
    elseif node and not git_status then
      self.root:remove_node(file)
    end
    self:draw(self:get_current_node())
  end
end

---@async
---@param repo Yat.Git.Repo
function GitStatusPanel:on_dot_git_dir_changed(repo)
  if vim.v.exiting == vim.NIL and self.root.repo == repo then
    log.debug("git repo %s changed", tostring(self.root.repo))
    self.root:refresh({ refresh_git = false })
    self:draw(self:get_current_node())
  end
end

---@async
---@private
---@param dir string
---@param filenames string[]
function GitStatusPanel:on_fs_changed_event(dir, filenames)
  log.debug("fs_event for dir %q, with files %s", dir, filenames)
  local ui_is_open = self:is_open()

  if self.root:is_ancestor_of(dir) or self.root.path == dir then
    if not self.refreshing then
      self.refreshing = true
      self.root:refresh()
      self.refreshing = false

      if ui_is_open then
        scheduler()
        self:draw(self:get_current_node())
      end
    else
      log.info("git tree is refreshing, skipping")
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
  if not repo or repo == self.root.repo then
    return
  end
  local old_root = self.root
  self.root = create_root_node(repo)
  self.current_node = self.root:refresh() --[[@as Yat.Nodes.Git]]
  log.debug("updated tree root to %s, old root was %s", tostring(self.root), tostring(old_root))
  scheduler()
  self:draw()
end

---@protected
---@return fun(bufnr: integer)
---@return string search_root
function GitStatusPanel:get_complete_func_and_search_root()
  return function(bufnr)
    return self:complete_func_loaded_nodes(bufnr)
  end, self.root.path
end

return GitStatusPanel

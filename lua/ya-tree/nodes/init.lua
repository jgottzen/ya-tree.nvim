local Path = require("plenary.path")

local Node = require("ya-tree.nodes.node")
local BufferNode = require("ya-tree.nodes.buffer_node")
local GitNode = require("ya-tree.nodes.git_node")
local SearchNode = require("ya-tree.nodes.search_node")
local fs = require("ya-tree.filesystem")
local git = require("ya-tree.git")

local M = {}

---Creates a new filesystem node tree root.
---@async
---@param path string the path
---@param old_root? YaTreeNode the previous root
---@return YaTreeNode root
function M.create_filesystem_tree(path, old_root)
  local fs_node = fs.node_for(path) --[[@as FsNode]]
  local root = Node:new(fs_node)

  -- if the tree root was moved on level up, i.e the new root is the parent of the old root, add it to the tree
  if old_root and Path:new(old_root.path):parent().filename == root.path then
    root.children = { old_root }
    old_root.parent = root
    local repo = old_root.repo
    if repo and root.path:find(repo.toplevel, 1, true) then
      root.repo = repo
    end
  end

  -- force scan of the directory
  root:expand({ force_scan = true })

  return root
end

---Creates a search node tree, with `root_path` as the root node.
---@async
---@param root_path string
---@param term string
---@param cmd string
---@param args string[]
---@return YaTreeSearchNode root
---@return YaTreeSearchNode|nil first_leaf_node
---@return number|string matches_or_error
function M.create_search_tree(root_path, term, cmd, args)
  local fs_node = fs.node_for(root_path) --[[@as FsNode]]
  local root = SearchNode:new(fs_node)
  root.repo = git.get_repo_for_path(root_path)
  return root, root:search(term, cmd, args)
end

---Creates a buffer node tree.
---@async
---@param root_path string
---@return YaTreeBufferNode root, YaTreeBufferNode first_leaf_node
function M.create_buffers_tree(root_path)
  local fs_node = fs.node_for(root_path) --[[@as FsNode]]
  local root = BufferNode:new(fs_node)
  root.repo = git.get_repo_for_path(root_path)
  return root, root:refresh()
end

---Creates a git node tree, with the `repo` toplevel as the root node.
---@async
---@param repo GitRepo
---@return YaTreeGitNode root, YaTreeGitNode first_leaft_node
function M.create_git_tree(repo)
  local fs_node = fs.node_for(repo.toplevel) --[[@as FsNode]]
  local root = GitNode:new(fs_node)
  root.repo = repo
  return root, root:refresh()
end

return M

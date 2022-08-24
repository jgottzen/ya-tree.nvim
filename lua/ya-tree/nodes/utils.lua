local scheduler = require("plenary.async.util").scheduler
local Path = require("plenary.path")

local fs = require("ya-tree.filesystem")
local log = require("ya-tree.log")
local utils = require("ya-tree.utils")

local M = {}

---Creates a new node.
---@generic T : YaTreeNode
---@param class `T`
---@param fs_node FsNode filesystem data.
---@param parent? `T` the parent node.
---@return `T` node
function M.create_node(class, fs_node, parent)
  local this = setmetatable(fs_node, class) --[[@as YaTreeNode]]
  ---@cast parent YaTreeNode?
  this.parent = parent
  this.modified = false
  if this:is_container() then
    this.children = {}
  end

  -- inherit any git repo
  if parent and parent.repo then
    this.repo = parent.repo
  end

  log.trace("created node %s", this)

  return this
end

---@async
---@generic T : YaTreeNode
---@param root `T`
---@param paths string[]
---@param node_creator async fun(path: string, parent: `T`): `T`|nil
---@return `T` first_leaf_node
function M.create_tree_from_paths(root, paths, node_creator)
  ---@cast root YaTreeNode
  ---@type table<string, YaTreeNode>
  local node_map = { [root.path] = root }

  ---@param path string
  ---@param parent YaTreeNode
  local function add_node(path, parent)
    local node = node_creator(path, parent)
    if node then
      parent.children[#parent.children + 1] = node
      parent.empty = false
      table.sort(parent.children, root.node_comparator)
      node_map[node.path] = node
    end
  end

  local min_path_size = #root.path
  for _, path in ipairs(paths) do
    if fs.exists(path) then
      ---@type string[]
      local parents = Path:new(path):parents()
      for i = #parents, 1, -1 do
        local parent_path = parents[i]
        -- skip paths 'above' the root node
        if #parent_path > min_path_size then
          local parent = node_map[parent_path]
          if not parent then
            local grand_parent = node_map[parents[i + 1]]
            add_node(parent_path, grand_parent)
          end
        end
      end

      local parent = node_map[parents[1]]
      add_node(path, parent)
    end
  end

  local first_leaf_node = root
  while first_leaf_node and first_leaf_node:is_container() do
    if first_leaf_node.children and first_leaf_node.children[1] then
      first_leaf_node = first_leaf_node.children[1]
    else
      break
    end
  end

  scheduler()
  return first_leaf_node
end

---@async
---@generic T : YaTreeBufferRootNode|YaTreeGitRootNode
---@param root `T`
---@param file string
---@param node_creator fun(fs_node: FsNode, parent: `T`): `T`
---@return `T`|nil node
function M.add_fs_node(root, file, node_creator)
  if not fs.exists(file) then
    log.error("no file node found for %q", file)
    return nil
  end

  ---@cast root YaTreeBufferRootNode|YaTreeGitRootNode
  local rest = file:sub(#root.path + 1)
  ---@type string[]
  local splits = vim.split(rest, utils.os_sep, { plain = true, trimempty = true })
  local node = root
  for i = 1, #splits do
    local name = splits[i]
    local found = false
    for _, child in ipairs(node.children) do
      if child.name == name then
        found = true
        node = child
        break
      end
    end
    if not found then
      local fs_node = fs.node_for(node.path .. utils.os_sep .. name)
      if fs_node then
        local child = node_creator(fs_node, node)
        log.debug("adding child %q to parent %q", child.path, node.path)
        node.children[#node.children + 1] = child
        node.empty = false
        table.sort(node.children, root.node_comparator)
        node = child
      else
        log.error("cannot create fs node for %q", node.path .. utils.os_sep .. name)
        return nil
      end
    end
  end
  scheduler()
  return node
end

---@param root YaTreeBufferRootNode|YaTreeGitRootNode
---@param file string
function M.remove_fs_node(root, file)
  local node = root:get_child_if_loaded(file)
  while node and node.parent and node ~= root do
    if node.parent and node.parent.children then
      for index, child in ipairs(node.parent.children) do
        if child == node then
          log.debug("removing child %q from parent %q", child.path, node.parent.path)
          table.remove(node.parent.children, index)
          break
        end
      end
      if #node.parent.children == 0 then
        node.parent.empty = true
        node = node.parent
      else
        break
      end
    end
  end
end

return M

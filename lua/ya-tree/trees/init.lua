local void = require("plenary.async").void

local git = require("ya-tree.git")
local log = require("ya-tree.log")("trees")

local api = vim.api

local M = {
  ---@private
  ---@type table<Yat.Trees.Type, Yat.Tree>
  _registered_trees = {},
  ---@private
  ---@type table<integer, { [Yat.Trees.Type|"current"|"previous"]: Yat.Tree }>
  _tabpage_trees = {},
}

---@param type Yat.Trees.Type
---@return boolean
local function is_not_special_tree_type(type)
  return type ~= "current" and type ~= "previous"
end

function M.delete_trees_for_nonexisting_tabpages()
  ---@type table<string, boolean>
  local found_toplevels = {}
  local tabpages = api.nvim_list_tabpages()
  for tabpage, trees in pairs(M._tabpage_trees) do
    if not vim.tbl_contains(tabpages, tabpage) then
      for type, tree in pairs(trees) do
        if is_not_special_tree_type(type) then
          tree:delete()
        end
        trees[type] = nil
      end
      log.debug("Deleted trees for tabpage %s", tabpage)
      M._tabpage_trees[tabpage] = nil
    else
      for type, tree in pairs(trees) do
        if is_not_special_tree_type(type) then
          tree.root:walk(function(node)
            if node.repo and not found_toplevels[node.repo.toplevel] then
              found_toplevels[node.repo.toplevel] = true
              if not node.repo:is_yadm() then
                return true
              end
            end
          end)
        end
      end
    end
  end

  for toplevel, repo in pairs(git.repos) do
    if not found_toplevels[toplevel] then
      git.remove_repo(repo)
    end
  end
end

---@return Yat.Trees.Type[]
function M.get_registered_tree_types()
  return vim.tbl_keys(M._registered_trees)
end

---@param callback fun(tree: Yat.Tree)
function M.for_each_tree(callback)
  for _, trees in pairs(M._tabpage_trees) do
    for type, tree in pairs(trees) do
      if is_not_special_tree_type(type) then
        callback(tree)
      end
    end
  end
end

---@param tabpage integer
---@param name Yat.Trees.Type
---@param set_current? boolean
---@return Yat.Tree? tree
function M.get_tree(tabpage, name, set_current)
  local trees = M._tabpage_trees[tabpage]
  if trees then
    local tree = trees[name]
    if tree and set_current then
      trees.previous = trees.current
      trees.current = tree
    end
    return tree
  end
end

---@async
---@param tabpage integer
---@param name Yat.Trees.Type
---@param set_current boolean
---@param ... any tree arguments
---@return Yat.Tree? tree
function M.new_tree(tabpage, name, set_current, ...)
  local trees = M._tabpage_trees[tabpage]
  if not trees then
    trees = {}
    M._tabpage_trees[tabpage] = trees
  end
  if trees[name] then
    trees[name]:delete(tabpage)
    trees[name] = nil
  end
  local class = M._registered_trees[name]
  if class then
    local tree = class:new(tabpage, ...)
    if tree then
      trees[name] = tree
      if set_current then
        trees.previous = trees.current
        trees.current = tree
      end
    end
    return tree
  end
end

---@param tabpage integer
---@param set_current? boolean
---@return Yat.Tree? tree
function M.previous_tree(tabpage, set_current)
  local tree = M._tabpage_trees[tabpage]
  local previous = tree and tree.previous
  if previous and set_current then
    tree.previous = tree.current
    tree.current = previous
  end
  return previous
end

---@param tabpage integer
---@return Yat.Tree? tree
function M.current_tree(tabpage)
  local tree = M._tabpage_trees[tabpage]
  return tree and tree.current
end

---@param tabpage integer
---@param tree Yat.Tree
function M.set_current_tree(tabpage, tree)
  local trees = M._tabpage_trees[tabpage]
  if not trees then
    trees = {}
    M._tabpage_trees[tabpage] = trees
  end
  trees.previous = trees.current
  trees.current = tree
end

---@param tabpage integer
---@param set_current? boolean
---@return Yat.Trees.Filesystem? tree
function M.filesystem(tabpage, set_current)
  return M.get_tree(tabpage, "filesystem", set_current) --[[@as Yat.Trees.Filesystem?]]
end

---@async
---@param tabpage integer
---@param set_current boolean
---@param root? string|Yat.Node
---@return Yat.Trees.Filesystem tree
function M.new_filesystem(tabpage, set_current, root)
  return M.new_tree(tabpage, "filesystem", set_current or false, root) --[[@as Yat.Trees.Filesystem]]
end

---@async
---@param tabpage integer
---@param set_current boolean
---@param root? string|Yat.Node
---@return Yat.Trees.Filesystem tree
function M.filesystem_or_new(tabpage, set_current, root)
  local tree = M.filesystem(tabpage, set_current)
  if not tree then
    tree = M.new_filesystem(tabpage, set_current, root)
  end
  return tree
end

---@param tabpage integer
---@param set_current? boolean
---@return Yat.Trees.Buffers? tree
function M.buffers(tabpage, set_current)
  return M.get_tree(tabpage, "buffers", set_current) --[[@as Yat.Trees.Buffers?]]
end

---@async
---@param tabpage integer
---@param set_current boolean
---@param path string
---@return Yat.Trees.Buffers tree
function M.new_buffers(tabpage, set_current, path)
  return M.new_tree(tabpage, "buffers", set_current or false, path) --[[@as Yat.Trees.Buffers]]
end

---@param tabpage integer
---@param set_current? boolean
---@return Yat.Trees.Git? tree
function M.git(tabpage, set_current)
  return M.get_tree(tabpage, "git", set_current) --[[@as Yat.Trees.Git?]]
end

---@async
---@param tabpage integer
---@param set_current boolean
---@param repo Yat.Git.Repo
---@return Yat.Trees.Git tree
function M.new_git(tabpage, set_current, repo)
  return M.new_tree(tabpage, "git", set_current or false, repo) --[[@as Yat.Trees.Git]]
end

---@param tabpage integer
---@param set_current? boolean
---@return Yat.Trees.Search? tree
function M.search(tabpage, set_current)
  return M.get_tree(tabpage, "search", set_current) --[[@as Yat.Trees.Search?]]
end

---@async
---@param tabpage integer
---@param set_current boolean
---@param path string
---@return Yat.Trees.Search
function M.new_search(tabpage, set_current, path)
  return M.new_tree(tabpage, "search", set_current or false, path) --[[@as Yat.Trees.Search]]
end

---@async
---@param scope "window"|"tabpage"|"global"|"auto"
---@param new_cwd string
local function on_cwd_changed(scope, new_cwd)
  log.debug("scope=%s, cwd=%s", scope, new_cwd)

  local current_tabpage = api.nvim_get_current_tabpage() --[[@as integer]]
  -- Do the current tabpage first
  if scope == "tabpage" or scope == "global" then
    local trees = M._tabpage_trees[current_tabpage] or {}
    for type, tree in pairs(trees) do
      if is_not_special_tree_type(type) then
        tree:on_cwd_changed(new_cwd)
      end
    end
  end
  if scope == "global" then
    for tabpage, trees in ipairs(M._tabpage_trees) do
      if tabpage ~= current_tabpage then
        for type, tree in pairs(trees) do
          if is_not_special_tree_type(type) then
            tree:on_cwd_changed(new_cwd)
          end
        end
      end
    end
  end
end

---@async
---@param new_cwd string
function M.change_cwd_for_current_tabpage(new_cwd)
  void(on_cwd_changed)("tabpage", new_cwd)
end

---@param config Yat.Config
local function register_trees(config)
  for tree_name in pairs(config.trees) do
    if tree_name ~= "global_mappings" then
      ---@type boolean, Yat.Tree?
      local ok, tree = pcall(require, "ya-tree.trees." .. tree_name)
      if ok and tree and type(tree.setup) == "function" and type(tree.TYPE) == "string" and type(tree.new) == "function" then
        log.debug("registering tree %q", tree.TYPE)
        tree.setup(config)
        M._registered_trees[tree.TYPE] = tree
      end
    end
  end

  ---@type table<Yat.Actions.Name, Yat.Trees.Type[]>
  local supported_actions = {}
  for type, tree in pairs(M._registered_trees) do
    for _, name in ipairs(tree.supported_actions) do
      local trees = supported_actions[name]
      if not trees then
        trees = {}
        supported_actions[name] = trees
      end
      trees[#trees + 1] = type
    end
  end

  ---@return table<Yat.Actions.Name, Yat.Trees.Type[]>
  function M.actions_supported_by_trees()
    return supported_actions
  end
end

---@param config Yat.Config
function M.setup(config)
  register_trees(config)

  if config.cwd.follow then
    local group = api.nvim_create_augroup("YaTreeTrees", { clear = true })
    api.nvim_create_autocmd("DirChanged", {
      group = group,
      pattern = "*",
      callback = function(input)
        -- currently not available in the table passed to the callback
        if not vim.v.event.changed_window then
          -- if the autocmd was fired because of a switch to a tab or window with a different
          -- cwd than the previous tab/window, it can safely be ignored.
          void(on_cwd_changed)(input.match, input.file)
        end
      end,
      desc = "YaTree DirChanged handler",
    })
  end
end

return M

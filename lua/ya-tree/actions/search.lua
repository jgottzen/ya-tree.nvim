local scheduler = require("plenary.async.util").scheduler
local void = require("plenary.async").void

local lib = require("ya-tree.lib")
local ui = require("ya-tree.ui")
local Input = require("ya-tree.ui.input")
local utils = require("ya-tree.utils")

local uv = vim.loop

local M = {}

---@async
---@param sidebar Yat.Sidebar
---@param tree Yat.Trees.Search
---@param term string
local function search(sidebar, tree, term)
  local matches_or_error = tree:search(term)
  if type(matches_or_error) == "number" then
    utils.notify(string.format("Found %s matches for %q in %q", matches_or_error, term, tree.root.path))
    sidebar:update(tree, tree.current_node)
  else
    utils.warn(string.format("Failed with message:\n\n%s", matches_or_error))
  end
end

---@async
---@param tree Yat.Tree
---@param node? Yat.Node
---@param context Yat.Action.FnContext
function M.search_interactively(tree, node, context)
  local sidebar = context.sidebar
  node = node or tree.root
  -- if the node is a file, search in the directory
  if not node:is_directory() and node.parent then
    node = node.parent --[[@as Yat.Node]]
  end
  local timer = uv.new_timer() --[[@as Luv.Timer]]
  local search_tree = sidebar:search_tree(node.path)

  ---@param ms integer
  ---@param term string
  local function delayed_search(ms, term)
    timer:start(ms, 0, function()
      void(search)(sidebar, search_tree, term)
    end)
  end

  local border = require("ya-tree.config").config.view.popups.border
  local term = ""
  scheduler()
  local height, width = sidebar:get_window_size()
  local input = Input:new({ prompt = "Search:", relative = "win", row = height, col = 0, width = width - 2, border = border }, {
    ---@param text string
    on_change = void(function(text)
      if text == term or text == nil then
        return
      elseif #text == 0 and #term > 0 then
        -- reset search
        term = text
        timer:stop()
        search_tree:reset()
        scheduler()
        sidebar:update()
      else
        term = text
        local length = #term
        local delay = 500
        if length > 5 then
          delay = 100
        elseif length > 3 then
          delay = 200
        elseif length > 2 then
          delay = 400
        end

        delayed_search(delay, term)
      end
    end),
    ---@param text string
    on_submit = void(function(text)
      if text ~= term or timer:is_active() then
        timer:stop()
        search(sidebar, search_tree, text)
      else
        -- let the ui catch up, so that the cursor doens't 'jump' one character left...
        scheduler()
        context.sidebar:focus_node(search_tree, search_tree.current_node)
      end
      timer:close()
    end),
    on_close = void(function()
      timer:stop()
      timer:close()
      sidebar:close_tree(search_tree)
      sidebar:update()
    end),
  })
  input:open()
end

---@async
---@param tree Yat.Tree
---@param node? Yat.Node
---@param context Yat.Action.FnContext
function M.search_once(tree, node, context)
  node = node or tree.root
  -- if the node is a file, search in the directory
  if not node:is_directory() and node.parent then
    node = node.parent --[[@as Yat.Node]]
  end

  local term = ui.input({ prompt = "Search:" })
  if term then
    search(context.sidebar, context.sidebar:search_tree(node.path), term)
  end
end

---@async
---@param tree Yat.Tree
---@param node? Yat.Node
---@param context Yat.Action.FnContext
function M.search_for_node_in_tree(tree, node, context)
  node = node or tree.root
  local completion = type(tree.complete_func) == "function" and function(bufnr)
    tree:complete_func(bufnr, node)
  end or type(tree.complete_func) == "string" and tree.complete_func or nil
  local border = require("ya-tree.config").config.view.popups.border
  local input = Input:new({ prompt = "Path:", completion = completion, border = border }, {
    on_submit = void(function(path)
      if path then
        lib.search_for_node_in_tree(context.sidebar, tree, path)
      end
    end),
  })
  input:open()
end

return M

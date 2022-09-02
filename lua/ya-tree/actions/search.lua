local scheduler = require("plenary.async.util").scheduler
local void = require("plenary.async").void

local lib = require("ya-tree.lib")
local ui = require("ya-tree.ui")
local Input = require("ya-tree.ui.input")

local uv = vim.loop

local M = {}

---@async
---@param _ YaTree
---@param node YaTreeNode
function M.search_interactively(_, node)
  -- if the node is a file, search in the directory
  if node:is_file() and node.parent then
    node = node.parent --[[@as YaTreeNode]]
  end
  ---@type uv_timer_t
  local timer = uv.new_timer()
  ---@type fun(node: YaTreeNode, term: string)
  local search = void(lib.search)

  ---@param ms number
  ---@param term string
  local function delayed_search(ms, term)
    timer:start(ms, 0, function()
      search(node, term)
    end)
  end

  local border = require("ya-tree.config").config.view.popups.border
  local term = ""
  local height, width = ui.get_size()
  local input = Input:new({ prompt = "Search:", relative = "win", row = height, col = 0, width = width - 2, border = border }, {
    ---@param text string
    on_change = void(function(text)
      if text == term or text == nil then
        return
      elseif #text == 0 and #term > 0 then
        -- reset search
        term = text
        timer:stop()
        scheduler()
        lib.close_search()
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
        lib.search(node, text)
      else
        -- let the ui catch up, so that the cursor doens't 'jump' one character left...
        scheduler()
        lib.focus_first_search_result()
      end
      timer:close()
    end),
    on_close = void(function()
      timer:stop()
      timer:close()
      lib.close_search()
    end),
  })
  input:open()
end

---@async
---@param _ YaTree
---@param node YaTreeNode
function M.search_once(_, node)
  -- if the node is a file, search in the directory
  if node:is_file() and node.parent then
    node = node.parent --[[@as YaTreeNode]]
  end

  local term = ui.input({ prompt = "Search:" })
  if term then
    lib.search(node, term)
  end
end

---@async
---@param tree YaTree
function M.search_for_path_in_tree(tree)
  local border = require("ya-tree.config").config.view.popups.border
  local input = Input:new({ prompt = "Path:", completion = "file_in_path", border = border }, {
    on_submit = void(function(path)
      if path then
        lib.search_for_node_in_tree(tree, path)
      end
    end),
  })
  input:open()
end

return M

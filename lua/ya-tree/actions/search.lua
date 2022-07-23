local void = require("plenary.async").void

local lib = require("ya-tree.lib")
local ui = require("ya-tree.ui")
local Input = require("ya-tree.ui.input")

local uv = vim.loop

local M = {}

---@async
---@param node YaTreeNode
function M.search_interactively(node)
  -- if the node is a file, search in the directory
  if node:is_file() and node.parent then
    node = node.parent --[[@as YaTreeNode]]
  end
  ---@type uv_timer_t
  local timer = uv.new_timer()
  ---@type fun(node: YaTreeNode, term: string, focus_node: boolean)
  local search = void(lib.search)

  ---@param ms number
  ---@param term string
  local function delayed_search(ms, term)
    timer:start(ms, 0, function()
      -- focus_node has to be false, otherwise the cursor will jump in the input window when
      -- focus switches to the tree window to move the cursor and then back to the input window
      search(node, term, false)
    end)
  end

  local term = ""
  local height, width = ui.get_size()
  local input = Input:new({ prompt = "Search:", relative = "win", row = height, col = 0, width = width - 2 }, {
    ---@param text string
    on_change = void(function(text)
      if text == term or text == nil then
        return
      elseif #text == 0 and #term > 0 then
        -- reset search
        term = text
        timer:stop()
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
        lib.search(node, text, true)
      else
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
---@param node YaTreeNode
function M.search_once(node)
  -- if the node is a file, search in the directory
  if node:is_file() and node.parent then
    node = node.parent --[[@as YaTreeNode]]
  end

  local term = ui.input({ prompt = "Search:" })
  if term then
    lib.search(node, term, true)
  end
end

---@async
function M.search_for_path_in_tree()
  local input = Input:new({ prompt = "Path:", completion = "file_in_path" }, {
    on_submit = void(function(path)
      if path then
        lib.search_for_node_in_tree(path)
      end
    end),
  })
  input:open()
end

return M

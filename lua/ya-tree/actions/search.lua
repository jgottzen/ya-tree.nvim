local lib = require("ya-tree.lib")
local ui = require("ya-tree.ui")
local Input = require("ya-tree.ui.input")

local uv = vim.loop

local M = {}

---@param node YaTreeNode
function M.search_interactively(node)
  -- if the node is a file, search in the directory
  if node:is_file() and node.parent then
    node = node.parent
  end
  ---@type uv_timer_t
  local timer = uv.new_timer()

  ---@param ms number
  ---@param term string
  local function delayed_search(ms, term)
    timer:start(ms, 0, function()
      lib.search(node, term, false)
    end)
  end

  local term = ""
  local height, width = ui.get_size()
  local input = Input:new({ prompt = "Search:", relative = "win", row = height, col = 0, width = width - 2 }, {
    ---@param text string
    on_change = function(text)
      if text == term or text == nil then
        return
      elseif #text == 0 and #term > 0 then
        -- reset search
        term = text
        timer:stop()
        vim.schedule(function()
          lib.close_search()
        end)
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
    end,
    ---@param text string
    on_submit = function(text)
      if text ~= term then
        term = text
        timer:stop()
        lib.search(node, text, true)
      else
        lib.focus_first_search_result()
      end
    end,
    on_close = function()
      lib.close_search()
    end,
  })
  input:open()
end

---@param node YaTreeNode
function M.search_once(node)
  -- if the node is a file, search in the directory
  if node:is_file() and node.parent then
    node = node.parent
  end

  vim.ui.input({ prompt = "Search:" }, function(term)
    if term then
      lib.search(node, term, true)
    end
  end)
end

return M

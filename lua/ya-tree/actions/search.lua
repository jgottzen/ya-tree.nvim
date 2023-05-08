local lazy = require("ya-tree.lazy")

local async = lazy.require("ya-tree.async") ---@module "ya-tree.async"
local nui = lazy.require("ya-tree.ui.nui") ---@module "ya-tree.ui.nui"
local ui = lazy.require("ya-tree.ui") ---@module "ya-tree.ui"
local utils = lazy.require("ya-tree.utils") ---@module "ya-tree.utils"

local uv = vim.loop

local M = {}

---@async
---@param panel Yat.Panel.Tree
---@param node? Yat.Node
function M.search_for_node_in_panel(panel, node)
  panel:search_for_node(node)
end

---@async
---@param panel Yat.Panel.Files
---@param root string
---@param term string
---@param focus_node boolean
local function search(panel, root, term, focus_node)
  local matches_or_error = panel:search(root, term, focus_node)
  if type(matches_or_error) == "number" then
    utils.notify(string.format("Found %s matches for %q in %q", matches_or_error, term, panel.root.path))
  else
    utils.warn(string.format("Failed with message:\n\n%s", matches_or_error))
  end
end

---@async
---@param panel Yat.Panel.Files
---@param node? Yat.Node.Filesystem|Yat.Node.Search
function M.search_interactively(panel, node)
  node = node or panel.root
  -- if the node is a file, search in the directory
  if not node:is_directory() then
    node = node.parent --[[@as Yat.Node.Filesystem|Yat.Node.Search]]
  end
  ---@cast node -?
  local timer = uv.new_timer() --[[@as uv_timer_t]]

  ---@param ms integer
  ---@param term string
  local function delayed_search(ms, term)
    timer:start(ms, 0, function()
      async.void(search)(panel, node.path, term, false)
    end)
  end

  local term = ""
  local height, width = panel:size()
  nui.input({ title = "Search:", relative = "win", row = height - 2, col = 0, width = width - 2 }, {
    ---@param text string
    on_change = async.void(function(text)
      if text == term or text == nil then
        return
      elseif #text == 0 and #term > 0 then
        -- reset search
        timer:stop()
        term = text
        panel:close_search(true)
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
    on_submit = async.void(function(text)
      if text ~= term or timer:is_active() then
        timer:stop()
        search(panel, node.path, text, true)
      else
        -- let the ui catch up, so that the cursor doens't 'jump' one character left...
        async.scheduler()
        panel:focus_node(panel.current_node)
      end
      timer:close()
    end),
    on_close = async.void(function()
      timer:stop()
      timer:close()
      panel:close_search(true)
    end),
  })
end

---@async
---@param panel Yat.Panel.Files
---@param node? Yat.Node.Filesystem|Yat.Node.Search
function M.search_once(panel, node)
  node = node or panel.root
  -- if the node is a file, search in the directory
  if not node:is_directory() then
    node = node.parent --[[@as Yat.Node.Filesystem|Yat.Node.Search]]
  end

  local term = ui.nui_input({ title = " Search: " })
  if term then
    search(panel, node.path, term, true)
  end
end

---@async
---@param panel Yat.Panel.Files
---@param _ Yat.Node.Filesystem|Yat.Node.Search
function M.close_search(panel, _)
  panel:close_search(true)
end

return M

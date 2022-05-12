local async = require("plenary.async")
local scheduler = require("plenary.async.util").scheduler

local lib = require("ya-tree.lib")
local job = require("ya-tree.job")
local ui = require("ya-tree.ui")
local Input = require("ya-tree.ui.input")
local utils = require("ya-tree.utils")
local log = require("ya-tree.log")

local fn = vim.fn
local uv = vim.loop

local M = {}

---@type boolean
local fd_has_max_results
---@type boolean
local fdfind_has_max_results
do
  ---@param cmd string
  ---@return boolean
  local function has_max_results(cmd)
    local test = fn.system(cmd .. " this_is_only_a_test_search --max-depth=1 --max-results=1")
    return not test:match("^error:")
  end

  local has_fd = fn.executable("fd") == 1
  local has_fdfind = fn.executable("fdfind") == 1
  fd_has_max_results = has_fd and has_max_results("fd")
  fdfind_has_max_results = has_fdfind and has_max_results("fdfind")
end

---@param term string
---@param path string
---@param config YaTreeConfig
---@return string cmd, string[] arguments
local function build_search(term, path, config)
  local cmd = config.search.cmd

  ---@type string[]
  local args
  if type(config.search.args) == "function" then
    args = config.search.args(cmd, term, path, config)
  else
    if cmd == "fd" or cmd == "fdfind" then
      args = { "--color=never", "-tf", "-td", "-tl" }
      if not config.filters.enable or not config.filters.dotfiles then
        table.insert(args, "--hidden")
      end
      if config.filters.enable then
        for name, _ in pairs(config.filters.custom) do
          table.insert(args, "--exclude")
          table.insert(args, name)
        end
      end
      if config.git.show_ignored then
        table.insert(args, "--no-ignore")
      end
      if (fd_has_max_results or fdfind_has_max_results) and config.search.max_results > 0 then
        table.insert(args, "--max-results=" .. config.search.max_results)
      end
      table.insert(args, "--glob")
      table.insert(args, term)
      table.insert(args, path)
    elseif cmd == "find" then
      args = { path, "-type", "f,d,l" }
      if config.filters.enable and config.filters.dotfiles then
        table.insert(args, "-not")
        table.insert(args, "-path")
        table.insert(args, "*/.*")
      end
      table.insert(args, "-iname")
      table.insert(args, term)
    elseif cmd == "where" then
      args = { "/r", path, term }
    else
      -- no search command available
      return
    end

    if type(config.search.args) == "table" then
      for _, arg in ipairs(config.search.args) do
        table.insert(args, arg)
      end
    end
  end

  return cmd, args
end

---@async
---@param term string
---@param node YaTreeNode
---@param focus_node boolean
---@param config YaTreeConfig
local function search(term, node, focus_node, config)
  local search_term = term
  if term ~= "*" and not term:find("*") then
    search_term = "*" .. term .. "*"
  end
  local cmd, args = build_search(search_term, node.path, config)
  if not cmd then
    utils.warn("No suitable search command found!")
    return
  end

  log.debug("searching for %q in %q", term, node.path)

  scheduler()
  job.run({ cmd = cmd, args = args, cwd = node.path, wrap_callback = true }, function(code, stdout, stderr)
    if code == 0 then
      ---@type string[]
      local lines = vim.split(stdout or "", "\n", { plain = true, trimempty = true })
      utils.notify(string.format("%q found %s matches", cmd, #lines))
      lib.display_search_result(node, term, lines, focus_node)
    else
      stderr = vim.split(stderr or "", "\n", { plain = true, trimempty = true })
      stderr = table.concat(stderr, " ")
      utils.warn(string.format("Search failed with code %s and message %s", code, stderr))
    end
  end)
end

---@param node YaTreeNode
function M.live_search(node)
  if not node then
    return
  end

  -- if the node is a file, search in the directory
  if node:is_file() and node.parent then
    node = node.parent
  end
  local config = require("ya-tree.config").config
  local timer = uv.new_timer()

  ---@param ms number
  ---@param term string
  local function delayed_search(ms, term)
    -- stylua: ignore
    timer:start(ms, 0, async.void(function()
      search(term, node, false, config)
    end))
  end

  local term = ""
  local height, width = ui.get_size()
  local input = Input:new({ title = "Search:", relative = "win", row = height, col = 0, width = width - 2 }, {
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
        search(text, node, true, config)
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
function M.search(node)
  if not node then
    return
  end

  -- if the node is a file, search in the directory
  if node:is_file() and node.parent then
    node = node.parent
  end

  async.void(function()
    local term = ui.input({ prompt = "Search:" })
    if term then
      local config = require("ya-tree.config").config
      search(term, node, true, config)
    end
  end)()
end

return M

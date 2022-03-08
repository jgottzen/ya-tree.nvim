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

local has_fd = fn.executable("fd") == 1
local has_fdfind = fn.executable("fdfind") == 1
local has_find = fn.executable("find") == 1
local has_where = fn.executable("where") == 1
local has_win32 = fn.has("win32") == 1

local fd_has_max_results
local fdfind_has_max_results
do
  local function has_max_results(cmd)
    local test = fn.system(cmd .. " this_is_only_a_test_search --max-depth=1 --max-results=1")
    return not test:match("^error:")
  end

  fd_has_max_results = has_fd and has_max_results("fd")
  fdfind_has_max_results = has_fdfind and has_max_results("fdfind")
end

local function build_search(term, path, config)
  local cmd, args
  if config.search.cmd then
    cmd = config.search.cmd
  elseif has_fd then
    cmd = "fd"
  elseif has_fdfind then
    cmd = "fdfind"
  elseif has_find and not has_win32 then
    cmd = "find"
  elseif has_where then
    cmd = "where"
  end

  if type(config.search.args) == "table" then
    args = config.search.args(cmd, term, path, config)
  else
    if cmd == "fd" or cmd == "fdfind" then
      args = { "--color=never" }
      if config.filters.enable then
        if not config.filters.dotfiles then
          table.insert(args, "--hidden")
        end
      end
      if config.git.show_ignored then
        table.insert(args, "--no-ignore")
      end
      if fd_has_max_results or fdfind_has_max_results then
        table.insert(args, "--max-results=" .. (config.search.max_results or 200))
      end
      table.insert(args, "--glob")
      table.insert(args, term)
      table.insert(args, path)
    elseif cmd == "find" then
      args = { path, "-type", "f,d" }
      if config.filters.enable then
        if not config.filters.dotfiles then
          table.insert(args, "-not")
          table.insert(args, "-path")
          table.insert(args, "*/.*")
        end
      end
      table.insert(args, "-iname")
      table.insert(args, term)
    elseif cmd == "where" then
      args = { "/r", path, term }
    else
      return
    end
  end
  if type(config.search.args) == "table" then
    for _, v in ipairs(config.search.args) do
      table.insert(args, v)
    end
  end

  return cmd, args
end

local function search(term, node, config, focus_node)
  local search_term = term
  if term ~= "*" and not term:find("*") then
    search_term = "*" .. term .. "*"
  end
  local cmd, args = build_search(search_term, node.path, config)
  if not cmd then
    utils.print_error("No suitable search command found!")
    return
  end

  log.debug("searching for %q in %q", term, node.path)

  scheduler()

  job.run({ cmd = cmd, args = args, cwd = node.path }, function(code, stdout, stderr)
    if code == 0 then
      log.debug("search result: %s", stdout)
      local lines = vim.split(stdout or "", "\n", true)
      if lines[#lines] == "" then
        lines[#lines] = nil
      end
      vim.schedule(function()
        lib.display_search_result(node, term, lines)

        if focus_node then
          lib.focus_first_search_result()
        end
      end)
    else
      vim.schedule(function()
        utils.print_error(string.format("Search failed with code %s and message %s", code, stderr))
      end)
    end
  end)
end

function M.live_search(node, config)
  if not node then
    return
  end

  -- if the node is a file, search in the directory
  if node:is_file() and node.parent then
    node = node.parent
  end

  local winid, height, width = ui.get_ui_winid_and_size()
  if not winid then
    return
  end

  local timer = uv.new_timer()
  local function debounce(fun)
    local started = false

    return function(ms, ...)
      local args = { ... }
      if started then
        started = false
        timer:stop()
      end
      timer:start(ms, 0, function()
        started = false
        vim.schedule_wrap(fun)(unpack(args))
      end)
      started = true
    end
  end

  local search_debounced = debounce(function(term)
    async.run(function()
      search(term, node, config)
    end)
  end)

  local term = ""
  local anchor = config.view.side == "left" and "SW" or "SE"
  local input = Input:new({ title = "Search:", win = winid, anchor = anchor, row = height, col = 0, size = width - 2 }, {
    on_change = function(value)
      if value == term or value == nil then
        return
      elseif #value == 0 and #term > 0 then
        -- reset search
        term = value
        timer:stop()
        vim.schedule(function()
          lib.clear_search()
        end)
      else
        term = value
        local length = #term
        local delay
        if length > 5 then
          delay = 100
        elseif length > 3 then
          delay = 200
        elseif length > 2 then
          delay = 400
        else
          delay = 500
        end

        search_debounced(delay, term)
      end
    end,
    on_submit = function()
      ui.reset_ui_window()
      lib.focus_first_search_result()
    end,
    on_close = function()
      ui.reset_ui_window()
      lib.clear_search()
    end,
  })

  input:open()
end

function M.search(node, config)
  if not node then
    return
  end

  -- if the node is a file, search in the directory
  if node:is_file() and node.parent then
    node = node.parent
  end

  async.run(function()
    scheduler()

    local term = ui.input({ prompt = "Search:" })
    if not term then
      return
    end

    search(term, node, config, true)
  end)
end

return M

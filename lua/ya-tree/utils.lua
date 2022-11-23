local Path = require("plenary.path")

local api = vim.api
local fn = vim.fn
local uv = vim.loop
local os_sep = Path.path.sep

local M = {}

---@param tbl table
---@param value any
function M.tbl_remove(tbl, value)
  for i = #tbl, 1, -1 do
    if tbl[i] == value then
      table.remove(tbl, i)
    end
  end
end

---@generic T
---@param list T[]
---@return T[] list
function M.tbl_unique(list)
  local uniques = {}
  for _, v in pairs(list) do
    if v ~= nil then
      uniques[v] = true
    end
  end
  return vim.tbl_keys(uniques)
end

M.os_sep = os_sep
M.is_linux = fn.has("unix") == 1
M.is_macos = not M.is_linux and (fn.has("mac") == 1 or fn.has("macunix") == 1)
M.is_windows = not M.is_macos and (fn.has("win32") == 1 or fn.has("win32unix") == 1)

do
  ---@type table<string, boolean>
  local extensions

  ---@param extension string
  ---@return boolean
  function M.is_windows_exe(extension)
    if not extensions then
      local splits = vim.split(string.gsub(vim.env.PATHEXT or "", "%.", ""), ";", { plain = true }) --[=[@as string[]]=]
      for _, ext in pairs(splits) do
        extensions[ext:upper()] = true
      end
    end

    return extensions[extension:upper()] or false
  end
end

---@param path string
---@return boolean is_absolute
function M.is_absolute_path(path)
  if os_sep == "\\" then
    return string.match(path, "^[%a]:\\.*$") ~= nil
  end
  return string.sub(path, 1, 1) == os_sep
end

---@param paths string[]
---@return string|nil path
function M.find_common_ancestor(paths)
  if #paths == 0 then
    return nil
  end

  table.sort(paths, function(a, b)
    return #a < #b
  end)
  ---@type string[]
  local common_ancestor = {}
  ---@type string[][]
  local splits = {}
  for i, path in ipairs(paths) do
    splits[i] = vim.split(Path:new(path):absolute(), os_sep, { plain = true })
  end

  for pos, dir_name in ipairs(splits[1]) do
    local matched = true
    local split_index = 2
    while split_index <= #splits and matched do
      if #splits[split_index] < pos then
        matched = false
        break
      end
      matched = splits[split_index][pos] == dir_name
      split_index = split_index + 1
    end
    if matched then
      common_ancestor[#common_ancestor + 1] = dir_name
    else
      break
    end
  end

  local path = table.concat(common_ancestor, os_sep)
  if #path == 0 then
    return nil
  else
    return path
  end
end

---@param path string
---@return boolean is_root
function M.is_root_directory(path)
  if os_sep == "\\" then
    return string.match(path, "^[A-Z]:\\?$")
  end
  return path == "/"
end

---@param first string
---@param second string
---@return string path
function M.join_path(first, second)
  if M.is_root_directory(first) then
    return string.format("%s%s", first, second)
  else
    return string.format("%s%s%s", first, os_sep, second)
  end
end

---@param path string
---@param root string
---@return string relative_path
function M.relative_path_for(path, root)
  return Path:new(path):make_relative(root)
end

do
  local units = { "B", "KB", "MB", "GB", "TB" }
  local log1024 = math.log(1024)

  -- taken from nvim-tree
  ---@param size integer
  ---@return string
  function M.format_size(size)
    size = math.max(size, 0)
    local pow = math.floor((size and math.log(size) or 0) / log1024)
    pow = math.min(pow, #units)

    local value = size / (1024 ^ pow)
    value = math.floor((value * 10) + 0.5) / 10

    pow = pow + 1

    return (units[pow] == nil) and (size .. " B") or (value .. " " .. units[pow])
  end
end

---@param path string
---@return boolean is_directory
local function is_directory(path)
  local stat = uv.fs_stat(path) --[[@as Luv.Fs.Stat?]]
  return stat and stat.type == "directory" or false
end

---@return boolean
function M.is_buffer_directory()
  local bufnr = api.nvim_get_current_buf()
  local bufname = api.nvim_buf_get_name(bufnr)
  if not is_directory(bufname) then
    return false
  end
  if api.nvim_buf_get_option(bufnr, "filetype") ~= "" then
    return false
  end

  local lines = api.nvim_buf_get_lines(bufnr, 0, -1, false)
  return #lines == 0 or (#lines == 1 and lines[1] == "")
end

do
  ---@param cmd string
  ---@return boolean
  local function has_max_results(cmd)
    local test = fn.system(cmd .. " this_is_only_a_test_search --max-depth=1 --max-results=1")
    return not test:match("^error:")
  end
  ---@type boolean?, boolean?
  local fd_has_max_results, fdfind_has_max_results

  ---@param term string
  ---@param path string
  ---@param glob boolean
  ---@return string|nil cmd, string[] arguments
  function M.build_search_arguments(term, path, glob)
    local config = require("ya-tree.config").config
    local cmd = config.search.cmd

    local args
    if type(config.search.args) == "function" and cmd then
      args = config.search.args(cmd, term, path, config)
    else
      if cmd == "fd" or cmd == "fdfind" then
        if not fd_has_max_results or not fdfind_has_max_results then
          if coroutine.running() then
            require("plenary.async.util").scheduler()
          end
          fd_has_max_results = fn.executable("fd") == 1 and has_max_results("fd")
          fdfind_has_max_results = fn.executable("fdfind") == 1 and has_max_results("fdfind")
        end

        args = { "--color=never" }
        if not config.filters.enable or not config.filters.dotfiles then
          table.insert(args, "--hidden")
        end
        if config.filters.enable then
          for _, name in ipairs(config.filters.custom) do
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
        if glob then
          table.insert(args, "--glob")
          if term ~= "*" and not term:find("*") then
            term = "*" .. term .. "*"
          end
          table.insert(args, term)
        else
          table.insert(args, "--full-path")
          table.insert(args, term)
        end
        table.insert(args, path)
      elseif cmd == "find" then
        args = { path }
        if config.filters.enable and config.filters.dotfiles then
          table.insert(args, "-not")
          table.insert(args, "-path")
          table.insert(args, "*/.*")
        end
        if term ~= "*" and not term:find("*") then
          term = "*" .. term .. "*"
        end
        if glob then
          table.insert(args, "-iname")
          table.insert(args, term)
        else
          table.insert(args, "-ipath")
          table.insert(args, "*" .. term .. "*")
        end
      elseif cmd == "where" then
        if term ~= "*" and not term:find("*") then
          term = "*" .. term .. "*"
        end
        args = { "/r", path, term }
      else
        -- no search command available
        return nil, {}
      end

      if type(config.search.args) == "table" then
        for _, arg in ipairs(config.search.args) do
          table.insert(args, arg)
        end
      end
    end

    return cmd, args
  end
end

do
  local has_notify_plugin, notify = pcall(require, "notify")

  ---@param message string message
  ---@param level? integer default: `vim.log.levels.INFO`
  ---@see vim.log.levels
  function M.notify(message, level)
    level = level or vim.log.levels.INFO
    if has_notify_plugin and notify == vim.notify then
      vim.notify(message, level, { title = "YaTree" })
    else
      vim.notify(string.format("[ya-tree] %s", message), level)
    end
  end

  ---@param message string message
  function M.warn(message)
    M.notify(message, vim.log.levels.WARN)
  end
end

return M

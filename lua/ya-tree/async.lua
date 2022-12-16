----------------------------------------------------------------------------------------------------
-- Based on: https://github.com/lewis6991/async.nvim
----------------------------------------------------------------------------------------------------

--- Small async library for Neovim plugins

local M = {}

-- Coroutine.running() was changed between Lua 5.1 and 5.2:
-- - 5.1: Returns the running coroutine, or nil when called by the main thread.
-- - 5.2: Returns the running coroutine plus a boolean, true when the running
--   coroutine is the main one.
--
-- For LuaJIT, 5.2 behaviour is enabled with LUAJIT_ENABLE_LUA52COMPAT
--
-- We need to handle both.
local main_co_or_nil = coroutine.running()

---@param fn fun(...)
---@param callback? fun(...)
---@param ... any
local function execute(fn, callback, ...)
  local co = coroutine.create(fn)

  local function step(...)
    local ret = { coroutine.resume(co, ...) }
    local stat, nargs, protected, err_or_fn = unpack(ret)

    if not stat then
      error(string.format("The coroutine failed with this message: %s\n%s", err_or_fn, debug.traceback(co)))
    end

    if coroutine.status(co) == "dead" then
      if callback then
        callback(unpack(ret, 4))
      end
      return
    end

    assert(type(err_or_fn) == "function", "type error :: expected function")

    local args = { select(5, unpack(ret)) }

    if protected then
      args[nargs] = function(...)
        step(true, ...)
      end
      local ok, err = pcall(err_or_fn, unpack(args, 1, nargs))
      if not ok then
        step(false, err)
      end
    else
      args[nargs] = step
      err_or_fn(unpack(args, 1, nargs))
    end
  end

  step(...)
end

--- Use this to create a function which executes in an async context but
--- called from a non-async context. Inherently this cannot return anything
--- since it is non-blocking
---@param fn function
---@param argc integer The number of arguments of func. Defaults to 0
function M.sync(fn, argc)
  argc = argc or 0
  return function(...)
    if coroutine.running() ~= main_co_or_nil then
      return fn(...)
    end
    local callback = select(argc + 1, ...)
    execute(fn, callback, unpack({ ... }, 1, argc))
  end
end

--- Create a function which executes in an async context but
--- called from a non-async context.
---@param fn function
function M.void(fn)
  return function(...)
    if coroutine.running() ~= main_co_or_nil then
      return fn(...)
    end
    execute(fn, nil, ...)
  end
end

--- Creates an async function with a callback style function.
---@param fn function A callback style function to be converted. The last argument must be the callback.
---@param argc integer The number of arguments of func. Must be included.
---@param protected boolean call the function in protected mode (like pcall)
---@return fun(...) Returns an async function
function M.wrap(fn, argc, protected)
  assert(argc, "argc must not be nil")
  return function(...)
    if coroutine.running() == main_co_or_nil then
      return fn(...)
    end
    return coroutine.yield(argc, protected, fn, ...)
  end
end

--- Run a collection of async functions (`thunks`) concurrently and return when
--- all have finished.
---@param n integer Max number of thunks to run concurrently
---@param interrupt_check function Function to abort thunks between calls
---@param thunks function[]
function M.join(n, interrupt_check, thunks)
  local function run(finish)
    if #thunks == 0 then
      return finish()
    end

    local remaining = { select(n + 1, unpack(thunks)) }
    local to_go = #thunks

    local ret = {}

    local function cb(...)
      ret[#ret + 1] = { ... }
      to_go = to_go - 1
      if to_go == 0 then
        finish(ret)
      elseif not interrupt_check or not interrupt_check() then
        if #remaining > 0 then
          local next_task = table.remove(remaining)
          next_task(cb)
        end
      end
    end

    for i = 1, math.min(n, #thunks) do
      thunks[i](cb)
    end
  end

  return coroutine.yield(1, false, run)
end

--- Partially applying arguments to an async function
---@param fn function
---@param ... any arguments to apply to `fn`
---@return fun(...)
function M.curry(fn, ...)
  local args = { ... }
  local nargs = select("#", ...)
  return function(...)
    local other = { ... }
    for i = 1, select("#", ...) do
      args[nargs + i] = other[i]
    end
    fn(unpack(args))
  end
end

--- An async function that when called will yield to the Neovim scheduler to be
--- able to call the API.
---@type fun()
M.scheduler = M.wrap(vim.schedule, 1, false)

--- Schedules `fn` to run on vim loop in an async context.
---@param fn async fun()
function M.defer(fn)
  vim.schedule(function ()
    M.void(fn)()
  end)
end

return M

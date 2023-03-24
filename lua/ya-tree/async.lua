----------------------------------------------------------------------------------------------------
-- Based on: https://github.com/lewis6991/async.nvim
-- at commit: https://github.com/lewis6991/async.nvim/tree/bad4edbb2917324cd11662dc0209ce53f6c8bc23
----------------------------------------------------------------------------------------------------

--- Small async library for Neovim plugins

--- Store all the async threads in a weak table so we don't prevent them from being garbage collected
---@type table<thread, Yat.Async>
local HANDLES = setmetatable({}, { __mode = "k" })

local M = {}

-- Coroutine.running() was changed between Lua 5.1 and 5.2:
-- - 5.1: Returns the running coroutine, or nil when called by the main thread.
-- - 5.2: Returns the running coroutine plus a boolean, true when the running coroutine is the main one.
--
-- For LuaJIT, 5.2 behaviour is enabled with LUAJIT_ENABLE_LUA52COMPAT
--
-- We need to handle both.

---Returns whether the current execution context is async.
---
---@return boolean?
function M.running()
  local current = coroutine.running()
  if current and HANDLES[current] then
    return true
  end
end

---@param handle any
---@return boolean?
local function is_AsyncT(handle)
  if handle and type(handle) == "table" and vim.is_callable(handle.cancel) and vim.is_callable(handle.is_cancelled) then
    return true
  end
end

---@class Yat.Async
---@field package _current? Yat.Async
local AsyncT = {}

---@param co thread
---@return Yat.Async
function AsyncT.new(co)
  local handle = setmetatable({}, { __index = AsyncT })
  HANDLES[co] = handle
  return handle
end

-- Analogous to uv.close
---@param cb function
function AsyncT:cancel(cb)
  -- Cancel anything running on the event loop
  if self._current and not self._current:is_cancelled() then
    self._current:cancel(cb)
  end
end

-- Analogous to uv.is_closing
function AsyncT:is_cancelled()
  return self._current and self._current:is_cancelled()
end

---Run a function in an async context.
---@param fn fun(...) The function to run.
---@param callback? fun(...) Callback on completion.
---@param ... any Arguments for `fn`.
---@return Yat.Async
function M.run(fn, callback, ...)
  vim.validate({
    fn = { fn, "function" },
    callback = { callback, "function", true },
  })

  local co = coroutine.create(fn)
  local handle = AsyncT.new(co)

  local function step(...)
    local ret = { coroutine.resume(co, ...) }
    local ok = ret[1] ---@type boolean

    if not ok then
      local err = ret[2] ---@type string
      error(string.format("The coroutine failed with this message:\n%s\n%s", err, debug.traceback(co)))
    end

    if coroutine.status(co) == "dead" then
      if callback then
        callback(unpack(ret, 4, table.maxn(ret)))
      end
      return
    end

    -- coroutine.yield is called with (argc, pfunc, ...) as the arguments
    ---@type integer, any|fun(...):any
    local nargs, next_fn = ret[2], ret[3]
    local args = { select(4, unpack(ret)) }

    assert(type(next_fn) == "function", "type error :: expected function")

    args[nargs] = step

    local r = next_fn(unpack(args, 1, nargs))
    if is_AsyncT(r) then
      handle._current = r --[[@as Yat.Async]]
    end
  end

  step(...)
  return handle
end

---@param argc integer
---@param fn fun(...)
---@param ... any
---@return any ...
local function wait(argc, fn, ...)
  vim.validate({
    argc = { argc, "number" },
    fn = { fn, "function" },
  })

  -- Always run the wrapped functions in xpcall and re-raise the error in the
  -- coroutine. This makes pcall work as normal.
  local function pfunc(...)
    local args = { ... }
    local cb = args[argc]
    args[argc] = function(...)
      cb(true, ...)
    end
    xpcall(fn, function(err)
      cb(false, err, debug.traceback())
    end, unpack(args, 1, argc))
  end

  local ret = { coroutine.yield(argc, pfunc, ...) }

  local ok = ret[1]
  if not ok then
    local _, err, traceback = unpack(ret)
    error(string.format("Wrapped function failed: %s\n%s", err, traceback))
  end

  return unpack(ret, 2, table.maxn(ret))
end

---Wait on a callback style function
---
---@overload fun(fn: fun(...), ...):any
---@overload fun(argc: integer, fn: fun(...), ...):any
function M.wait(...)
  if type(select(1, ...)) == "number" then
    return wait(...)
  end

  -- Assume argc is equal to the number of passed arguments.
  return wait(select("#", ...) - 1, ...)
end

---Use this to create a function which executes in an async context but called from a non-async context.
---Inherently this cannot return anything since it is non-blocking.
---
---@param fn fun(...):any
---@param argc? number The number of arguments of func. Defaults to 0
---@param strict? boolean Error when called in non-async context
---@return fun(...):Yat.Async
function M.create(fn, argc, strict)
  vim.validate({
    fc = { fn, "function" },
    argc = { argc, "number", true },
  })

  argc = argc or 0
  return function(...)
    if M.running() then
      if strict then
        error("This function must run in a non-async context")
      end
      return fn(...)
    end
    local callback = select(argc + 1, ...)
    return M.run(fn, callback, unpack({ ... }, 1, argc))
  end
end

---Create a function which executes in an async context but called from a non-async context.
---
---@param fn fun(...):any
---@param strict? boolean Error when called in a non-async context.
---@return fun(...): Yat.Async
function M.void(fn, strict)
  vim.validate({ fn = { fn, "function" } })

  return function(...)
    if M.running() then
      if strict then
        error("This function must run in a non-async context")
      end
      return fn(...)
    end
    return M.run(fn, nil, ...)
  end
end

---Creates an async function with a callback style function.
---
---@param fn fun(...):any A callback style function to be converted. The last argument must be the callback.
---@param argc integer The number of arguments of func. Must be included.
---@param strict boolean Error when called in a non-async context.
---@return fun(...) fn Returns an async function.
function M.wrap(fn, argc, strict)
  vim.validate({ argc = { argc, "number" } })

  return function(...)
    if not M.running() then
      if strict then
        error("This function must run in an async context")
      end
      return fn(...)
    end
    return M.wait(argc, fn, ...)
  end
end

---Run a collection of async functions (`thunks`) concurrently and return when all have finished.
---
---@param thunks function[]
---@param n integer Max number of thunks to run concurrently.
---@param interrupt_check function Function to abort thunks between calls.
function M.join(thunks, n, interrupt_check)
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

  if not M.running() then
    return run
  end
  return M.wait(1, false, run)
end

---Partially applying arguments to an async function.
---
---@param fn fun(...)
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

---An async function that when called will yield to the Neovim scheduler to be able to call the API.
---@type fun()
M.scheduler = M.wrap(vim.schedule, 1, false)

---Schedules `fn` to run soon on the nvim loop, in an async context.
---
---@param fn async fun()
function M.defer(fn)
  vim.schedule(function()
    M.void(fn)()
  end)
end

return M

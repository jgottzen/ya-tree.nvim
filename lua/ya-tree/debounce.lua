local M = {}

---@class Luv.Timer
---@field start fun(self: Luv.Timer, timout: integer, repeat: integer, callback: fun(...: any)): 0|nil
---@field stop fun(self: Luv.Timer): 0|nil
---@field close fun(self: Luv.Timer)
---@field is_active fun(self: Luv.Timer): boolean?
---@field is_closing fun(self: Luv.Timer): boolean?

---@type Luv.Timer[]
local timers = {}

---@param fn fun(...)
---@param ms integer
---@return fun(...)
function M.debounce_trailing(fn, ms)
  local timer = vim.loop.new_timer() --[[@as Luv.Timer]]
  timers[#timers + 1] = timer
  return function(...)
    local args = { ... }
    timer:start(ms, 0, function()
      timer:stop()
      vim.schedule_wrap(fn)(unpack(args))
    end)
  end
end

---@param fn fun(...)
---@param accumulator fun(...): any
---@param ms integer
---@return fun(...)
function M.accumulate_trailing(fn, accumulator, ms)
  local timer = vim.loop.new_timer() --[[@as Luv.Timer]]
  timers[#timers + 1] = timer
  local args = {}
  return function(...)
    args[#args + 1] = accumulator(...)
    timer:start(ms, 0, function()
      timer:stop()
      local fn_args = args
      args = {}
      vim.schedule_wrap(fn)(fn_args)
    end)
  end
end

local function close_timers()
  for _, timer in ipairs(timers) do
    if not timer:is_closing() then
      timer:close()
    end
  end
end

function M.setup()
  local events = require("ya-tree.events")
  local event = require("ya-tree.events.event").autocmd
  events.on_autocmd_event(event.LEAVE_PRE, "YA_TREE_DEBOUNCE_CLEANUP", close_timers)
end

return M

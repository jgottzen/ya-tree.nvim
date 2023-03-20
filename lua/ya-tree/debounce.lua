local M = {}

---@type uv_timer_t[]
local timers = {}

---@param fn fun(...)
---@param ms integer
---@return fun(...)
function M.debounce_trailing(fn, ms)
  local timer = vim.loop.new_timer() --[[@as uv_timer_t]]
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
  local timer = vim.loop.new_timer() --[[@as uv_timer_t]]
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

local events = require("ya-tree.events")
local event = require("ya-tree.events.event").autocmd
events.on_autocmd_event(event.LEAVE_PRE, "YA_TREE_DEBOUNCE_CLEANUP", function()
  for _, timer in ipairs(timers) do
    if not timer:is_closing() then
      timer:close()
    end
  end
end)

return M

local M = {}

---@class uv_timer_t
---@field start fun(self: uv_timer_t, timout: number, repeat: number, callback: fun(...: any)): 0|nil
---@field stop fun(self: uv_timer_t): 0|nil
---@field close fun(self: uv_timer_t)
---@field is_active fun(self: uv_timer_t): boolean?
---@field is_closing fun(self: uv_timer_t): boolean?

---@type uv_timer_t[]
local timers = {}

---@param fn fun(...)
---@param ms number
---@return fun(...)
function M.debounce_trailing(fn, ms)
  ---@type uv_timer_t
  local timer = vim.loop.new_timer()
  timers[#timers + 1] = timer
  return function(...)
    local args = { ... }
    timer:start(ms, 0, function()
      timer:stop()
      vim.schedule_wrap(fn)(unpack(args))
    end)
  end
end

do
  local events = require("ya-tree.events")
  local event = require("ya-tree.events.event").autocmd
  events.on_autocmd_event(event.LEAVE_PRE, "YA_TREE_DEBOUNCE_CLEANUP", function()
    for _, timer in ipairs(timers) do
      if not timer:is_closing() then
        timer:close()
      end
    end
  end)
end

return M

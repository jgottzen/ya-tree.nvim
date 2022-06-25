local M = {}

---@class uv_timer_t
---@field start fun(self: uv_timer_t, timout: integer, repeat: integer, callback: fun(...: any)): 0|nil
---@field stop fun(self: uv_timer_t): 0|nil
---@field close fun(self: uv_timer_t)
---@field is_active fun(self: uv_timer_t): boolean?
---@field is_closing fun(self: uv_timer_t): boolean?

---@param fn fun(...)
---@param ms number
---@return fun(...)
function M.debounce_trailing(fn, ms)
  ---@type uv_timer_t
  local timer = vim.loop.new_timer()
  return function(...)
    local args = { ... }
    timer:start(ms, 0, function()
      timer:stop()
      vim.schedule_wrap(fn)(unpack(args))
    end)
  end
end

return M

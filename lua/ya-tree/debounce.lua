local M = {}

---@param fn fun(...)
---@param ms number
---@return fun(...)
function M.debounce_trailing(fn, ms)
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

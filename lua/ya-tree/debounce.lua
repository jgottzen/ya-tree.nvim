local M = {}

local unpack = unpack or table.unpack

function M.debounce_trailing(fun, ms)
  local timer = vim.loop.new_timer()
  return function(...)
    local args = { ... }
    timer:start(ms, 0, function()
      timer:stop()
      vim.schedule_wrap(fun)(unpack(args))
    end)
  end
end

return M

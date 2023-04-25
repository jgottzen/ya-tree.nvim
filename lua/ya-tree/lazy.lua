local M = {}

---Will require the module on first index of it. The module must export a table.
---
---Does NOT support comparing the returned value, i.e `lazy.require("a.b") ~= lazy.require("a.b")`.
---Support callable modules.
---@param module string
---@return unknown
function M.require(module)
  return setmetatable({}, {
    __index = function(_, key)
      return require(module)[key]
    end,
    __newindex = function(_, key, value)
      require(module)[key] = value
    end,
    __call = function(_, ...)
      return require(module)(...)
    end,
  })
end

return M

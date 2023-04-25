local M = {}

---Will require the module on first index of it.
---Does NOT support comparing the returned value, i.e `lazy.require("a.b") ~= lazy.require("a.b")`
---@param module string
---@return unknown
function M.require(module)
  return setmetatable({}, {
    __index = function(_, key)
      return require(module)[key]
    end,
  })
end

return M

----------------------------------------------------------------------------------------------------
-- Based on: https://github.com/jpatte/yaci.lua
--
-- With improvements from https://github.com/sindrets/diffview.nvim/blob/main/lua/diffview/oop.lua
----------------------------------------------------------------------------------------------------

local M = {}

---Associations between an object an its virtuals.
---@type table<Yat.Class, { virtuals: table<string, function> }>
local CLASSES = setmetatable({}, { __mode = "k" })

---Return a shallow copy of table t
local function duplicate(t)
  local t2 = {}
  for k, v in pairs(t) do
    t2[k] = v
  end
  return t2
end

---@param class Yat.Class
---@return Yat.Object?
local function new_instance(class, ...)
  -- selene: allow(shadowing)

  ---@param class Yat.Class
  ---@param virtuals? string[]
  ---@return Yat.Object
  ---@diagnostic disable-next-line:redefined-local
  local function make_instance(class, virtuals)
    ---@type Yat.Object
    local instance = duplicate(virtuals)
    instance.__class = class

    if class:super() ~= nil then
      instance.super = make_instance(class:super(), virtuals)
      rawset(instance.super, "__lower", instance)
    else
      instance.super = {}
    end

    setmetatable(instance, class.static)

    return instance
  end

  local instance = make_instance(class, CLASSES[class].virtuals)
  ---@diagnostic disable-next-line:invisible
  instance:init(...)
  return instance
end

---@param class Yat.Class
---@param function_name string
local function make_virtual(class, function_name)
  local fn = class.static[function_name]
  if fn == nil then
    fn = function()
      error("Attempt to call an undefined abstract method '" .. function_name .. "'")
    end
  end
  CLASSES[class].virtuals[function_name] = fn
end

---Try to cast an instance into an instance of one of its super- or subclasses
---@param class Yat.Class
---@param instance Yat.Object
local function try_cast(class, instance)
  -- is it already the right class?
  if instance.class == class then
    return instance
  end

  local current = instance.__lower
  -- search lower in the hierarchy
  while current ~= nil do
    if current.__class == class then
      return current
    end
    current = current.__lower
  end

  -- instance is not a sub- or super-type of class
  return nil
end

---Same as try_cast but raise an error in case of failure
---@param class Yat.Class
---@param instance Yat.Object
local function secure_cast(class, instance)
  local cast = try_cast(class, instance)
  if cast == nil then
    error("Failed to cast " .. tostring(instance) .. " to a " .. class:name())
  end
  return cast
end

---@param instance Yat.Object
local function instsance_init_definition(instance)
  ---@diagnostic disable-next-line:invisible
  instance.super:init()
end

---@param instance Yat.Object
---@param key string
---@param value any
local function instance_newindex(instance, key, value)
  -- first check if this field isn't already defined higher in the hierarchy
  if instance.super[key] ~= nil then
    -- update the old value
    instance.super[key] = value
  else
    -- create the field
    rawset(instance, key, value)
  end
end

---@generic T
---@param base Yat.Class
---@param name `T`
---@return T
local function subclass(base, name)
  if type(name) ~= "string" then
    name = "Unnamed"
  end

  ---@type Yat.Object
  local class = {}

  -- need to copy everything here because events can't be found through metatables
  local static = base.static
  local instance_internals = {
    __tostring = static.__tostring,
    __eq = static.__eq,
    __add = static.__add,
    __sub = static.__sub,
    __mul = static.__mul,
    __div = static.__div,
    __mod = static.__mod,
    __pow = static.__pow,
    __unm = static.__unm,
    __len = static.__len,
    __lt = static.__lt,
    __le = static.__le,
    __concat = static.__concat,
    __call = static.__call,
    __newindex = instance_newindex,
    init = instsance_init_definition,
    class = function()
      return class
    end,
    instance_of = function(_, other)
      return class == other or base:isa(other)
    end,
  }

  -- Look for field 'key' in instance 'instance'
  ---@param self Yat.Object
  ---@param key string
  function instance_internals.__index(self, key)
    local res = instance_internals[key]
    if res ~= nil then
      return res
    end

    return self.super[key] -- Is it somewhere higher in the hierarchy?
  end

  ---@class Yat.Class
  ---@field static { [string]: function }
  ---@field new fun(class: Yat.Class, ...): Yat.Object
  ---@field subclass fun(self: Yat.Class, name: string): Yat.Class
  ---@field virtual fun(self: Yat.Class, method: string)
  ---@field cast fun(self: Yat.Class, other: Yat.Object): Yat.Class
  ---@field try_cast fun(self: Yat.Class, other: Yat.Object): Yat.Class?
  ---@field name fun(self: Yat.Class): string
  ---@field super fun(self: Yat.Class): Yat.Class
  ---@field isa fun(self: Yat.Class, other: Yat.Object): boolean
  local class_internals = {
    static = instance_internals,
    new = new_instance,
    subclass = subclass,
    virtual = make_virtual,
    cast = secure_cast,
    trycast = try_cast,
    name = function(_)
      return name --[[@as string]]
    end,
    super = function(_)
      return base
    end,
    isa = function(_, other)
      return class == other or base:isa(other)
    end,
  }
  CLASSES[class] = { virtuals = duplicate(CLASSES[base].virtuals) }

  -- selene: allow(shadowing)

  ---@param class Yat.Class
  ---@param name string
  ---@param method fun(...): any
  ---@diagnostic disable-next-line:redefined-local
  local function new_method(class, name, method)
    instance_internals[name] = method
    if CLASSES[class].virtuals[name] ~= nil then
      CLASSES[class].virtuals[name] = method
    end
  end

  setmetatable(class, {
    __newindex = new_method,
    __index = function(_, key)
      return class_internals[key] or class_internals.static[key] or base[key]
    end,
    __tostring = function()
      return "<class " .. name .. ">"
    end,
    __call = new_instance,
  })

  return class
end

---@class Yat.Object
---@field package __class Yat.Class
---@field package __lower Yat.Object
---@field protected init fun(self: Yat.Object, ...)
---@field class fun(self: Yat.Object): Yat.Class
---@field super Yat.Object
---@field subclass fun(self: Yat.Class, name: string): Yat.Object
---@field static Yat.Object
---@field virtual fun(self: Yat.Object, method: string)
---@field instance_of fun(self: Yat.Object, class: Yat.Object): boolean
local Object = {}

local function object_new_item()
  error("Do not modify the 'Yat.Object' class, subclass it instead.")
end

local object_instance = {
  __newindex = object_new_item,
  ---@param self Yat.Object
  __tostring = function(self)
    return "<class " .. self:class():name() .. ">"
  end,
  init = function() end,
  class = function()
    return Object
  end,
  instance_of = function(_, other)
    return other == Object
  end,
}
object_instance.__index = object_instance

local object_class = {
  static = object_instance,
  new = new_instance,
  subclass = subclass,
  cast = secure_cast,
  trycast = try_cast,
  name = function()
    return "Object"
  end,
  super = function()
    return nil
  end,
  isa = function(_, other)
    return other == Object
  end,
}
CLASSES[Object] = { virtuals = {} }

setmetatable(Object, {
  __newindex = object_new_item,
  __index = object_class,
  __tostring = function()
    return "<class Object>"
  end,
  __call = new_instance,
})

---@generic T : Yat.Object
---@param name `T`
---@param super? Yat.Object
---@return T
function M.create_class(name, super)
  super = super or Object
  return super:subclass(name)
end

return M

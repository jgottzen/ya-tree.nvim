-- modified version of middleclass

local meta = {
  _VERSION = "middleclass v4.1.1",
  _DESCRIPTION = "Object Orientation for Lua",
  _URL = "https://github.com/kikito/middleclass",
  _LICENSE = [[
    MIT LICENSE
    Copyright (c) 2011 Enrique García Cota
    Permission is hereby granted, free of charge, to any person obtaining a
    copy of this software and associated documentation files (the
    "Software"), to deal in the Software without restriction, including
    without limitation the rights to use, copy, modify, merge, publish,
    distribute, sublicense, and/or sell copies of the Software, and to
    permit persons to whom the Software is furnished to do so, subject to
    the following conditions:
    The above copyright notice and this permission notice shall be included
    in all copies or substantial portions of the Software.
    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
    OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
    MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
    IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
    CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
    TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
    SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
  ]],
}

---@alias Yat.Object.Method fun(self: Yat.Object, ...):any
---@alias Yat.Class.Method fun(self: Yat.Class, ...):any

---@param class Yat.Class
---@param f? table<string, Yat.Object.Method>|Yat.Object.Method
---@return Yat.Object.Method
local function create_index_wrapper(class, f)
  if f == nil then
    ---@diagnostic disable-next-line:return-type-mismatch
    return class.__instance_dict
  elseif type(f) == "function" then
    ---@param self Yat.Object
    ---@param name string
    return function(self, name)
      local value = class.__instance_dict[name]

      if value ~= nil then
        return value
      else
        return f(self, name)
      end
    end
  else -- if  type(f) == "table" then
    ---@param _ Yat.Object
    ---@param name string
    return function(_, name)
      local value = class.__instance_dict[name]

      if value ~= nil then
        return value
      else
        return f[name]
      end
    end
  end
end

---@param class Yat.Class
---@param name string
---@param f Yat.Object.Method
local function propagate_instance_method(class, name, f)
  f = name == "__index" and create_index_wrapper(class, f) or f
  class.__instance_dict[name] = f

  for subclass in pairs(class.subclasses) do
    if rawget(subclass.__declared_methods, name) == nil then
      propagate_instance_method(subclass, name, f)
    end
  end
end

---@param class Yat.Class
---@param name string
---@param f Yat.Object.Method
local function declare_instance_method(class, name, f)
  class.__declared_methods[name] = f

  if f == nil and class.super then
    f = class.super.__instance_dict[name]
  end

  propagate_instance_method(class, name, f)
end

---@generic T : Yat.Object
---@param name `T`
---@param super? Yat.Class
---@return T
local function create_class(name, super)
  local dict = {}
  dict.__index = dict

  ---@class Yat.Class
  ---@field protected allocate fun(class: Yat.Class): Yat.Object
  ---@field new fun(class: Yat.Class, ...): Yat.Object
  ---@field name string
  ---@field subclass fun(self: Yat.Class, name: string): Yat.Object
  ---@field protected subclassed fun(self: Yat.Class, other: Yat.Class)
  ---@field is_subclass_of fun(self: Yat.Class, other: Yat.Class): boolean
  local class = {
    name = name,
    super = super,
    ---@type table<string, Yat.Class.Method>
    static = {},
    ---@private
    ---@type table<string, Yat.Object.Method>
    __instance_dict = dict,
    ---@private
    ---@type table<string, Yat.Object.Method>
    __declared_methods = {},
    ---@private
    ---@type table<Yat.Class, boolean>
    subclasses = setmetatable({}, { __mode = "k" }),
  }

  if super then
    setmetatable(class.static, {
      __index = function(_, k)
        local result = rawget(dict, k)
        if result == nil then
          return super.static[k]
        end
        return result
      end,
    })
  else
    setmetatable(class.static, {
      __index = function(_, k)
        return rawget(dict, k)
      end,
    })
  end

  setmetatable(class, {
    __index = class.static,
    __tostring = function()
      return "<class " .. name .. ">"
    end,
    __newindex = declare_instance_method,
  })

  return class
end

---@param class Yat.Class
---@param mixin Yat.Mixin
---@return Yat.Object
local function include_mixin(class, mixin)
  assert(type(mixin) == "table", "mixin must be a table")

  for name, method in pairs(mixin) do
    if name ~= "included" and name ~= "static" then
      class[name] = method
    end
  end

  for name, method in pairs(mixin.static or {}) do
    class.static[name] = method
  end

  ---@diagnostic disable-next-line:invisible
  if type(mixin.included) == "function" then
    ---@diagnostic disable-next-line:invisible
    mixin:included(class)
  end

  return class --[[@as Yat.Object]]
end

---@class Yat.DefaultMixin : Yat.Mixin
local DefaultMixin = {
  __tostring = function(self)
    return tostring(self.class)
  end,

  -- selene: allow(unused_variable)

  ---@protected
  ---@param self Yat.Object
  ---@param ... any
  ---@diagnostic disable-next-line:unused-local
  init = function(self, ...) end,

  ---@param self Yat.Object
  ---@param class Yat.Class
  ---@return boolean
  instance_of = function(self, class)
    return type(class) == "table"
      and type(self) == "table"
      and (
        self.class == class
        or type(self.class) == "table" and type(self.class.is_subclass_of) == "function" and self.class:is_subclass_of(class)
      )
  end,

  static = {
    ---@protected
    ---@param self Yat.Class
    ---@return Yat.Object
    allocate = function(self)
      assert(type(self) == "table", "Make sure that you are using 'Class:allocate' instead of 'Class.allocate'")
      return setmetatable({ class = self }, self.__instance_dict)
    end,

    ---@param self Yat.Class
    ---@param ... any
    ---@return Yat.Object
    new = function(self, ...)
      assert(type(self) == "table", "Make sure that you are using 'Class:new' instead of 'Class.new'")
      ---@diagnostic disable-next-line:invisible
      local instance = self:allocate()
      ---@diagnostic disable-next-line:invisible
      instance:init(...)
      return instance
    end,

    ---@generic T : Yat.Object
    ---@param self Yat.Class
    ---@param name `T`
    ---@return T class
    subclass = function(self, name)
      assert(type(self) == "table", "Make sure that you are using 'Class:subclass' instead of 'Class.subclass'")
      assert(type(name) == "string", "You must provide a name(string) for your class")

      local subclass = create_class(name, self)

      for methodName, f in pairs(self.__instance_dict) do
        if not (methodName == "__index" and type(f) == "table") then
          propagate_instance_method(subclass, methodName, f)
        end
      end
      subclass.init = function(instance, ...)
        ---@diagnostic disable-next-line:undefined-field
        return self.init(instance, ...)
      end

      self.subclasses[subclass] = true
      ---@diagnostic disable-next-line:invisible
      self:subclassed(subclass)

      return subclass
    end,

    -- selene: allow(unused_variable)

    ---@protected
    ---@param self Yat.Class
    ---@param other Yat.Class
    ---@diagnostic disable-next-line:unused-local
    subclassed = function(self, other) end,

    ---@param self Yat.Class
    ---@param other Yat.Class
    ---@return boolean
    is_subclass_of = function(self, other)
      return type(other) == "table" and type(self.super) == "table" and (self.super == other or self.super:is_subclass_of(other))
    end,

    ---@param self Yat.Class
    ---@param mixin Yat.Mixin
    ---@return Yat.Class
    include = function(self, mixin)
      assert(type(self) == "table", "Make sure you that you are using 'Class:include' instead of 'Class.include'")
      include_mixin(self, mixin)
      return self
    end,
  },
}

---@generic T : Yat.Object
---@param name `T`
---@param super? Yat.Object
---@return T
function meta.create_class(name, super)
  assert(type(name) == "string", "A name (string) is needed for the new class")
  return super and super:subclass(name) or include_mixin(create_class(name), DefaultMixin)
end

---@class Yat.Object
---@field class Yat.Class
---@field static table<string, function>
local Object = {}

---The constructor must be defined on subclasses.
---@private
---@param ... any constructor paramaters
---@return Yat.Object
---@diagnostic disable-next-line:missing-return
function Object:new(...) end

---@protected
---@param ... any constructor paramaters
function Object:init(...) end

-- selene: allow(unused_variable)

---@param class Yat.Object
---@return boolean
---@diagnostic disable-next-line:unused-local,missing-return
function Object:instance_of(class) end

-- selene: allow(unused_variable)

---@generic T : Yat.Object
---@param name `T`
---@return T
---@diagnostic disable-next-line:unused-local,missing-return
function Object:subclass(name) end

-- selene: allow(unused_variable)

---@generic T : Yat.Object
---@param mixin Yat.Mixin
---@return T
---@diagnostic disable-next-line:unused-local,missing-return
function Object:include(mixin) end

-- selene: allow(unused_variable)

---@class Yat.Mixin
---@field protected included? fun(self: Yat.Mixin, class: Yat.Class)
---@field static? table<string, fun(self: Yat.Object, ...: any)>
---@diagnostic disable-next-line:unused-local
local Mixin = {}

return meta

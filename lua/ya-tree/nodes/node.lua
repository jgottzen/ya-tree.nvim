local lazy = require("ya-tree.lazy")

local diagnostics = lazy.require("ya-tree.diagnostics") ---@module "ya-tree.diagnostics"
local Logger = lazy.require("ya-tree.log") ---@module "ya-tree.log"
local meta = require("ya-tree.meta")
local Path = lazy.require("ya-tree.path") ---@module "ya-tree.path"

---@alias Yat.Node.Type "filesystem"|"search"|"buffer"|"git"|"text"|"symbol"|"call_hierarchy"|string

---@alias Yat.Node.Params { name: string, path: string, container: boolean, [string]?: any }

---@abstract
---@class Yat.Node : Yat.Object
---
---@field public TYPE Yat.Node.Type
---@field public name string
---@field public path string
---@field protected container boolean
---@field public parent? Yat.Node
---@field protected _children? Yat.Node[]
---@field public modified boolean
---@field protected _clipboard_status? Yat.Actions.Clipboard.Action
---@field public expanded? boolean
---@field public node_comparator? fun(a: Yat.Node, b: Yat.Node):boolean
---@field public git_status? fun(self: Yat.Node):string|nil
local Node = meta.create_class("Yat.Node")

function Node.__tostring(self)
  return string.format("(%s, %s)", self.TYPE, self.path)
end

---@param other Yat.Node
function Node.__eq(self, other)
  return self.TYPE == other.TYPE and self.path == other.path
end

---@protected
---@param params Yat.Node.Params node parameters.
---@param parent? Yat.Node the parent node.
function Node:init(params, parent)
  for k, v in pairs(params) do
    if type(v) ~= "function" then
      self[k] = v
    end
  end
  self.parent = parent
  self.modified = false
  if self:is_container() then
    self._children = {}
  end

  Logger.get("nodes").trace("created node %s", self)
end

---Recursively calls `visitor` for this node and each child node, if the function returns `true` the `walk` doens't recurse into
---any children of that node, but continues with the next child, if any.
---@generic T : Yat.Node
---@param self T
---@param visitor fun(node: T):boolean?
function Node:walk(visitor)
  ---@cast self Yat.Node
  if visitor(self) then
    return
  end

  if self._children then
    for _, child in ipairs(self._children) do
      child:walk(visitor)
    end
  end
end

---@param output_to_log? boolean
---@return table<string, any>
function Node:get_debug_info(output_to_log)
  ---@type table<string, any>
  local t = { __class = self.class.name }
  for k, v in pairs(self) do
    if type(v) == "table" then
      if v.class then
        t[k] = tostring(v)
      elseif k == "_children" then
        t[k] = vim.tbl_map(tostring, v)
      elseif k ~= "class" then
        t[k] = v
      end
    elseif type(v) ~= "function" then
      t[k] = v
    end
  end
  if output_to_log then
    Logger.get("nodes").info(t)
  end
  return t
end

---@protected
---@param params Yat.Node.Params node parameters.
function Node:merge_new_data(params)
  for k, v in pairs(params) do
    if type(self[k]) ~= "function" then
      self[k] = v
    else
      Logger.get("nodes").error("self.%s is a function, this is not allowed!", k)
    end
  end
end

---@return boolean container
function Node:is_container()
  return self.container
end

---@abstract
---@return boolean editable
function Node:is_editable()
  error("is_editable must be implemented by subclasses")
end

---@param node Yat.Node
---@return string
function Node:relative_path_to(node)
  local sep = Path.path.sep
  local path, to = self.path:gsub(sep .. sep, sep), node.path:gsub(sep .. sep, sep)
  if path == to then
    return "."
  else
    if to:sub(#to, #to) ~= sep then
      to = to .. sep
    end

    if path:sub(1, #to) == to then
      path = path:sub(#to + 1, -1)
    end
  end
  return path
end

---@param path string
---@return boolean
function Node:is_ancestor_of(path)
  return self:has_children() and vim.startswith(path, self.path .. Path.path.sep)
end

---@return boolean
function Node:has_children()
  return self._children ~= nil
end

---@return boolean hidden
function Node:is_hidden()
  return false
end

---@param status Yat.Actions.Clipboard.Action|nil
function Node:set_clipboard_status(status)
  self._clipboard_status = status
  if self:is_container() then
    for _, child in ipairs(self._children) do
      child:set_clipboard_status(status)
    end
  end
end

---@return Yat.Actions.Clipboard.Action|nil status
function Node:clipboard_status()
  return self._clipboard_status
end

---@return DiagnosticSeverity|nil
function Node:diagnostic_severity()
  return diagnostics.severity_of(self.path)
end

---@generic T : Yat.Node
---@param self T
---@return T[] children
function Node:children()
  ---@cast self Yat.Node
  return self._children
end

-- selene: allow(unused_variable)

---@abstract
---@param cmd string
---@diagnostic disable-next-line:unused-local
function Node:edit(cmd) end

---@async
---@abstract
---@generic T : Yat.Node
---@param self T
---@param ... any
---@return T|nil node
function Node:add_node(...) end

---@protected
function Node:on_node_removed() end

---@param path string
---@param remove_empty_parents? boolean
---@return boolean updated
function Node:remove_node(path, remove_empty_parents)
  local log = Logger.get("nodes")
  local updated = false
  local node = self:get_node(path)
  while node and node.parent and node ~= self do
    if node.parent and node.parent._children then
      for i = #node.parent._children, 1, -1 do
        local child = node.parent._children[i]
        if child == node then
          log.debug("removing child %q from parent %q", child.path, node.parent.path)
          table.remove(node.parent._children, i)
          child:on_node_removed()
          updated = true
          break
        end
      end
      if #node.parent._children == 0 then
        node = node.parent
        if not remove_empty_parents then
          return updated
        end
      else
        break
      end
    end
  end
  return updated
end

---Returns an iterator function for this `node`'s children.
---@generic T : Yat.Node
---@param self T
---@param opts? {reverse?: boolean, from?: T}
---  - {opts.reverse?} `boolean`
---  - {opts.from?} T
---@return fun(): integer, T iterator
function Node:iterate_children(opts)
  local children = self._children --[=[@as Yat.Node[]]=]
  if not children or #children == 0 then
    return function() end
  end

  opts = opts or {}
  local start = 0
  if opts.reverse then
    start = #children + 1
  end
  if opts.from then
    for i, child in ipairs(children) do
      if child == opts.from then
        start = i
        break
      end
    end
  end

  local pos = start
  if opts.reverse then
    return function()
      pos = pos - 1
      if pos >= 1 then
        return pos, children[pos]
      end
    end
  else
    return function()
      pos = pos + 1
      if pos <= #children then
        return pos, children[pos]
      end
    end
  end
end

---Collapses the node, if it is a directory.
---@param opts? {children_only?: boolean, recursive?: boolean}
---  - {opts.children_only?} `boolean`
---  - {opts.recursive?} `boolean`
function Node:collapse(opts)
  opts = opts or {}
  if self._children then
    if not opts.children_only then
      self.expanded = false
    end

    if opts.recursive then
      for _, child in ipairs(self._children) do
        child:collapse({ recursive = opts.recursive })
      end
    end
  end
end

---Expands the node, if it has children.
---@async
---@generic T : Yat.Node
---@param self T
---@param opts? {to?: string}
---  - {opts.to?} `string` recursively expand to the specified path and return that `Node`, if found.
---@return T|nil node if {opts.to} is specified, and found.
function Node:expand(opts)
  local log = Logger.get("nodes")
  ---@cast self Yat.Node
  log.debug("expanding %q", self.path)
  opts = opts or {}
  if self._children then
    self.expanded = true
  end

  if opts.to then
    if self.path == opts.to then
      log.debug("self %q is equal to path %q", self.path, opts.to)
      return self
    elseif self:is_ancestor_of(opts.to) then
      for _, child in ipairs(self._children) do
        if child:is_ancestor_of(opts.to) then
          log.debug("child node %q is parent of %q", child.path, opts.to)
          return child:expand(opts)
        elseif child.path == opts.to then
          if child._children then
            child:expand(opts)
          end
          return child
        end
      end
    else
      log.debug("node %q is not a parent of path %q", self.path, opts.to)
    end
  end
end

---Returns the child node specified by `path`, if it exists.
---@generic T : Yat.Node
---@param self T
---@param path string
---@return T|nil node
function Node:get_node(path)
  ---@cast self Yat.Node
  if self.path == path then
    return self
  end

  if self:is_ancestor_of(path) then
    for _, child in ipairs(self._children) do
      if child.path == path then
        return child
      elseif child:is_ancestor_of(path) then
        return child:get_node(path)
      end
    end
  end
end

-- selene: allow(unused_variable)

---@abstract
---@async
---@param opts? table<string, any>
---@diagnostic disable-next-line:unused-local
function Node:refresh(opts) end

return Node

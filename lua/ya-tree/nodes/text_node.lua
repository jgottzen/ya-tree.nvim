local Node = require("ya-tree.nodes.node")

---@class Yat.Node.Text : Yat.Node
---@field new fun(self: Yat.Node.Text, text: string, path: string, container?: boolean, parent?: Yat.Node.Text): Yat.Node.Text
---
---@field public TYPE "text"
---@field public parent? Yat.Node.Text
---@field private _children? Yat.Node.Text[]
local TextNode = Node:subclass("Yat.Node.Text")

---@protected
---@param text string
---@param path string
---@param container? boolean
---@param parent? Yat.Node.Text
function TextNode:init(text, path, container, parent)
  Node.init(self, {
    name = text,
    path = path,
    container = container or false,
  }, parent)
  self.TYPE = "text"
end

---@return boolean editable
function TextNode:is_editable()
  return false
end

---@param text string
---@param path string
---@param container? boolean
function TextNode:add_node(text, path, container)
  if not self.container then
    self.container = true
    self._children = {}
  end
  self._children[#self._children + 1] = TextNode:new(text, path, container, self)
end

return TextNode

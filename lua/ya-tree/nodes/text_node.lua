local meta = require("ya-tree.meta")
local Node = require("ya-tree.nodes.node")

---@class Yat.Node.Text : Yat.Node
---@field new fun(self: Yat.Node.Text, text: string, path: string, container: boolean, parent?: Yat.Node.Text): Yat.Node.Text
---@overload fun(text: string, path: string, container: boolean, parent?: Yat.Node.Text): Yat.Node.Text
---
---@field public TYPE "text"
---@field public parent? Yat.Node.Text
---@field private _children? Yat.Node.Text[]
local TextNode = meta.create_class("Yat.Node.Text", Node)

---@protected
---@param text string
---@param path string
---@param container boolean
---@param parent? Yat.Node.Text
function TextNode:init(text, path, container, parent)
  Node.init(self, {
    name = text,
    path = path,
    _type = container and "directory" or "file",
  }, parent)
  self.TYPE = "text"
end

---@return boolean
function TextNode:is_editable()
  return false
end

---@protected
function TextNode:_scandir() end

function TextNode:refresh(...) end

return TextNode

local meta = require("ya-tree.meta")
local Node = require("ya-tree.nodes.node")

---@class Yat.Node.Text : Yat.Node
---@field new fun(self: Yat.Node.Text, text: string, path: string, container: boolean, parent?: Yat.Node.Text): Yat.Node.Text
---@overload fun(text: string, path: string, container: boolean, parent?: Yat.Node.Text): Yat.Node.Text
---@field class fun(self: Yat.Node.Text): Yat.Node.Text
---@field super Yat.Node
---
---@field protected __node_type "text"
---@field public parent? Yat.Node.Text
---@field private _children? Yat.Node.Text[]
local TextNode = meta.create_class("Yat.Node.Text", Node)
TextNode.__node_type = "text"

---@protected
---@param text string
---@param path string
---@param container boolean
---@param parent? Yat.Node.Text
function TextNode:init(text, path, container, parent)
  self.super:init({
    name = text,
    path = path,
    _type = container and "directory" or "file",
  }, parent)
end

---@return false
function TextNode:is_editable()
  return false
end

---@protected
function TextNode:_scandir() end

function TextNode:refresh() end

return TextNode

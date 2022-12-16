local meta = require("ya-tree.meta")
local Node = require("ya-tree.nodes.node")

---@class Yat.Nodes.Text : Yat.Node
---@field new fun(self: Yat.Nodes.Text, text: string, path: string, container: boolean, parent?: Yat.Nodes.Text): Yat.Nodes.Text
---@overload fun(text: string, path: string, container: boolean, parent?: Yat.Nodes.Text): Yat.Nodes.Text
---@field class fun(self: Yat.Nodes.Text): Yat.Nodes.Text
---@field super Yat.Node
---
---@field add_node fun(self: Yat.Nodes.Text, path: string): Yat.Nodes.Text?
---@field protected __node_type "text"
---@field public parent? Yat.Nodes.Text
---@field private _children? Yat.Nodes.Text[]
local TextNode = meta.create_class("Yat.Nodes.Text", Node)
TextNode.__node_type = "text"

---@protected
---@param text string
---@param path string
---@param container boolean
---@param parent? Yat.Nodes.Text
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

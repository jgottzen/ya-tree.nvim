local Node = require("ya-tree.nodes.node")

---@class Yat.Nodes.Text : Yat.Node
---@field private __node_type "Text"
---@field public parent? Yat.Nodes.Text
---@field private _children? Yat.Nodes.Text[]
local TextNode = { __node_type = "Text" }
TextNode.__index = TextNode
TextNode.__eq = Node.__eq
TextNode.__tostring = Node.__tostring
setmetatable(TextNode, { __index = Node })

---@param text string
---@param path string
---@param container boolean
---@param parent? Yat.Nodes.Text
---@return Yat.Nodes.Text node
function TextNode:new(text, path, container, parent)
  local this = Node.new(self, {
    name = text,
    path = path,
    type = container and "directory" or "file",
  }, parent)
  return this
end

function TextNode:is_editable()
  return false
end

---@private
function TextNode:_scandir() end

function TextNode:refresh() end

return TextNode

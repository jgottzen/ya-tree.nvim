local hl = require("ya-tree.ui.highlights")

local M = {}

---@return string[] lines, highlight_group[][] highlights
function M.create_help()
  local mappings = require("ya-tree.actions").mappings

  ---@type string[]
  local lines
  ---@type highlight_group[][]
  local highlights
  ---@type ActionMapping[]
  ---@param mapping ActionMapping
  local insert = vim.tbl_filter(function(mapping)
    return mapping.mode == "n"
  end, mappings)
  ---@type ActionMapping[]
  ---@param mapping ActionMapping
  local visual = vim.tbl_filter(function(mapping)
    return mapping.mode == "v" or mapping.mode == "V"
  end, mappings)
  table.sort(insert, function(a, b)
    return a.name < b.name
  end)
  table.sort(visual, function(a, b)
    return a.name < b.name
  end)

  lines = { " HELP", "", " Normal Mode:" }
  highlights = { { { name = hl.ROOT_NAME, from = 0, to = -1 } }, {}, { { name = hl.ROOT_NAME, from = 0, to = -1 } } }

  for _, mapping in ipairs(insert) do
    for _, key in ipairs(mapping.keys) do
      lines[#lines + 1] = string.format("%7s : %s", key, mapping.name)
      local key_len = math.max(7, #key)
      highlights[#highlights + 1] = {
        {
          name = hl.GIT_DIRTY,
          from = 0,
          to = key_len,
        },
        {
          name = hl.SYMBOLIC_LINK,
          from = key_len + 3,
          to = -1,
        },
      }
    end
  end

  lines[#lines + 1] = ""
  highlights[#highlights + 1] = {}
  lines[#lines + 1] = " Visual Mode:"
  highlights[#highlights + 1] = { { name = hl.ROOT_NAME, from = 0, to = -1 } }

  for _, mapping in ipairs(visual) do
    for _, key in ipairs(mapping.keys) do
      lines[#lines + 1] = string.format("%7s : %s", key, mapping.name)
      local key_len = math.max(7, #key)
      highlights[#highlights + 1] = {
        {
          name = hl.GIT_DIRTY,
          from = 0,
          to = key_len,
        },
        {
          name = hl.SYMBOLIC_LINK,
          from = key_len + 3,
          to = -1,
        },
      }
    end
  end

  return lines, highlights
end

return M

---@enum YaTreeEvent
local event = {
  TAB_NEW = 1,
  TAB_ENTERED = 2,
  TAB_CLOSED = 3,

  BUFFER_NEW = 101,
  BUFFER_ENTERED = 102,
  BUFFER_HIDDEN = 103,
  BUFFER_DISPLAYED = 104,
  BUFFER_DELETED = 105,
  BUFFER_MODIFIED = 106,
  BUFFER_SAVED = 107,

  WINDOW_LEAVE = 201,
  WINDOW_CLOSED = 202,

  CWD_CHANGED = 301,

  DIAGNOSTICS_CHANGED = 401,

  COLORSCHEME = 501,

  LEAVE_PRE = 601,

  GIT = 1001,
}
vim.tbl_add_reverse_lookup(event)

return event

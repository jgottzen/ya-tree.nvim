local M = {
  ---@enum YaTreeEvents.AutocmdEvent
  autocmd = {
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

    CWD_CHANGED = 303,

    DIAGNOSTICS_CHANGED = 401,

    COLORSCHEME = 501,

    LEAVE_PRE = 601,
  },

  ---@enum YaTreeEvents.GitEvent
  git = {
    DOT_GIT_DIR_CHANGED = 10001, -- fun(repo: GitRepo, fs_changes: boolean)
  },

  ---@enum YaTreeEvents.YaTreeEvent
  ya_tree = {
    YA_TREE_WINDOW_OPENED = 20001, -- fun({ winid: integer })
    YA_TREE_WINDOW_CLOSED = 20002, -- fun({ winid: integer })
  },
}

return M

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
}

return M

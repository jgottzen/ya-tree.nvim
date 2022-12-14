local M = {
  ---@enum Yat.Events.AutocmdEvent
  autocmd = {
    BUFFER_NEW = 101,
    BUFFER_HIDDEN = 102,
    BUFFER_DISPLAYED = 103,
    BUFFER_DELETED = 104,
    BUFFER_MODIFIED = 105,
    BUFFER_SAVED = 106,

    COLORSCHEME = 201,

    LEAVE_PRE = 301,
  },

  ---@enum Yat.Events.GitEvent
  git = {
    DOT_GIT_DIR_CHANGED = 10001, -- async fun(repo: GitRepo, fs_changes: boolean)
  },

  ---@enum Yat.Events.YaTreeEvent
  ya_tree = {
    YA_TREE_WINDOW_OPENED = 20001, -- fun({ winid: integer })
    YA_TREE_WINDOW_CLOSED = 20002, -- fun({ winid: integer })

    DIAGNOSTICS_CHANGED = 20101, -- fun(severity_changed: boolean)

    FS_CHANGED = 20201, -- fun(dir: string, filenames: string[])

    REQUEST_SIDEBAR_REPAINT = 20301, -- fun(tabpage: integer)
  },
}

return M

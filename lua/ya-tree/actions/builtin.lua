---@alias Yat.Actions.Name
---| "close_sidebar"
---| "system_open"
---| "open_help"
---| "show_node_info"
---| "close_panel"
---| "open_symbols_panel",
---| "open_git_status_panel"
---| "open_buffers_panel"
---| "open"
---| "vsplit"
---| "split"
---| "tabnew"
---| "preview"
---| "preview_and_focus"
---| "copy_name_to_clipboard"
---| "copy_root_relative_path_to_clipboard"
---| "copy_absolute_path_to_clipboard"
---| "close_node"
---| "close_all_nodes"
---| "close_all_child_nodes"
---| "expand_all_nodes"
---| "expand_all_child_nodes"
---| "refresh_panel"
---| "focus_parent"
---| "focus_prev_sibling"
---| "focus_next_sibling"
---| "focus_first_sibling"
---| "focus_last_sibling"
---
---| "add"
---| "rename"
---| "delete"
---| "trash"
---| "copy_node"
---| "cut_node"
---| "paste_nodes"
---| "clear_clipboard"
---| "cd_to"
---| "cd_up"
---| "toggle_filter"
---
---| "search_for_node_in_panel"
---| "search_interactively"
---| "search_once"
---| "close_search"
---
---| "goto_node_in_files_panel"
---
---| "toggle_ignored"
---| "check_node_for_git"
---| "focus_prev_git_item"
---| "focus_next_git_item"
---| "git_stage"
---| "git_unstage"
---| "git_revert"
---
---| "focus_prev_diagnostic_item"
---| "focus_next_diagnostic_item"

local M = {
  general = {
    close_sidebar = "close_sidebar",
    system_open = "system_open",
    open_help = "open_help",
    show_node_info = "show_node_info",
    close_panel = "close_panel",

    open_symbols_panel = "open_symbols_panel",
    open_git_status_panel = "open_git_status_panel",
    open_buffers_panel = "open_buffers_panel",

    open = "open",
    vsplit = "vsplit",
    split = "split",
    tabnew = "tabnew",
    preview = "preview",
    preview_and_focus = "preview_and_focus",

    copy_name_to_clipboard = "copy_name_to_clipboard",
    copy_root_relative_path_to_clipboard = "copy_root_relative_path_to_clipboard",
    copy_absolute_path_to_clipboard = "copy_absolute_path_to_clipboard",

    close_node = "close_node",
    close_all_nodes = "close_all_nodes",
    close_all_child_nodes = "close_all_child_nodes",
    expand_all_nodes = "expand_all_nodes",
    expand_all_child_nodes = "expand_all_child_nodes",

    refresh_panel = "refresh_panel",

    focus_parent = "focus_parent",
    focus_prev_sibling = "focus_prev_sibling",
    focus_next_sibling = "focus_next_sibling",
    focus_first_sibling = "focus_first_sibling",
    focus_last_sibling = "focus_last_sibling",
  },
  files = {
    add = "add",
    rename = "rename",
    delete = "delete",
    trash = "trash",

    copy_node = "copy_node",
    cut_node = "cut_node",
    paste_nodes = "paste_nodes",
    clear_clipboard = "clear_clipboard",

    cd_to = "cd_to",
    cd_up = "cd_up",

    toggle_filter = "toggle_filter",
  },
  search = {
    search_for_node_in_panel = "search_for_node_in_panel",
    search_interactively = "search_interactively",
    search_once = "search_once",
    close_search = "close_search",
  },
  panel_specific = {
    goto_node_in_files_panel = "goto_node_in_files_panel",
  },
  git = {
    toggle_ignored = "toggle_ignored",
    check_node_for_git = "check_node_for_git",
    focus_prev_git_item = "focus_prev_git_item",
    focus_next_git_item = "focus_next_git_item",
    git_stage = "git_stage",
    git_unstage = "git_unstage",
    git_revert = "git_revert",
  },
  diagnostics = {
    focus_prev_diagnostic_item = "focus_prev_diagnostic_item",
    focus_next_diagnostic_item = "focus_next_diagnostic_item",
  },
}

return M

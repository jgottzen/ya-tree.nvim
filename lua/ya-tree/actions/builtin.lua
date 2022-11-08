---@alias Yat.Actions.Name
---| "close_window"
---| "system_open"
---| "open_help"
---| "show_node_info"
---| "close_tree"
---| "delete_tree"
---| "focus_prev_tree"
---| "focus_next_tree"
---| "open_git_tree"
---| "open_buffers_tree"
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
---| "refresh_tree"
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
---| "toggle_ignored"
---| "toggle_filter"
---
---| "search_for_node_in_tree"
---| "search_interactively"
---| "search_once"
---
---| "goto_node_in_filesystem_tree"
---
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
    close_window = "close_window",
    system_open = "system_open",
    open_help = "open_help",
    show_node_info = "show_node_info",
    close_tree = "close_tree",
    delete_tree = "delete_tree",
    focus_prev_tree = "focus_prev_tree",
    focus_next_tree = "focus_next_tree",

    open_git_tree = "open_git_tree",
    open_buffers_tree = "open_buffers_tree",

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

    refresh_tree = "refresh_tree",

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

    toggle_ignored = "toggle_ignored",
    toggle_filter = "toggle_filter",
  },
  search = {
    search_for_node_in_tree = "search_for_node_in_tree",
    search_interactively = "search_interactively",
    search_once = "search_once",
  },
  tree_specific = {
    goto_node_in_filesystem_tree = "goto_node_in_filesystem_tree",
  },
  git = {
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

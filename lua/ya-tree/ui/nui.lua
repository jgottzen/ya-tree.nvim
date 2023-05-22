local lazy = require("ya-tree.lazy")

local Config = lazy.require("ya-tree.config") ---@module "ya-tree.config"
local hl = lazy.require("ya-tree.ui.highlights") ---@module "ya-tree.ui.highlights"
local NuiInput = lazy.require("nui.input") ---@module "nui.input"
local NuiPopup = lazy.require("nui.popup") ---@module "nui.popup"
local nui_autocmd = lazy.require("nui.utils.autocmd") ---@module "nui.utils.autocmd"

local api = vim.api
local fn = vim.fn

local M = {}

do
  ---@type string?
  local current_completion

  -- selene: allow(global_usage)
  ---@param start integer
  ---@param base string
  ---@return integer|string[]
  _G._ya_tree_input_complete = function(start, base)
    if start == 1 then
      return 0
    end
    return fn.getcompletion(base, current_completion)
  end

  ---@class Yat.Ui.InputOpts
  ---@field title string
  ---@field default? string defaults to an empty string.
  ---@field completion? string|fun(bufnr: integer)
  ---@field relative? string defaults to "cursor".
  ---@field row? integer defaults to 1.
  ---@field col? integer defaults to 1.
  ---@field width? integer defaults to 30.

  ---@param opts Yat.Ui.InputOpts
  ---@param callbacks {on_submit?: fun(text: string), on_close?: fun(), on_change?: fun(text: string)}
  ---  - {callbacks.on_submit?} `function(text: string): void`
  ---  - {callbacks.on_close?} `function(): void`
  ---  - {callbacks.on_change?} `function(text: string): void`
  function M.input(opts, callbacks)
    local border = Config.config.popups.border
    local options = {
      ns_id = hl.NS,
      relative = opts.relative or "cursor",
      position = { row = opts.row or 1, col = opts.col or 1 },
      size = opts.width or 30,
      border = {
        style = border,
        text = {
          top = opts.title,
          top_align = "left",
        },
      },
      win_options = {
        winhighlight = "Normal:YaTreeFloatNormal,FloatBorder:FloatBorder",
      },
    }
    current_completion = nil
    local completion = opts.completion
    if type(completion) == "string" then
      options.buf_options = {
        completefunc = "v:lua._ya_tree_input_complete",
        omnifunc = "",
      }
      if completion == "file_in_path" then
        options.buf_options.path = vim.loop.cwd() .. "/**"
      end
      current_completion = completion
    end

    local input = NuiInput(options, {
      default_value = opts.default,
      on_submit = callbacks.on_submit,
      on_change = callbacks.on_change,
      on_close = callbacks.on_close,
    })

    input:map("i", "<Esc>", function()
      input:unmount()
      if callbacks.on_close then
        callbacks.on_close()
      end
    end, { noremap = true })
    input:map("n", "<Esc>", function()
      input:unmount()
      if callbacks.on_close then
        callbacks.on_close()
      end
    end, { noremap = true })

    if completion then
      if type(completion) == "function" then
        completion(input.bufnr)
      end

      input:map("i", "<Tab>", function()
        if fn.pumvisible() == 1 then
          return api.nvim_replace_termcodes("<C-n>", true, false, true)
        else
          return api.nvim_replace_termcodes("<C-x><C-u>", true, false, true)
        end
      end, { expr = true })
      input:map("i", "<S-Tab>", function()
        if fn.pumvisible() == 1 then
          return api.nvim_replace_termcodes("<C-p>", true, false, true)
        else
          return api.nvim_replace_termcodes("<C-x><C-u>", true, false, true)
        end
      end, { expr = true })
      if fn.pumvisible() == 1 then
        local escape_key = api.nvim_replace_termcodes("<C-e>", true, false, true)
        api.nvim_feedkeys(escape_key, "n", true)
      end
    end

    input:mount()
  end
end

---@class Yat.Ui.PopupOpts
---@field title string
---@field relative? string defaults to "cursor".
---@field row? integer defaults to 1.
---@field col? integer defaults to 1.
---@field width integer|string
---@field height integer|string
---@field enter? boolean
---@field close_keys? string[]
---@field close_on_focus_loss? boolean
---@field on_close? fun()
---@field lines? string[]
---@field highlight_groups? Yat.Ui.HighlightGroup[][]

---@param opts Yat.Ui.PopupOpts
---@return NuiPopup
function M.popup(opts)
  local border = Config.config.popups.border
  local options = {
    ns_id = hl.NS,
    size = {
      width = opts.width,
      height = opts.height,
    },
    relative = opts.relative or "cursor",
    enter = opts.enter,
    border = {
      style = border,
      text = {
        top = opts.title,
        top_align = "center",
      },
    },
    win_options = {
      winhighlight = "Normal:YaTreeFloatNormal,FloatBorder:FloatBorder",
    },
  }
  if opts.relative == "editor" then
    options.position = "50%"
  else
    options.position = {
      row = opts.row or 1,
      col = opts.col or 1,
    }
  end

  local popup = NuiPopup(options)

  if opts.close_keys then
    for _, key in ipairs(opts.close_keys) do
      popup:map("n", key, function()
        popup:unmount()
        if opts.on_close then
          opts.on_close()
        end
      end, { noremap = true })
    end
  end
  if opts.close_on_focus_loss then
    popup:on({ nui_autocmd.event.BufLeave }, function()
      popup:unmount()
      if opts.on_close then
        opts.on_close()
      end
    end, { once = true })
  end

  if opts.lines then
    M.set_content_for_popup(popup, opts.lines, opts.highlight_groups)
  end

  popup:mount()

  return popup
end

---@param popup NuiPopup
---@param lines string[]
---@param highlight_groups? Yat.Ui.HighlightGroup[][]
function M.set_content_for_popup(popup, lines, highlight_groups)
  vim.bo[popup.bufnr].modifiable = true
  api.nvim_buf_set_lines(popup.bufnr, 0, -1, false, lines)
  if highlight_groups then
    for line, highlight_group in ipairs(highlight_groups) do
      for _, highlight in ipairs(highlight_group) do
        api.nvim_buf_add_highlight(popup.bufnr, popup.ns_id, highlight.name, line - 1, highlight.from, highlight.to)
      end
    end
  end
  vim.bo[popup.bufnr].modifiable = false
end

return M

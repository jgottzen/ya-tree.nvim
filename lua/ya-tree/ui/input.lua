local log = require("ya-tree.log")

local api = vim.api
local fn = vim.fn

---@class Input
---@field private winid number
---@field private bufnr number
---@field private prompt string
---@field private title string
---@field private title_winid? number
---@field private win_config table<string, any>
---@field private callbacks table<string, function>
---@field private orig_row number
---@field private orig_col number
local Input = {}
Input.__index = Input

---@type {name: string, value: string|boolean}[]
local buf_options = {
  { name = "bufhidden", value = "wipe" },
  { name = "buflisted", value = false },
  { name = "filetype", value = "YaTreeInput" },
  { name = "buftype", value = "prompt" },
  { name = "swapfile", value = false },
}

local win_options = {
  number = false,
  relativenumber = false,
  list = false,
  winfixwidth = true,
  winfixheight = true,
  foldenable = false,
  spell = false,
  signcolumn = "no",
  foldmethod = "manual",
  foldcolumn = "0",
  cursorcolumn = false,
  cursorlineopt = "line",
  wrap = false,
  winhl = table.concat({
    "Normal:Normal",
    "FloatBorder:FloatBorder",
  }, ","),
}

--- Create a new `Input`.
---
---@param opts {title: string, prompt?: string, win?: number, relative?: string, anchor?: string, row?: number, col?: number, width?: number}
---  - {opts.title} `string`
---  - {opts.prompt?} `string` defaults to an empty string.
---  - {opts.win?} `number`
---  - {opts.relative?} `string` defaults to `"cursor"`.
---  - {opts.anchor?} `string` defaults to `"SW"`.
---  - {opts.row?} `number` defaults to `1`.
---  - {opts.col?} `number` defaults to `1`.
---  - {opts.width?} `number` defaults to `30`.
---
---@param callbacks {on_submit?: fun(text: string), on_close?: fun(), on_change?: fun(text: string)}
---  - {callbacks.on_submit?} `function(text: string): void`
---  - {callbacks.on_close?} `function(): void`
---  - {callbacks.on_change?} `function(text: string): void`
---@return Input input
function Input:new(opts, callbacks)
  local this = setmetatable({
    prompt = opts.prompt or "",
    title = opts.title,
    win_config = {
      relative = opts.relative or "cursor",
      win = opts.win,
      anchor = opts.anchor or "SW",
      row = opts.row or 1,
      col = opts.col or 1,
      width = opts.width or 30,
      height = 1,
      style = "minimal",
      zindex = 150,
      border = "rounded",
    },
  }, self)

  callbacks = callbacks or {}
  this.callbacks = {
    on_submit = function(text)
      this:close()

      if callbacks.on_submit then
        callbacks.on_submit(text)
      end
    end,
    on_close = function()
      this:close()

      if callbacks.on_close then
        callbacks.on_close()
      end
    end,
  }

  if callbacks.on_change then
    this.callbacks.on_change = function()
      ---@type string
      local value = api.nvim_buf_get_lines(this.bufnr, 0, 1, false)[1]
      callbacks.on_change(value:sub(#this.prompt + 1))
    end
  end

  return this
end

---@param key string
---@param value boolean|string
---@return string
local function format_option(key, value)
  if value == true then
    return key
  elseif value == false then
    return string.format("no%s", key)
  else
    return string.format("%s=%s", key, value)
  end
end

function Input:_create_title()
  if self.title then
    -- HACK to force the parent window to position itself
    -- See https://github.com/neovim/neovim/issues/13403
    vim.cmd("redraw")

    local width = math.min(api.nvim_win_get_width(self.winid) - 2, 2 + api.nvim_strwidth(self.title))
    local bufnr = api.nvim_create_buf(false, true)
    ---@type number
    self.title_winid = api.nvim_open_win(bufnr, false, {
      relative = "win",
      win = self.winid,
      width = width,
      height = 1,
      row = -1,
      col = 1,
      focusable = false,
      zindex = self.win_config.zindex + 1,
      style = "minimal",
      noautocmd = false,
    })
    api.nvim_win_set_option(self.title_winid, "winblend", api.nvim_win_get_option(self.winid, "winblend"))
    api.nvim_buf_set_option(bufnr, "bufhidden", "wipe")
    local title = " " .. self.title:sub(1, math.min(width - 2, api.nvim_strwidth(self.title))) .. " "
    api.nvim_buf_set_lines(bufnr, 0, -1, true, { title })
    local ns = api.nvim_create_namespace("YaTreeInput")
    api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
    api.nvim_buf_add_highlight(bufnr, ns, "FloatTitle", 0, 0, -1)
  end
end

function Input:open()
  if self.winid then
    return
  end

  self.orig_row, self.orig_col = unpack(api.nvim_win_get_cursor(self.win_config.win or 0))

  ---@type number
  self.bufnr = api.nvim_create_buf(false, true)
  for _, v in ipairs(buf_options) do
    api.nvim_buf_set_option(self.bufnr, v.name, v.value)
  end

  ---@type number
  self.winid = api.nvim_open_win(self.bufnr, true, self.win_config)
  for k, v in pairs(win_options) do
    api.nvim_command(string.format("noautocmd setlocal %s", format_option(k, v)))
  end

  self:_create_title()

  if self.callbacks.on_change then
    api.nvim_buf_attach(self.bufnr, false, { on_lines = self.callbacks.on_change })
  end

  fn.prompt_setprompt(self.bufnr, self.prompt)
  fn.prompt_setcallback(self.bufnr, self.callbacks.on_submit)
  fn.prompt_setinterrupt(self.bufnr, self.callbacks.on_close)

  self:map("i", "<Esc>", function()
    -- just calling input:close() and then ui.reset_window() will still leave
    -- the tree window with relativenumber, forcing the interrupt handler set by
    -- prompt_setinterrupt solves it...
    ---@type string
    local keys = api.nvim_replace_termcodes("<C-c>", true, false, true)
    api.nvim_feedkeys(keys, "n", true)
  end, { noremap = true })

  vim.cmd("startinsert!")
end

function Input:close()
  if not self.winid then
    return
  end

  if api.nvim_buf_is_valid(self.bufnr) then
    api.nvim_buf_delete(self.bufnr, { force = true })
    self.bufnr = nil
  end

  if self.title_winid and api.nvim_win_is_valid(self.title_winid) then
    api.nvim_win_close(self.title_winid, true)
  end
  self.title_winid = nil

  if api.nvim_win_is_valid(self.winid) then
    api.nvim_win_close(self.winid, true)
  end

  self.winid = nil

  -- fix the cursor being moved one character to the left after leaving the input
  api.nvim_win_set_cursor(0, { self.orig_row, self.orig_col + 1 })
end

do
  ---@type table<string, fun(bufnr: number)>
  local handlers = {}
  local handler_id = 1

  ---@param bufnr number
  ---@param mode string
  ---@param key string
  ---@param handler fun(bufnr: number)|string
  ---@param opts? table<"'noremap'"|"'nowait'"|"'silent'"|"'script'"|"'expr'"|"'unique'", boolean>
  local function set_key_map(bufnr, mode, key, handler, opts)
    opts = opts or {}

    ---@type string
    local rhs
    if type(handler) == "function" then
      ---@type fun(bufnr: number)
      handlers[tostring(handler_id)] = handler
      rhs = string.format("<cmd>lua require('ya-tree.ui.input'):_execute(%s, %s)<CR>", bufnr, handler_id)
      handler_id = handler_id + 1
    else
      rhs = handler
    end

    log.trace("creating mapping for bufnr=%s, mode=%s, key=%s, rhs=%s, opts=%s", bufnr, mode, key, rhs, opts)
    api.nvim_buf_set_keymap(bufnr, mode, key, rhs, opts)
  end

  ---@param bufnr number
  ---@param id number
  function Input:_execute(bufnr, id)
    local handler = handlers[tostring(id)]
    if handler then
      log.trace("executing handler %s", id)
      handler(bufnr)
    else
      log.error("no handler for id %s, handlers=", id, handlers)
    end
  end

  ---@param mode string
  ---@param key string
  ---@param handler fun(bufnr: number)|string
  ---@param opts? table<"'noremap'"|"'nowait'"|"'silent'"|"'script'"|"'expr'"|"'unique'", boolean>
  function Input:map(mode, key, handler, opts)
    if not self.winid then
      error("Input not shown yet, call Input:open()")
    end

    set_key_map(self.bufnr, mode, key, handler, opts)
  end
end

return Input

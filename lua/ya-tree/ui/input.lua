local meta = require("ya-tree.meta")
local log = require("ya-tree.log")("ui")

local api = vim.api
local fn = vim.fn

---@class Yat.Ui.Input : Yat.Object
---@field new fun(self: Yat.Ui.Input, opts: Yat.Ui.InputOpts, callbacks: {on_submit?: fun(text: string), on_close?: fun(), on_change?: fun(text: string)}): Yat.Ui.Input
---@overload fun(opts: Yat.Ui.InputOpts, callbacks: {on_submit?: fun(text: string), on_close?: fun(), on_change?: fun(text: string)}): Yat.Ui.Input
---@field class fun(self: Yat.Ui.Input): Yat.Ui.Input
---
---@field private prompt string
---@field package default string
---@field private completion? string|fun(bufnr: integer)
---@field private winid? integer
---@field package bufnr? integer
---@field private title_winid? integer
---@field private win_config table<string, any>
---@field private callbacks table<string, function>
---@field package orig_row integer
---@field package orig_col integer
local Input = meta.create_class("Yat.Ui.Input")

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
    "Normal:YaTreeTextFloat",
    "FloatBorder:FloatBorder",
  }, ","),
}

---@class Yat.Ui.InputOpts
---@field title string
---@field prompt? string defaults to an empty string.
---@field default? string defaults to an empty string.
---@field completion? string|fun(bufnr: integer)
---@field win? integer
---@field relative? string defaults to "cursor".
---@field anchor? string defaults to "SW".
---@field row? integer defaults to 1.
---@field col? integer defaults to 1.
---@field width? integer defaults to 30.
---@field border? string|string[] defaults to "rounded".

---@private
---@param opts Yat.Ui.InputOpts
---  - {opts.title} `string`
---  - {opts.prompt?} `string` defaults to an empty string.
---  - {opts.default?} `string` defaults to an empty string.
---  - {opts.completion?} `string|fun(bufnr: intger)`
---  - {opts.win?} `integer`
---  - {opts.relative?} `string` defaults to `"cursor"`.
---  - {opts.anchor?} `string` defaults to `"SW"`.
---  - {opts.row?} `integer` defaults to `1`.
---  - {opts.col?} `integer` defaults to `1`.
---  - {opts.width?} `integer` defaults to `30`.
---  - {opts.border?} `string|string[]` defaults to "rounded".
---
---@param callbacks {on_submit?: fun(text: string), on_close?: fun(), on_change?: fun(text: string)}
---  - {callbacks.on_submit?} `function(text: string): void`
---  - {callbacks.on_close?} `function(): void`
---  - {callbacks.on_change?} `function(text: string): void`
function Input:init(opts, callbacks)
  self.prompt = opts.prompt or ""
  self.default = opts.default or ""
  self.completion = opts.completion
  self.win_config = {
    relative = opts.relative or "cursor",
    win = opts.win,
    anchor = opts.anchor or "SW",
    row = opts.row or 1,
    col = opts.col or 1,
    width = opts.width or 30,
    height = 1,
    style = "minimal",
    border = opts.border or "rounded",
    noautocmd = true,
  }

  callbacks = callbacks or {}
  self.callbacks = {
    on_submit = function(text)
      self:close()

      if callbacks.on_submit then
        callbacks.on_submit(text)
      end
    end,
    on_close = function()
      self:close()

      if callbacks.on_close then
        callbacks.on_close()
      end

      -- fix the cursor being moved one character to the left after leaving the input
      pcall(api.nvim_win_set_cursor, 0, { self.orig_row, self.orig_col + 1 })
    end,
  }

  if callbacks.on_change then
    self.callbacks.on_change = function()
      local value = api.nvim_buf_get_lines(self.bufnr, 0, 1, false)[1]
      callbacks.on_change(value:sub(#self.default + 1))
    end
  end
end

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

function Input:open()
  if self.winid then
    return
  end

  self.orig_row, self.orig_col = unpack(api.nvim_win_get_cursor(self.win_config.win or 0))

  self.bufnr = api.nvim_create_buf(false, true)
  for _, v in ipairs(buf_options) do
    api.nvim_buf_set_option(self.bufnr, v.name, v.value)
  end
  if type(self.completion) == "string" then
    api.nvim_buf_set_option(self.bufnr, "completefunc", "v:lua._ya_tree_input_complete")
    api.nvim_buf_set_option(self.bufnr, "omnifunc", "")
    if self.completion == "file_in_path" then
      api.nvim_buf_set_option(self.bufnr, "path", vim.loop.cwd() .. "/**")
    end
    current_completion = self.completion --[[@as string]]
  elseif type(self.completion) == "function" then
    self.completion(self.bufnr)
  end

  self.winid = api.nvim_open_win(self.bufnr, true, self.win_config)
  for k, v in pairs(win_options) do
    vim.wo[k] = v
  end

  self:_create_title()

  if self.callbacks.on_change then
    api.nvim_buf_attach(self.bufnr, false, { on_lines = self.callbacks.on_change })
  end

  fn.prompt_setprompt(self.bufnr, "")
  fn.prompt_setcallback(self.bufnr, self.callbacks.on_submit)
  fn.prompt_setinterrupt(self.bufnr, self.callbacks.on_close)
  api.nvim_buf_set_lines(self.bufnr, 0, -1, true, { self.default })

  self:map("i", "<Esc>", self.callbacks.on_close)
  if self.completion then
    self:map("i", "<Tab>", function()
      if fn.pumvisible() == 1 then
        return api.nvim_replace_termcodes("<C-n>", true, false, true)
      else
        return api.nvim_replace_termcodes("<C-x><C-u>", true, false, true)
      end
    end, { expr = true })
  end

  vim.cmd.startinsert({ bang = true })
  if self.completion and fn.pumvisible() == 1 then
    local escape_key = api.nvim_replace_termcodes("<C-e>", true, false, true)
    api.nvim_feedkeys(escape_key, "n", true)
  end
end

---@private
function Input:_create_title()
  if self.prompt then
    -- Force the Input window to position itself, otherwise relative = "win" is
    -- to the parent window of Input and not Input itself...
    -- see https://github.com/neovim/neovim/issues/14735
    vim.cmd.redraw()

    local width = math.min(api.nvim_win_get_width(self.winid) - 2, 2 + api.nvim_strwidth(self.prompt))
    local bufnr = api.nvim_create_buf(false, true)
    self.title_winid = api.nvim_open_win(bufnr, false, {
      relative = "win",
      win = self.winid,
      width = width,
      height = 1,
      row = -1,
      col = 1,
      focusable = false,
      zindex = 151,
      style = "minimal",
      noautocmd = true,
    })
    vim.opt_local["winblend"] = api.nvim_win_get_option(self.winid, "winblend")
    api.nvim_buf_set_option(bufnr, "bufhidden", "wipe")
    local title = " " .. self.prompt:sub(1, math.min(width - 2, api.nvim_strwidth(self.prompt))) .. " "
    api.nvim_buf_set_lines(bufnr, 0, -1, true, { title })
    local ns = api.nvim_create_namespace("YaTreeInput")
    api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
    api.nvim_buf_add_highlight(bufnr, ns, "FloatTitle", 0, 0, -1)
  end
end

function Input:close()
  if not self.winid then
    return
  end

  current_completion = nil
  -- we don't need to delete the buffer, it's wiped automatically, and doing so causes tabline issues...
  self.bufnr = nil

  if self.title_winid and api.nvim_win_is_valid(self.title_winid) then
    api.nvim_win_close(self.title_winid, true)
  end
  self.title_winid = nil

  if api.nvim_win_is_valid(self.winid) then
    api.nvim_win_close(self.winid, true)
  end
  self.winid = nil
end

---@param mode string
---@param key string
---@param rhs function|string
---@param opts? table<"remap"|"nowait"|"silent"|"script"|"expr"|"unique"|"desc", boolean>
function Input:map(mode, key, rhs, opts)
  if not self.winid then
    error("Input not shown yet, call Input:open()")
  end
  opts = opts or {}
  opts.buffer = self.bufnr

  log.trace("creating mapping for bufnr=%s, mode=%s, key=%s, rhs=%s, opts=%s", self.bufnr, mode, key, rhs, opts)
  vim.keymap.set(mode, key, rhs, opts)
end

return Input

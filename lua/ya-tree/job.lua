local wrap = require("plenary.async").wrap

local log = require("ya-tree.log")("job")

local uv = vim.loop

local M = {}

---@param opts {cmd: string, args: string[], cwd?: string, detached?: boolean}
---  - {opts.cmd} `string`
---  - {opts.args} `string[]`
---  - {opts.cwd?} `string`
---  - {opts.detached?} `boolean`
---@param on_complete fun(code: integer, stdout?: string, stderr?: string)
---@return integer|nil pid
function M.run(opts, on_complete)
  local state = {
    stdout = uv.new_pipe(false),
    stderr = uv.new_pipe(false),
    ---@type string[]
    stdout_data = {},
    ---@type string[]
    stderr_data = {},
    ---@type userdata
    handle = nil,
    ---@type integer
    pid = nil,
  }

  state.handle, state.pid = uv.spawn(opts.cmd, {
    args = opts.args,
    stdio = { nil, state.stdout, state.stderr },
    cwd = opts.cwd,
    detached = opts.detached,

    ---@param code integer
    ---@param signal integer
  }, function(code, signal)
    log.debug("%q completed with code=%s, signal=%s", opts.cmd, code, signal)

    if state.stdout then
      state.stdout:read_stop()
    end
    if state.stderr then
      state.stderr:read_stop()
    end

    if state.stdout and not state.stdout:is_closing() then
      state.stdout:close()
      state.stdout = nil
    end
    if state.stderr and not state.stderr:is_closing() then
      state.stderr:close()
      state.stderr = nil
    end
    if not state.handle:is_closing() then
      state.handle:close()
      state.handle = nil
    end

    local stdout = #state.stdout_data > 0 and table.concat(state.stdout_data) or nil
    local stderr = #state.stderr_data > 0 and table.concat(state.stderr_data) or nil

    on_complete(code, stdout, stderr)
    state = nil
  end)

  if state.handle then
    log.debug("spawned %q with arguments=%q, pid %s", opts.cmd, table.concat(opts.args, " "), state.pid)
    ---@param data string
    state.stdout:read_start(function(_, data)
      state.stdout_data[#state.stdout_data + 1] = data
    end)
    ---@param data string
    state.stderr:read_start(function(_, data)
      state.stderr_data[#state.stderr_data + 1] = data
    end)
    return state.pid
  else
    log.error("failed to spawn %q, error=%s", opts.cmd, tostring(state.pid))
    state.stdout:close()
    state.stderr:close()
    vim.schedule(function()
      on_complete(2, nil, tostring(state.pid))
      state = nil
    end)
    return nil
  end
end

---@type async fun(opts: {cmd: string, args: string[], cwd?: string, detached?: boolean}):integer, string?, string?
---  - {opts.cmd} `string`
---  - {opts.args} `string[]`
---  - {opts.cwd?} `string`
---  - {opts.detached?} `boolean`
M.async_run = wrap(function(opts, callback)
  M.run(opts, function(code, stdout, stderr)
    callback(code, stdout, stderr)
  end)
end, 2)

return M

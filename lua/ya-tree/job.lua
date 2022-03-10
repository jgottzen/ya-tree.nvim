local log = require("ya-tree.log")

local uv = vim.loop

local M = {}

---@param opts {cmd: string, args: string[], cwd?: string, detached?: boolean}
---  - {opts.cmd} `string`
---  - {opts.args} `string[]`
---  - {opts.cwd?} `string`
---  - {opts.detached?} `boolean`
---@param on_complete fun(code: number, stdout?: string, stderr?: string): nil
---@return table
function M.run(opts, on_complete)
  local state = {
    stdout = uv.new_pipe(false),
    stderr = uv.new_pipe(false),

    stdout_data = {},
    stderr_data = {},
  }

  state.handle, state.pid = uv.spawn(opts.cmd, {
    args = opts.args,
    stdio = { nil, state.stdout, state.stderr },
    cwd = opts.cwd,
    detached = opts.detached,
  }, function(code, signal)
    log.debug("%q completed with code=%s, signal=%s", opts.cmd, code, signal)

    state.code = code
    state.signal = signal

    if state.stdout then
      state.stdout:read_stop()
    end
    if state.stderr then
      state.stderr:read_stop()
    end

    if state.stdout and not state.stdout:is_closing() then
      state.stdout:close()
    end
    if state.stderr and not state.stderr:is_closing() then
      state.stderr:close()
    end

    local stdout = #state.stdout_data > 0 and table.concat(state.stdout_data) or nil
    local stderr = #state.stderr_data > 0 and table.concat(state.stderr_data) or nil

    on_complete(state.code, stdout, stderr)
  end)
  log.trace("spawned process %q with arguments=%q, pid %s", opts.cmd, opts.args, state.pid)

  state.stdout:read_start(function(_, data)
    state.stdout_data[#state.stdout_data + 1] = data
  end)
  state.stderr:read_start(function(_, data)
    state.stderr_data[#state.stderr_data + 1] = data
  end)

  return state
end

return M

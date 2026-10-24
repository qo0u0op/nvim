local tui_opening = false
local tui_pane_id

local function in_herdr()
  return vim.env.HERDR_ENV == "1" or (vim.env.HERDR_PANE_ID or "") ~= ""
end

local function terminal_tui_visible(buf)
  local win = vim.fn.bufwinid(buf)
  return win ~= -1 and vim.api.nvim_win_get_tabpage(win) == vim.api.nvim_get_current_tabpage()
end

local function has_terminal_tui()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) and terminal_tui_visible(buf) then
      local ok, value = pcall(vim.api.nvim_buf_get_var, buf, "opencode_tui")
      if ok and value then
        return true
      end
    end
  end
  return false
end

local function hidden_terminal_tui()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) and not terminal_tui_visible(buf) then
      local ok, value = pcall(vim.api.nvim_buf_get_var, buf, "opencode_tui")
      if ok and value then
        return buf
      end
    end
  end
end

local function pane_exists(pane_id)
  local ok, out = pcall(vim.fn.system, { "herdr", "pane", "get", pane_id })
  if not ok then
    return false
  end
  local decoded_ok, decoded = pcall(vim.fn.json_decode, out)
  return decoded_ok and decoded and decoded.result ~= nil
end

local function panes_for(workspace_id)
  local args = { "herdr", "pane", "list" }
  if workspace_id then
    table.insert(args, "--workspace")
    table.insert(args, workspace_id)
  end

  local ok, out = pcall(vim.fn.system, args)
  if not ok then
    return {}
  end
  local decoded_ok, decoded = pcall(vim.fn.json_decode, out)
  return decoded_ok and decoded and decoded.result and decoded.result.panes or {}
end

local function has_herdr_tui()
  if not in_herdr() or vim.fn.executable("herdr") == 0 then
    return false
  end

  if tui_pane_id then
    if pane_exists(tui_pane_id) then
      return true
    end
    tui_pane_id = nil
  end

  local ok, out = pcall(vim.fn.system, { "herdr", "workspace", "list" })
  local decoded_ok, decoded = pcall(vim.fn.json_decode, out)
  local workspaces = ok and decoded_ok and decoded and decoded.result and decoded.result.workspaces
  local panes = {}

  if workspaces and #workspaces > 0 then
    for _, workspace in ipairs(workspaces) do
      vim.list_extend(panes, panes_for(workspace.workspace_id))
    end
  else
    panes = panes_for()
  end

  for _, pane in ipairs(panes) do
    if pane.agent == "opencode" or (pane.terminal_title or ""):match("^OC ") then
      tui_pane_id = pane.pane_id
      return true
    end
  end

  return false
end

local function has_tui()
  return tui_opening or has_herdr_tui() or has_terminal_tui()
end

local function fallback_tui()
  local hidden = hidden_terminal_tui()
  if hidden then
    vim.cmd("sbuffer " .. hidden)
    vim.cmd("wincmd p")
    return
  end

  vim.cmd("vsplit | terminal opencode")
  local buf = vim.api.nvim_get_current_buf()
  vim.b[buf].opencode_tui = true

  vim.api.nvim_create_autocmd("TermClose", {
    buffer = buf,
    once = true,
    callback = function()
      if vim.api.nvim_buf_is_valid(buf) then
        vim.api.nvim_buf_delete(buf, { force = true })
      end
    end,
  })

  vim.cmd("wincmd p")
end

local function finish_opening()
  vim.defer_fn(function()
    tui_opening = false
  end, 30000)
end

local function open_tui()
  if has_tui() then
    return
  end

  tui_opening = true
  finish_opening()

  if not in_herdr() or vim.fn.executable("herdr") == 0 then
    fallback_tui()
    tui_opening = false
    return
  end

  local handled = false
  local function fail()
    if handled then
      return
    end
    handled = true
    tui_opening = false
    fallback_tui()
  end

  vim.fn.jobstart({
    "herdr",
    "pane",
    "split",
    "--current",
    "--direction",
    "right",
    "--cwd",
    vim.fn.getcwd(),
    "--no-focus",
  }, {
    stdout_buffered = true,
    on_exit = function()
      if not handled then
        fail()
      end
    end,
    on_stdout = function(_, data)
      if handled then
        return
      end

      local output = table.concat(data or {}, "")
      local ok, result = pcall(vim.fn.json_decode, output)
      if not (ok and result and result.result and result.result.pane) then
        return fail()
      end

      handled = true
      tui_pane_id = result.result.pane.pane_id
      tui_opening = false
      vim.fn.jobstart({
        "herdr",
        "pane",
        "run",
        tui_pane_id,
        "opencode",
      })
    end,
  })
end

local function ensure_tui()
  open_tui()
end

return {
  "nickjvandyke/opencode.nvim",
  -- HTTPS because this machine has no SSH key for the global lazy url_format.
  url = "https://github.com/nickjvandyke/opencode.nvim.git",
  -- version = "*", -- Stable release is v1-only; main supports OpenCode v2
  config = function()
    ---@type opencode.Opts
    vim.g.opencode_opts = {
      server = {
        start = function()
          -- 先確認背景 service 是否活著，藉此避開插件 5 次 × 1 秒的輪詢上限：
          -- 1. `service.json` 指向已死的 service 時，`opencode service start` 會先
          --    等約 5 秒才啟動新 service，剛好超過輪詢上限，所以先清掉死掉的註冊。
          -- 2. 由 TUI 間接啟動 service 要等 TUI 整個跑起來（實測約 5 秒），
          --    直接 `opencode service start` 只要約 0.5 秒。
          if vim.fn.executable("opencode") == 1 then
            local state_home = vim.env.XDG_STATE_HOME
            local state_dir = (state_home and state_home ~= "")
                and vim.fs.joinpath(state_home, "opencode")
              or vim.fs.joinpath(vim.uv.os_homedir() or vim.env.HOME or "", ".local", "state", "opencode")
            local service_json = vim.fs.joinpath(state_dir, "service.json")
            local registration = require("opencode.server.discovery").registration()
            local pid = registration and registration.pid
            if type(pid) == "number" and pid > 0 and vim.uv.kill(pid, 0) ~= 0 then
              vim.fn.delete(service_json)
            end
            vim.fn.jobstart({ "opencode", "service", "start" })
          end

          open_tui()
        end,
      },
    }

    vim.o.autoread = true -- Required for `vim.g.opencode_opts.events.reload`

    -- OpenCode v2 does not persist an empty TUI session, so `/api/session`
    -- returns nothing until the first prompt. Create one on demand.
    local Server = require("opencode.server")
    local Promise = require("opencode.promise")

    function Server:create_session()
      return self:request("/api/session", "POST", {
        location = { directory = vim.fn.getcwd() },
      }):next(function(response)
        local session = response and response.data
        if session and session.id then
          vim.notify("OpenCode: created a new session for " .. vim.fn.getcwd(), vim.log.levels.INFO)
          return session
        end
        return Promise.reject("Failed to create an OpenCode session for `" .. vim.fn.getcwd() .. "`")
      end)
    end

    local resolve_session = Server.resolve_session
    function Server:resolve_session()
      return resolve_session(self):catch(function(err)
        if type(err) == "string" and err:find("No OpenCode session found", 1, true) then
          return self:create_session()
        end
        return Promise.reject(err)
      end)
    end

    -- Recommended/example keymaps
    vim.keymap.set({ "n", "x" }, "<leader>ao", function()
      ensure_tui()
      require("opencode").ask("@this: ")
    end, { desc = "Ask OpenCode…" })
    vim.keymap.set({ "n", "x" }, "<leader>as", function()
      ensure_tui()
      require("opencode").select()
    end, { desc = "Select OpenCode…" })

    vim.keymap.set({ "n", "x" }, "go", function()
      ensure_tui()
      return require("opencode").operator("@this ")
    end, { desc = "Append range to OpenCode", expr = true })
    vim.keymap.set("n", "goo", function()
      ensure_tui()
      return require("opencode").operator("@this ") .. "_"
    end, { desc = "Append line to OpenCode", expr = true })
  end,
}

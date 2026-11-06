--------------------------------------------------------------------------------
-- 共用工具
--------------------------------------------------------------------------------

local tui_opening = false
local tui_pane_id

---@param path string
---@return string?
local function read_file(path)
  local fd = vim.uv.fs_open(path, "r", 0)
  if not fd then
    return nil
  end
  local stat = vim.uv.fs_fstat(fd)
  -- /proc 檔案的 st_size 是 0，所以不能直接拿 size 當讀取長度。
  local size = stat and stat.size or 0
  local data = vim.uv.fs_read(fd, size > 0 and size or 4096, 0)
  vim.uv.fs_close(fd)
  return data
end

---執行指令並解析 JSON 輸出；失敗回 nil。
---@param cmd string[]
---@return table?
local function run_json(cmd)
  local ok, proc = pcall(vim.system, cmd, { text = true })
  if not ok then
    return nil
  end
  local result = proc:wait()
  local decoded_ok, decoded = pcall(vim.json.decode, result.stdout or "")
  return decoded_ok and decoded or nil
end

---TUI 的啟動指令；有目標 session 時接續它，避免開一個全新的空 session。
---@param session_id string?
---@return string[]
local function tui_command(session_id)
  if type(session_id) == "string" and session_id:match("^ses_%w+$") then
    return { "opencode", "--session", session_id }
  end
  return { "opencode" }
end

--------------------------------------------------------------------------------
-- TUI 後端介面
--
-- 每個後端提供 snapshot()：ids（已知 session id）、titles（`OC | <標題>`）、
-- any（是否有任何 TUI，用於還沒解析出目標 session 時）。
--
-- 新增終端復用器（tmux / zellij…）只要實作 Multiplexer 的三個方法：
--   available() → 這個復用器是否可用
--   panes()     → MultiplexerPane[]（id / title / session_id / is_tui）
--   open()      → 開新 pane 執行 opencode
-- 然後加進 MULTIPLEXERS 即可，偵測邏輯會自動沿用。
--------------------------------------------------------------------------------

---@class TuiSnapshot
---@field ids table<string, boolean>
---@field titles string[]
---@field any boolean

---@class MultiplexerPane
---@field id string
---@field title? string
---@field session_id? string
---@field is_tui? boolean

---@class Multiplexer
---@field available fun(): boolean
---@field panes fun(): MultiplexerPane[]
---@field open fun(session_id: string?, on_fail: fun())

--------------------------------------------------------------------------------
-- 後端：nvim 內建 terminal
--------------------------------------------------------------------------------

---@param buf integer
---@return boolean
local function buffer_in_current_tab(buf)
  local tabpage = vim.api.nvim_get_current_tabpage()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
    if vim.api.nvim_win_get_buf(win) == buf then
      return true
    end
  end
  return false
end

---本 nvim 裡的 opencode TUI buffer。
---@param visible boolean
---@return integer[]
local function terminal_tui_buffers(visible)
  local buffers = {}
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if
      vim.api.nvim_buf_is_valid(buf)
      and buffer_in_current_tab(buf) == visible
      and vim.b[buf].opencode_tui
    then
      table.insert(buffers, buf)
    end
  end
  return buffers
end

local nvim_tui = {
  ---@return boolean
  available = function()
    return true
  end,

  ---@return TuiSnapshot
  snapshot = function()
    local snapshot = { ids = {}, titles = {}, any = false }
    for _, buf in ipairs(terminal_tui_buffers(true)) do
      snapshot.any = true
      local session_id = vim.b[buf].opencode_session
      if session_id then
        snapshot.ids[session_id] = true
      end
    end
    return snapshot
  end,

  ---@param session_id string?
  open = function(session_id)
    local hidden = terminal_tui_buffers(false)[1]
    if hidden then
      vim.cmd.sbuffer(hidden)
      vim.cmd.wincmd("p")
      return
    end

    local command = table.concat(vim.tbl_map(vim.fn.shellescape, tui_command(session_id)), " ")
    vim.cmd.vsplit()
    vim.cmd.terminal(command)
    local buf = vim.api.nvim_get_current_buf()
    vim.b[buf].opencode_tui = true
    vim.b[buf].opencode_session = session_id

    -- TUI 視窗常常停在 normal mode（尤其從其他視窗點進來時），此時 PgUp/PgDn
    -- 與滾輪只會在空的 terminal buffer 上滾。改成直接把翻頁鍵送進 TUI。
    for _, binding in ipairs({
      { "<PageUp>", "\x1b[5~", "Scroll OpenCode up" },
      { "<PageDown>", "\x1b[6~", "Scroll OpenCode down" },
      { "<ScrollWheelUp>", "\x1b[5~", "Scroll OpenCode up" },
      { "<ScrollWheelDown>", "\x1b[6~", "Scroll OpenCode down" },
    }) do
      local key, sequence, desc = binding[1], binding[2], binding[3]
      vim.keymap.set("n", key, function()
        local channel = vim.b[buf].terminal_job_id
        if channel then
          vim.api.nvim_chan_send(channel, sequence)
        end
      end, { buffer = buf, desc = desc })
    end

    vim.api.nvim_create_autocmd("TermClose", {
      buffer = buf,
      once = true,
      callback = function()
        if vim.api.nvim_buf_is_valid(buf) then
          vim.api.nvim_buf_delete(buf, { force = true })
        end
      end,
    })

    vim.cmd.wincmd("p")
  end,
}

--------------------------------------------------------------------------------
-- 復用器：herdr
--------------------------------------------------------------------------------

local function in_herdr()
  return vim.env.HERDR_ENV == "1" or (vim.env.HERDR_PANE_ID or "") ~= ""
end

---@param pane_id string
---@return boolean
local function pane_exists(pane_id)
  local decoded = run_json({ "herdr", "pane", "get", pane_id })
  return decoded ~= nil and decoded.result ~= nil
end

---@param workspace_id string?
---@return table[]
local function panes_for(workspace_id)
  local cmd = { "herdr", "pane", "list" }
  if workspace_id then
    table.insert(cmd, "--workspace")
    table.insert(cmd, workspace_id)
  end
  local decoded = run_json(cmd)
  return decoded and decoded.result and decoded.result.panes or {}
end

---所有 workspace 的 herdr pane。
---@return table[]
local function herdr_panes()
  local decoded = run_json({ "herdr", "workspace", "list" })
  local workspaces = decoded and decoded.result and decoded.result.workspaces
  if not workspaces or #workspaces == 0 then
    return panes_for()
  end

  local panes = {}
  for _, workspace in ipairs(workspaces) do
    vim.list_extend(panes, panes_for(workspace.workspace_id))
  end
  return panes
end

---@type Multiplexer
local herdr = {
  available = function()
    return in_herdr() and vim.fn.executable("herdr") == 1
  end,

  panes = function()
    local panes = {}
    local own_pane_seen = false

    for _, pane in ipairs(herdr_panes()) do
      local reference = pane.agent_session
      panes[#panes + 1] = {
        id = pane.pane_id,
        title = pane.terminal_title,
        is_tui = pane.agent == "opencode",
        session_id = (reference and reference.kind == "id") and reference.value or nil,
      }
      if pane.pane_id == tui_pane_id then
        own_pane_seen = true
      end
    end

    -- 自己開的 pane 可能還在啟動，先當成 TUI，避免重複開
    if tui_pane_id and not own_pane_seen then
      if pane_exists(tui_pane_id) then
        panes[#panes + 1] = { id = tui_pane_id, is_tui = true }
      else
        tui_pane_id = nil
      end
    end

    return panes
  end,

  open = function(session_id, on_fail)
    local handled = false
    local function fail()
      if handled then
        return
      end
      handled = true
      on_fail()
    end

    vim.system({
      "herdr",
      "pane",
      "split",
      "--current",
      "--direction",
      "right",
      "--cwd",
      vim.uv.cwd() or "",
      "--no-focus",
    }, { text = true }, function(result)
      if handled then
        return
      end

      local ok, decoded = pcall(vim.json.decode, result.stdout or "")
      if not (ok and decoded and decoded.result and decoded.result.pane) then
        return fail()
      end

      handled = true
      tui_pane_id = decoded.result.pane.pane_id
      tui_opening = false
      vim.system(vim.list_extend({ "herdr", "pane", "run", tui_pane_id }, tui_command(session_id)))
    end)
  end,
}

--------------------------------------------------------------------------------
-- 後端：kitty（靠視窗標題辨識 session）
--------------------------------------------------------------------------------

---所有 kitty 實例的 socket 路徑（各實例各自一個 `kitty-<pid>`）。
---@return string[]
local function kitty_sockets()
  local sockets = {}
  for _, dir in ipairs({ vim.env.XDG_RUNTIME_DIR, "/tmp" }) do
    if dir and dir ~= "" and vim.uv.fs_stat(dir) then
      for name, kind in vim.fs.dir(dir) do
        if kind == "socket" and name:match("^kitty%-%d+$") then
          table.insert(sockets, vim.fs.joinpath(dir, name))
        end
      end
    end
  end
  return sockets
end

---TUI 會把視窗標題設成 `OC | <session 標題>`。
---@return string[]
local function kitty_session_titles()
  local titles = {}
  for _, socket in ipairs(kitty_sockets()) do
    local decoded = run_json({ "kitty", "@", "--to", "unix:" .. socket, "ls" })
    if type(decoded) == "table" then
      for _, os_window in ipairs(decoded) do
        for _, tab in ipairs(os_window.tabs or {}) do
          for _, window in ipairs(tab.windows or {}) do
            local marker = (window.title or ""):match("^OC | (.+)$")
            if marker then
              table.insert(titles, marker)
            end
          end
        end
      end
    end
  end
  return titles
end

local kitty = {
  ---@return boolean
  available = function()
    return vim.fn.executable("kitty") == 1
  end,

  ---@return TuiSnapshot
  snapshot = function()
    return { ids = {}, titles = kitty_session_titles(), any = false }
  end,
}

--------------------------------------------------------------------------------
-- 後端：/proc（無法辨識 session，只能比對 cwd）
--------------------------------------------------------------------------------

-- 帶這些子命令的 `opencode` 不是互動式 TUI（例如背景 service 或一次性執行）。
-- 注意 `mini` 是互動式介面，不能列進來；新增子命令時要同步更新。
local NON_TUI_SUBCOMMANDS = {
  acp = true,
  api = true,
  auth = true,
  debug = true,
  mcp = true,
  models = true,
  pair = true,
  plugin = true,
  reload = true,
  run = true,
  serve = true,
  service = true,
  session = true,
  stats = true,
  uninstall = true,
  update = true,
  upgrade = true,
}

---同一目錄是否已有其他 opencode TUI（例如另一個 kitty 視窗／分頁）。
---@return boolean
local function process_tui_in_cwd()
  local cwd = vim.uv.cwd() or ""
  cwd = vim.uv.fs_realpath(cwd) or cwd

  for name, kind in vim.fs.dir("/proc") do
    if kind == "directory" and name:match("^%d+$") then
      local cmdline = read_file("/proc/" .. name .. "/cmdline")
      if cmdline and cmdline ~= "" then
        local args = vim.split(cmdline, "\0", { plain = true })
        local exe = args[1] and vim.fs.basename(args[1]) or ""
        if exe == "opencode" and not NON_TUI_SUBCOMMANDS[args[2] or ""] then
          local process_cwd = vim.uv.fs_readlink("/proc/" .. name .. "/cwd")
          if process_cwd and (vim.uv.fs_realpath(process_cwd) or process_cwd) == cwd then
            return true
          end
        end
      end
    end
  end

  return false
end

local process = {
  ---@return boolean
  available = function()
    return vim.uv.fs_stat("/proc") ~= nil
  end,

  ---@return TuiSnapshot
  snapshot = function()
    return { ids = {}, titles = {}, any = process_tui_in_cwd() }
  end,
}

--------------------------------------------------------------------------------
-- 後端註冊
--------------------------------------------------------------------------------

---把 multiplexer 轉成統一的 TUI 後端介面。
---@param mux Multiplexer
---@return table
local function multiplexer_backend(mux)
  return {
    available = mux.available,
    ---@return TuiSnapshot
    snapshot = function()
      local snapshot = { ids = {}, titles = {}, any = false }
      for _, pane in ipairs(mux.panes()) do
        if pane.session_id then
          snapshot.ids[pane.session_id] = true
        end
        local marker = (pane.title or ""):match("^OC | (.+)$")
        if marker then
          table.insert(snapshot.titles, marker)
        end
        if pane.is_tui or marker then
          snapshot.any = true
        end
      end
      return snapshot
    end,
  }
end

---可用的終端復用器；之後加 tmux / zellij 時加在這裡。
---@type Multiplexer[]
local MULTIPLEXERS = { herdr }

local BACKENDS = {
  nvim_tui,
  multiplexer_backend(herdr),
  kitty,
  process,
}

--------------------------------------------------------------------------------
-- TUI 查詢
--------------------------------------------------------------------------------

---合併所有後端的 snapshot。
---@return TuiSnapshot
local function tui_snapshot()
  local merged = { ids = {}, titles = {}, any = false }
  for _, backend in ipairs(BACKENDS) do
    if backend.available() then
      local snapshot = backend.snapshot()
      for session_id in pairs(snapshot.ids) do
        merged.ids[session_id] = true
      end
      vim.list_extend(merged.titles, snapshot.titles)
      merged.any = merged.any or snapshot.any
    end
  end
  return merged
end

---@param session opencode.server.Session?
---@return boolean
local function archived(session)
  return (session and session.time and session.time.archived) and true or false
end

---@param session opencode.server.Session
---@param snapshot TuiSnapshot
---@param exact boolean
---@return boolean
local function session_shown(session, snapshot, exact)
  if snapshot.ids[session.id] then
    return true
  end

  local title = session.title
  if type(title) ~= "string" then
    return false
  end

  for _, shown in ipairs(snapshot.titles) do
    if exact and shown == title then
      return true
    end
    -- 標題可能被截斷，所以也接受前綴
    if not exact and shown ~= "" and title:sub(1, #shown) == shown then
      return true
    end
  end

  return false
end

---該 session 是否已經顯示在某個 TUI。
---@param session opencode.server.Session
---@param snapshot TuiSnapshot
---@return boolean
local function session_visible(session, snapshot)
  return session_shown(session, snapshot, true) or session_shown(session, snapshot, false)
end

---專案內、目前有 TUI 正在顯示的 session（新的優先）。
---@param sessions opencode.server.Session[]?
---@param snapshot TuiSnapshot
---@return opencode.server.Session?
local function displayed_session(sessions, snapshot)
  -- 先比對完全相同的標題，再比對被截斷的前綴
  for _, exact in ipairs({ true, false }) do
    for _, session in ipairs(sessions or {}) do
      if not archived(session) and session_shown(session, snapshot, exact) then
        return session
      end
    end
  end
end

--------------------------------------------------------------------------------
-- OpenCode server／session 解析
--------------------------------------------------------------------------------

---@param sessions opencode.server.Session[]?
---@return opencode.server.Session?
local function newest_session(sessions)
  for _, session in ipairs(sessions or {}) do
    if not archived(session) then
      return session
    end
  end
end

---@param sessions opencode.server.Session[]?
---@param directory string
---@return opencode.server.Session?
local function newest_session_in(sessions, directory)
  for _, session in ipairs(sessions or {}) do
    local location = session.location
    if not archived(session) and location and location.directory == directory then
      return session
    end
  end
end

---@class ProjectInfo
---@field id string
---@field directory string

-- nvim cwd → OpenCode 專案資訊（快取）
local project_cache = {}

---OpenCode 認為的專案（通常是 git 根目錄）；取不到就退回 nvim 的 cwd。
---@param server opencode.server.Server
---@return Promise<ProjectInfo>
local function project_info(server)
  local Promise = require("opencode.promise")
  local cwd = vim.uv.cwd() or ""
  local cached = project_cache[cwd]
  if cached then
    return Promise.resolve(cached)
  end

  return server
    :request("/api/location", "GET")
    :next(function(response)
      local project = response and response.project or {}
      local info = {
        id = type(project.id) == "string" and project.id or "",
        directory = type(project.canonical) == "string" and project.canonical or cwd,
      }
      project_cache[cwd] = info
      return Promise.resolve(info)
    end)
    :catch(function()
      return Promise.resolve({ id = "", directory = cwd })
    end)
end

---@param server opencode.server.Server
---@param directory string
---@return Promise<opencode.server.Session[]>
local function sessions_in(server, directory)
  local Promise = require("opencode.promise")
  local path = "/api/session?directory=" .. vim.uri_encode(directory) .. "&order=desc&parentID=null"
  return server:request(path, "GET"):next(function(response)
    return Promise.resolve(response and response.data or {})
  end)
end

---整個專案（含子目錄）的 session。
---@param server opencode.server.Server
---@param project_id string
---@return Promise<opencode.server.Session[]>
local function project_sessions(server, project_id)
  local Promise = require("opencode.promise")
  if project_id == "" then
    return Promise.resolve({})
  end
  local path = "/api/session?project="
    .. vim.uri_encode(project_id)
    .. "&order=desc&parentID=null&limit=50"
  return server:request(path, "GET"):next(function(response)
    return Promise.resolve(response and response.data or {})
  end)
end

---優先序：專案內 TUI 正在顯示的 session → 目前 cwd 最新 → 專案目錄最新。
---@param server opencode.server.Server
---@return Promise<opencode.server.Session?>
local function preferred_session(server)
  local Promise = require("opencode.promise")
  local cwd = vim.uv.cwd() or ""

  return project_info(server):next(function(project)
    return project_sessions(server, project.id):next(function(sessions)
      if #sessions == 0 and project.id == "" then
        -- 拿不到專案資訊時，退回只看目前 cwd
        return sessions_in(server, cwd):next(function(cwd_sessions)
          return Promise.resolve(newest_session(cwd_sessions))
        end)
      end

      local shown = displayed_session(sessions, tui_snapshot())
      if shown then
        return Promise.resolve(shown)
      end

      local session = newest_session_in(sessions, cwd)
      if session then
        return Promise.resolve(session)
      end

      -- nvim 可能開在子目錄（例如從 yazi 開檔），此時沿用專案目錄的對話，
      -- 而不是另外開一個新 session。
      return Promise.resolve(newest_session_in(sessions, project.directory))
    end)
  end)
end

--------------------------------------------------------------------------------
-- 開啟 TUI
--------------------------------------------------------------------------------

local function finish_opening()
  vim.defer_fn(function()
    tui_opening = false
  end, 30000)
end

---@param session_id string?
---@param force boolean? 已經在外層決定要開時，略過「已有 TUI」的檢查
local function open_tui(session_id, force)
  if tui_opening then
    return
  end

  if not force and tui_snapshot().any then
    return
  end

  tui_opening = true
  finish_opening()

  local function fallback()
    nvim_tui.open(session_id)
    tui_opening = false
  end

  for _, mux in ipairs(MULTIPLEXERS) do
    if mux.available() then
      mux.open(session_id, fallback)
      return
    end
  end

  fallback()
end

---@param create boolean? 沒有任何對話時，是否先建立一個（ask/operator 需要）
local function ensure_tui(create)
  local Promise = require("opencode.promise")

  if tui_opening then
    return
  end

  -- 先解析目標 session（需要時順便拉起 service）。沒有對話就先建立，這樣
  -- 新開的 TUI 可以直接用 --session 接上，而不是停在 new session。
  tui_opening = true
  finish_opening()

  require("opencode.server.discovery")
    .get()
    :next(function(server)
      return preferred_session(server):next(function(session)
        if session or not create then
          return Promise.resolve(session)
        end
        return server:create_session()
      end)
    end)
    :next(function(session)
      local snapshot = tui_snapshot()
      -- 該對話已經顯示在某個 TUI 就不重開；同 cwd 的外部 TUI 也算。
      local visible
      if session then
        visible = session_visible(session, snapshot) or process_tui_in_cwd()
      else
        visible = snapshot.any
      end

      tui_opening = false
      if visible then
        return
      end

      open_tui(session and session.id or nil, true)
    end)
    :catch(function()
      tui_opening = false
      open_tui()
    end)
end

--------------------------------------------------------------------------------
-- 插件設定
--------------------------------------------------------------------------------

---清掉已失效的 service 註冊檔：`opencode service start` 遇到死掉的註冊時會先等
---約 5 秒才啟動新 service，剛好超過插件 5 次 × 1 秒的輪詢上限。
local function remove_stale_registrations()
  local state_home = vim.env.XDG_STATE_HOME
  local state_dir = (state_home and state_home ~= "")
      and vim.fs.joinpath(state_home, "opencode")
    or vim.fs.joinpath(vim.uv.os_homedir() or vim.env.HOME or "", ".local", "state", "opencode")

  if not vim.uv.fs_stat(state_dir) then
    return
  end

  for name, kind in vim.fs.dir(state_dir) do
    if kind == "file" and (name == "service.json" or name:match("^service%-.+%.json$")) then
      local path = vim.fs.joinpath(state_dir, name)
      local content = read_file(path)
      local decoded_ok, decoded = false, nil
      if content and content ~= "" then
        decoded_ok, decoded = pcall(vim.json.decode, content)
      end
      local pid = decoded_ok and type(decoded) == "table" and decoded.pid
      if type(pid) == "number" and pid > 0 and vim.uv.kill(pid, 0) ~= 0 then
        vim.uv.fs_unlink(path)
      end
    end
  end
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
          if vim.fn.executable("opencode") == 1 then
            remove_stale_registrations()
            vim.system({ "opencode", "service", "start" })
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
      return project_info(self):next(function(project)
        return self:request("/api/session", "POST", {
          location = { directory = project.directory },
        }):next(function(response)
          local session = response and response.data
          if session and session.id then
            vim.notify("OpenCode: created a new session for " .. project.directory, vim.log.levels.INFO)
            return session
          end
          return Promise.reject("Failed to create an OpenCode session for `" .. project.directory .. "`")
        end)
      end)
    end

    function Server:resolve_session()
      -- 優先使用專案內某個 TUI 正在顯示的 session，其次才是 cwd／專案目錄最新的；
      -- 都沒有才建立（建在專案目錄，不是 nvim 所在的子目錄）。
      return preferred_session(self):next(function(session)
        if session then
          return Promise.resolve(session)
        end
        return self:create_session()
      end)
    end

    -- Recommended/example keymaps
    vim.keymap.set({ "n", "x" }, "<leader>ao", function()
      ensure_tui(true)
      require("opencode").ask("@this: ")
    end, { desc = "Ask OpenCode…" })
    vim.keymap.set({ "n", "x" }, "<leader>as", function()
      ensure_tui()
      require("opencode").select()
    end, { desc = "Select OpenCode…" })

    vim.keymap.set({ "n", "x" }, "go", function()
      ensure_tui(true)
      return require("opencode").operator("@this ")
    end, { desc = "Append range to OpenCode", expr = true })
    vim.keymap.set("n", "goo", function()
      ensure_tui(true)
      return require("opencode").operator("@this ") .. "_"
    end, { desc = "Append line to OpenCode", expr = true })
  end,
}

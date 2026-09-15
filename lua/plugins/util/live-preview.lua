return {
  "brianhuster/live-preview.nvim",
  dependencies = {
    "ibhagwan/fzf-lua",
  },
  ft = { "markdown", "svg", "html", "css", "javascript", "d2" },
  keys = {
    { "<leader>kpl", "<cmd>LivePreview start<cr>", desc = "Start LivePreview" },
    { "<leader>kpc", "<cmd>LivePreview close<cr>", desc = "Close LivePreview" },
  },
  opts = {
    browser = "terminal-browser",
    port = 5500, -- 與 d2 --port 5500 保持一致
  },
  config = function(_, opts)
    require("livepreview.config").set(opts)

    local BLOCKED = "/__blocked__.png"
    local VAULT_BLOCKED = "/__vault_blocked__.png"

    local d2_job = nil

    local function stop_d2()
      if d2_job then
        local status = vim.fn.jobwait({ d2_job }, 0)[1]
        if status == -1 then
          vim.fn.jobstop(d2_job)
          vim.notify("d2 --watch 已終止")
        end
        d2_job = nil
      end
    end

    -- 共用小工具 ---------------------------------------------------------
    local function count_dotdot(s)
      local c = 0
      for _ in s:gmatch("%.%.") do
        c = c + 1
      end
      return c
    end

    local function is_under(path, root)
      root = vim.fs.normalize(root)
      path = vim.fs.normalize(path)
      if root:sub(-1) ~= "/" then
        root = root .. "/"
      end
      return path:sub(1, #root) == root
    end

    -- 去掉 title / 引號 / <操作>，只取路徑本體
    local function clean_src(raw)
      local s = vim.trim(raw or "")
      local first = s:match("^([^%s]+)")
      if first then
        s = first
      end
      return (s:gsub("^<", ""):gsub(">$", ""):gsub("^[\"']", ""):gsub("[\"']$", ""))
    end

    local function is_external(src)
      return src == "" or src:match("^%a+://") or src:match("^data:") or src:match("^#")
    end

    -- 向上搜尋 `.clin`（檔案或目錄）作為 vault root
    local function find_vault_root(filepath)
      local dir = vim.fs.dirname(vim.fs.normalize(filepath))
      while dir and dir ~= "" do
        if vim.uv.fs_stat(vim.fs.joinpath(dir, ".clin")) then
          return vim.fs.normalize(dir)
        end
        local parent = vim.fs.dirname(dir)
        if not parent or parent == dir then
          break
        end
        dir = parent
      end
      return nil
    end

    local function get_clin_vault()
      local f = io.open(vim.fn.expand("~/.config/clin/config.toml"), "r")
      if f then
        local c = f:read("*a")
        f:close()
        local p = c and c:match('storage_path%s*=%s*"([^"]+)"')
        if p then
          p = p:gsub("^~", vim.fn.expand("~")):gsub("%$([%w_]+)", function(v)
            return os.getenv(v) or ("$" .. v)
          end)
          p = vim.fs.normalize(p)
          if vim.uv.fs_stat(p) then
            return p
          end
        end
      end
      local def = vim.fs.normalize(vim.fn.expand("~/Documents/Onedrive/clin"))
      if vim.uv.fs_stat(def) then
        return def
      end
      return nil
    end

    local function is_tmp_clin_file(filepath)
      return vim.fs.normalize(filepath):match("^/tmp/clin/") ~= nil
    end

    -- 收集 markdown `![]()` 與 html `<img src>` 的原始路徑
    local function collect_img_srcs(content)
      local out = {}
      for img in content:gmatch("!%[[^%]]*%]%(([^%)]+)%)") do
        local s = clean_src(img)
        if s ~= "" and not s:match("^%a+://") and not s:match("^data:") and not s:match("^/") and not s:match("^#") then
          table.insert(out, s)
        end
      end
      for img in content:gmatch("<img[^>]+src%s*=%s*[\"']([^\"']+)[\"']") do
        local s = clean_src(img)
        if s ~= "" and not s:match("^%a+://") and not s:match("^data:") and not s:match("^/") then
          table.insert(out, s)
        end
      end
      return out
    end

    -- 無 `.clin` 時，從圖片實際位置推斷 webroot（例：test/new/test.md + ../img -> test）
    local function infer_webroot_from_images(filepath)
      local f = io.open(filepath, "r")
      if not f then
        return nil
      end
      local content = f:read("*a")
      f:close()
      if not content or content == "" then
        return nil
      end
      local dir = vim.fs.dirname(vim.fs.normalize(filepath))
      local cwd = vim.fs.normalize(vim.uv.cwd() or "")

      local function resolve_abs(src)
        if is_external(src) or src:sub(1, 1) == "/" or src:find("//") or count_dotdot(src) > 1 then
          return nil
        end
        local clean = clean_src(src:gsub("^%./", ""))
        local abs = vim.fs.normalize(vim.fs.joinpath(dir, clean))
        if vim.uv.fs_stat(abs) then
          return abs
        end
        -- 向上搜尋（處理 vault-relative `img/...` 在無 vault 時的情況）
        local cur = vim.fs.dirname(dir)
        while cur and cur ~= "" do
          local cand = vim.fs.normalize(vim.fs.joinpath(cur, clean))
          if vim.uv.fs_stat(cand) then
            return cand
          end
          if vim.fs.normalize(cur) == cwd then
            break
          end
          local parent = vim.fs.dirname(cur)
          if not parent or parent == cur then
            break
          end
          cur = parent
        end
        return abs
      end

      local abs_paths = {}
      for _, src in ipairs(collect_img_srcs(content)) do
        local abs = resolve_abs(src)
        if abs then
          table.insert(abs_paths, abs)
        end
      end
      if #abs_paths == 0 then
        return nil
      end
      local candidate = dir
      while candidate and candidate ~= "" do
        local all_inside = true
        for _, p in ipairs(abs_paths) do
          if not is_under(p, candidate) and p ~= vim.fs.normalize(candidate) then
            all_inside = false
            break
          end
        end
        if all_inside then
          return vim.fs.normalize(candidate)
        end
        local parent = vim.fs.dirname(candidate)
        if not parent or parent == candidate then
          break
        end
        candidate = parent
      end
      return nil
    end

    -- 依 vault 規則重寫圖片路徑
    -- - 有 vault：`img/...` 視為 vault 相對 -> `/img/...`；`../` 按 file-relative 解析，逃出 vault 者 blocked
    -- - 無 vault：解析後轉為 webroot 絕對 `/...`，逃出 webroot 者 blocked
    -- - `//`、`../../..` 一律 blocked
    local function rewrite_content(content, filepath, webroot, has_vault)
      if not content or content == "" or not webroot or not filepath then
        return content
      end
      local blocked = has_vault and VAULT_BLOCKED or BLOCKED
      local dir = vim.fs.dirname(vim.fs.normalize(filepath))
      local utils = require("livepreview.utils")

      local function transform(src)
        src = vim.trim(src)
        if is_external(src) then
          return src
        end
        if src:find("//") or count_dotdot(src) > 1 then
          return blocked
        end
        if src:sub(1, 1) == "/" then
          if src:find("%.%.") then
            return BLOCKED
          end
          return src
        end
        if has_vault then
          if src:find("%.%.") then
            -- 注意：gsub 會回傳 (字串, 次數)，需先存成 local 再傳入 joinpath，避免次數被當成第三個參數
            local clean = src:gsub("^%./", "")
            local abs = vim.fs.normalize(vim.fs.joinpath(dir, clean))
            if not is_under(abs, webroot) then
              return blocked
            end
            local rel = utils.get_relative_path(abs, webroot)
            return rel and ("/" .. rel) or blocked
          end
          local clean = src:gsub("^%./", "")
          return "/" .. clean
        end
        -- 無 vault：不含 `..` 時優先 file-relative，不存在則回退 webroot-relative
        local clean = src:gsub("^%./", "")
        if not src:find("%.%.") then
          local abs_file = vim.fs.normalize(vim.fs.joinpath(dir, clean))
          local rel_file = utils.get_relative_path(abs_file, webroot)
          if rel_file and vim.uv.fs_stat(abs_file) then
            return "/" .. rel_file
          end
          local abs_web = vim.fs.normalize(vim.fs.joinpath(webroot, clean))
          if vim.uv.fs_stat(abs_web) then
            local rel_web = utils.get_relative_path(abs_web, webroot)
            return rel_web and ("/" .. rel_web) or ("/" .. clean)
          end
        end
        local abs = vim.fs.normalize(vim.fs.joinpath(dir, clean))
        if not is_under(abs, webroot) then
          return blocked
        end
        local rel = utils.get_relative_path(abs, webroot)
        return rel and ("/" .. rel) or src
      end

      -- markdown: ![alt](src) 需保留 title
      content = content:gsub("!%[([^%]]*)%]%(([^%)]+)%)", function(alt, inside)
        local path, rest = vim.trim(inside):match("^([^%s]+)%s*(.*)$")
        if not path then
          return "![" .. alt .. "](" .. inside .. ")"
        end
        local new_path = transform(clean_src(path))
        if rest and rest ~= "" then
          return "![" .. alt .. "](" .. new_path .. " " .. rest .. ")"
        end
        return "![" .. alt .. "](" .. new_path .. ")"
      end)
      -- html: <img src="...">
      content = content:gsub("<img([^>]-)src%s*=%s*[\"']([^\"']+)[\"']", function(pre, src)
        return "<img" .. pre .. 'src="' .. transform(clean_src(src)) .. '"'
      end)
      return content
    end

    -- 當前預覽的生效上下文；serve 攔截只安裝一次，避免每次 start 重複包裝
    local active = { filepath = nil, webroot = nil, has_vault = false, tmp_clin_file = nil }

    -- 依 vault root（優先）/ 圖片推斷 / cwd 決定 webroot 與 urlpath
    local function resolve_webroot_and_urlpath(filepath, utils)
      filepath = vim.fs.normalize(filepath)
      -- clin 外部編輯器會複製 /tmp/clin/clin_{uuid}.md，圖片仍為 vault 相對，需以原始 vault 為 webroot
      if is_tmp_clin_file(filepath) then
        local vault = get_clin_vault()
        if vault then
          return vault, vim.fs.basename(filepath), true
        end
      end
      local vault_root = find_vault_root(filepath)
      local has_vault = vault_root ~= nil
      local webroot = vault_root or infer_webroot_from_images(filepath)
      if not webroot then
        webroot = vim.fs.normalize(vim.uv.cwd() or "")
      end
      local urlpath = utils.get_relative_path(filepath, webroot)
      if not urlpath then
        webroot = vim.fs.dirname(filepath)
        urlpath = vim.fs.basename(filepath)
        has_vault = false
      end
      return webroot, urlpath, has_vault
    end

    -- 攔截 handler.serve_file（只需安裝一次，讀取 active 上下文）
    -- handler 內部以局部變數捕獲 toHTML，直接覆蓋 template.toHTML 無效，故覆蓋 serve_file
    local function ensure_serve_intercept()
      local handler = require("livepreview.server.handler")
      if handler._vault_intercepted then
        return
      end
      handler._vault_intercepted = true
      handler.serve_file = function(client, file_path, if_none_match, accept)
        -- /tmp/clin/clin_{uuid}.md：頁面存於 /tmp，但 webroot 為原始 vault，需導向實際 tmp 檔案
        if active.tmp_clin_file and active.webroot then
          local base = vim.fs.basename(active.tmp_clin_file)
          local expected = vim.fs.normalize(vim.fs.joinpath(active.webroot, base))
          if vim.fs.normalize(file_path) == expected and vim.uv.fs_stat(active.tmp_clin_file) then
            file_path = active.tmp_clin_file
          end
        end
        local read_file = require("livepreview.utils").async_read_file
        local supported_filetype = require("livepreview.utils").supported_filetype
        local toHTML = require("livepreview.template").toHTML
        local handle_body = require("livepreview.template").handle_body
        local get_content_type = require("livepreview.server.utils.content_type").get
        local generate_etag = require("livepreview.server.utils.etag").generate
        read_file(file_path, function(_, body)
          if not body then
            handler.send_http_response(client, "404 Not Found", "text/plain", "404 Not Found")
            return
          end
          local etag = generate_etag(file_path)
          if if_none_match and if_none_match == etag then
            handler.send_http_response(
              client,
              "304 Not Modified",
              get_content_type(file_path) or "",
              "",
              { ["ETag"] = etag }
            )
            return
          end
          local filetype = supported_filetype(file_path)
          local content_type = get_content_type(file_path) or ""
          if filetype and accept and accept:match("text/html") then
            -- 重寫後再轉 HTML，確保 `img/...` 等 vault 相對路徑解析為 `/img/...`
            if filetype == "markdown" or filetype == "asciidoc" or filetype == "html" then
              body = rewrite_content(body, file_path, active.webroot, active.has_vault)
            end
            body = filetype ~= "html" and toHTML(body, filetype) or handle_body(body)
            content_type = "text/html; charset=UTF-8"
          end
          handler.send_http_response(client, "200 OK", content_type, body, { ["ETag"] = etag })
        end)
      end
    end

    local function check_port(port, utils)
      for _, process in ipairs(utils.processes_listening_on_port(port)) do
        if process.pid ~= vim.uv.os_getpid() then
          vim.notify(
            ("Port %d is being used by another process `%s` (PID %d). Run `:lua vim.uv.kill(%d)` to kill it or change the port with `:lua LivePreview.config.port = <new_port>`"):format(
              port,
              process.name,
              process.pid,
              process.pid
            ),
            vim.log.levels.WARN
          )
        end
      end
    end

    -- 複用上游 lp.start 邏輯，但允許指定 webroot
    -- 上游 Server:new(nil) 固定用 cwd 作 root，會讓 `../` 圖片逃出 root 而 404
    local function start_with_webroot(filepath, port, webroot, has_vault)
      local lp = require("livepreview")
      local Config = require("livepreview.config").config
      local server = require("livepreview.server")
      local utils = require("livepreview.utils")

      active.filepath, active.webroot, active.has_vault = filepath, webroot, has_vault or false
      active.tmp_clin_file = is_tmp_clin_file(filepath) and filepath or nil
      ensure_serve_intercept()
      check_port(port, utils)
      lp.close()

      lp.serverObj = server.Server:new(webroot)
      local function onTextChanged(client)
        local bufname = vim.api.nvim_buf_get_name(0)
        if not utils.supported_filetype(bufname) or utils.supported_filetype(bufname) == "html" then
          return
        end
        -- 即時預覽同樣重寫，才不會讓 `../../../../` 意外渲染
        local cur =
          rewrite_content(table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n"), filepath, webroot, has_vault)
        server.websocket.send_json(client, { filepath = bufname, type = "update", content = cur })
      end

      lp.serverObj:start(Config.address, port, {
        on_events = utils.supported_filetype(filepath) == "html" and {
          LivePreviewDirChanged = function(client, data)
            if not vim.regex([[\.\(html\|css\|js\)$]]):match_str(data.filename) then
              return
            end
            server.websocket.send_json(client, { type = "reload" })
          end,
        } or {
          TextChanged = vim.schedule_wrap(onTextChanged),
          TextChangedI = vim.schedule_wrap(onTextChanged),
        },
      })
      return true
    end

    -- 非 d2 的 start 流程：解析路徑 → vault root 作 webroot → 開瀏覽器
    local function start_live_preview(filepath, Config, utils)
      filepath = vim.fs.normalize(filepath)
      stop_d2() -- 避免 5500 埠被 d2 佔用
      local webroot, urlpath, has_vault
      if Config.dynamic_root then
        webroot = vim.fs.dirname(filepath)
        urlpath = vim.fs.basename(filepath)
        has_vault = false
      else
        webroot, urlpath, has_vault = resolve_webroot_and_urlpath(filepath, utils)
      end
      if not start_with_webroot(filepath, Config.port, webroot, has_vault) then
        return
      end
      local url = ("http://%s:%d/%s"):format(Config.address, Config.port, vim.uri_encode(urlpath))
      print("live-preview.nvim: Opening browser at " .. url .. " (root: " .. webroot .. ")")
      utils.open_browser(url, Config.browser)
    end

    -- 解析 start 目標：顯式參數優先，否則當前 buffer（不支援則找其他支援的 buffer）
    local function resolve_target(filepath_arg, utils, api)
      local filepath = filepath_arg
      if filepath ~= nil then
        if not utils.is_absolute_path(filepath) then
          filepath = vim.fs.joinpath(vim.uv.cwd(), filepath)
        end
        return filepath
      end
      filepath = api.nvim_buf_get_name(0)
      if utils.supported_filetype(filepath) then
        return filepath
      end
      local found = utils.find_supported_buf()
      if not found then
        vim.notify("live-preview.nvim only supports markdown, asciidoc, svg and html files", vim.log.levels.ERROR)
        return nil
      end
      return found
    end

    -- 合併 D2 到原有 LivePreview 指令：d2 用原生 watch server，其他走 live-preview
    -- 需在插件建立 :LivePreview 後覆寫（headless 測試時可能尚未建立，用 pcall 容錯）
    pcall(vim.api.nvim_del_user_command, "LivePreview")
    vim.api.nvim_create_user_command("LivePreview", function(cmd_opts)
      local Config = require("livepreview.config").config
      local utils = require("livepreview.utils")
      local api = vim.api

      local subcommand = cmd_opts.fargs[1]

      if subcommand == "start" then
        local filepath = resolve_target(cmd_opts.fargs[2], utils, api)
        if not filepath then
          return
        end
        if filepath:match("%.d2$") ~= nil then
          filepath = vim.fs.normalize(filepath)
          local output = "/tmp/" .. vim.fs.basename(filepath):gsub("%.d2$", ".svg")
          if cmd_opts.fargs[3] ~= nil then
            output = cmd_opts.fargs[3]
          end
          if d2_job then
            stop_d2()
          end
          -- 固定 5500，與 live-preview 一致；顯式指定 terminal-browser
          d2_job = vim.fn.jobstart(
            { "d2", "--watch", "--port", "5500", "--browser", "terminal-browser", filepath, output },
            {
              on_exit = function(_, code)
                d2_job = nil
                if code ~= 0 then
                  vim.notify("d2 --watch 已退出 code: " .. code, vim.log.levels.INFO)
                end
              end,
            }
          )
          vim.notify("d2 --watch http://localhost:5500 " .. filepath .. " -> " .. output)
          return
        end
        start_live_preview(filepath, Config, utils)
      elseif subcommand == "close" then
        stop_d2()
        require("livepreview").close()
        print("Live preview stopped")
      elseif subcommand == "pick" then
        -- pick 後同樣以 vault root 作 webroot，避免 `../` 圖片 404
        local picker = require("livepreview.picker")
        local picker_funcs = {}
        for k, v in pairs(require("livepreview.config").pickers) do
          picker_funcs[v] = picker[k]
        end
        local function pick_callback(pick_value)
          if not pick_value then
            vim.notify("No file picked", vim.log.levels.INFO)
            return
          end
          local picked = pick_value
          if not utils.is_absolute_path(picked) then
            picked = vim.fs.joinpath(vim.uv.cwd(), picked)
          end
          vim.cmd.edit(picked)
          start_live_preview(picked, Config, utils)
        end
        if Config.picker and #Config.picker > 0 then
          if not picker_funcs[Config.picker] then
            vim.notify("live-preview.nvim: config option 'picker' invalid", vim.log.levels.ERROR)
            return
          end
          local status, err = pcall(picker_funcs[Config.picker], pick_callback)
          if not status then
            vim.notify("live-preview.nvim : error calling picker " .. Config.picker, vim.log.levels.ERROR)
            vim.notify(err, vim.log.levels.ERROR)
          end
        else
          picker.pick(pick_callback)
        end
      else
        require("livepreview").help()
      end
    end, {
      nargs = "*",
      complete = function(ArgLead, CmdLine, _)
        local subcommands = { "start", "close", "pick", "-h", "--help" }
        local subcommand = vim.split(CmdLine, " ")[2]
        if subcommand == "" then
          return subcommands
        elseif subcommand == ArgLead then
          return vim.tbl_filter(function(subcmd)
            return vim.startswith(subcmd, ArgLead)
          end, subcommands)
        elseif subcommand == "start" then
          return vim.fn.getcompletion(ArgLead, "file")
        end
      end,
    })

    -- 關閉瀏覽器/退出時同時終止 d2 watch
    vim.api.nvim_create_autocmd("VimLeavePre", {
      callback = stop_d2,
      desc = "Stop d2 --watch on exit",
    })
  end,
}

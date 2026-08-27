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

    -- 合併 D2 到原有 LivePreview 指令：d2 用原生 watch server，其他走 live-preview
    -- 需在插件建立 :LivePreview 後覆寫
    vim.api.nvim_del_user_command("LivePreview")
    vim.api.nvim_create_user_command("LivePreview", function(cmd_opts)
      local lp = require("livepreview")
      local Config = require("livepreview.config").config
      local utils = require("livepreview.utils")
      local api = vim.api

      local subcommand = cmd_opts.fargs[1]

      if subcommand == "start" then
        -- 判斷是否為 d2 檔案（顯式參數或當前 buffer）
        local filepath
        if cmd_opts.fargs[2] ~= nil then
          filepath = cmd_opts.fargs[2]
          if not utils.is_absolute_path(filepath) then
            filepath = vim.fs.joinpath(vim.uv.cwd(), filepath)
          end
        else
          filepath = api.nvim_buf_get_name(0)
        end
        local is_d2 = filepath:match("%.d2$") ~= nil

        if is_d2 then
          filepath = vim.fs.normalize(filepath)
          local output = "/tmp/" .. vim.fs.basename(filepath):gsub("%.d2$", ".svg")
          if cmd_opts.fargs[3] ~= nil then
            output = cmd_opts.fargs[3]
          end
          if d2_job then
            stop_d2()
          end
          -- 固定 5500，與 live-preview 一致；顯式指定 terminal-browser
          d2_job = vim.fn.jobstart({ "d2", "--watch", "--port", "5500", "--browser", "terminal-browser", filepath, output }, {
            on_exit = function(_, code)
              d2_job = nil
              if code ~= 0 then
                vim.notify("d2 --watch 已退出 code: " .. code, vim.log.levels.INFO)
              end
            end,
          })
          vim.notify("d2 --watch http://localhost:5500 " .. filepath .. " -> " .. output)
          return
        end

        -- 非 d2：走原有 live-preview 流程（複用 plugin/livepreview.lua 邏輯）
        if cmd_opts.fargs[2] ~= nil then
          filepath = cmd_opts.fargs[2]
          if not utils.is_absolute_path(filepath) then
            filepath = vim.fs.joinpath(vim.uv.cwd(), filepath)
          end
        else
          filepath = api.nvim_buf_get_name(0)
          if not utils.supported_filetype(filepath) then
            filepath = utils.find_supported_buf()
            if not filepath then
              vim.notify("live-preview.nvim only supports markdown, asciidoc, svg and html files", vim.log.levels.ERROR)
              return
            end
          end
        end
        filepath = vim.fs.normalize(filepath)
        stop_d2() -- 避免 5500 埠被 d2 佔用
        if not lp.start(filepath, Config.port) then
          return
        end
        local urlpath = Config.dynamic_root and vim.fs.basename(filepath)
          or utils.get_relative_path(filepath, vim.fs.normalize(vim.uv.cwd() or ""))
        local urlpath_encoded = urlpath and vim.uri_encode(urlpath)
        local url = ("http://%s:%d/%s"):format(Config.address, Config.port, urlpath_encoded)
        print("live-preview.nvim: Opening browser at " .. url)
        utils.open_browser(url, Config.browser)

      elseif subcommand == "close" then
        stop_d2()
        require("livepreview").close()
        print("Live preview stopped")
      elseif subcommand == "pick" then
        require("livepreview").pick()
      else
        require("livepreview").help()
      end
    end, {
      nargs = "*",
      complete = function(ArgLead, CmdLine, CursorPos)
        local subcommands = { "start", "close", "pick", "-h", "--help" }
        local subcommand = vim.split(CmdLine, " ")[2]
        if subcommand == "" then
          return subcommands
        elseif subcommand == ArgLead then
          return vim.tbl_filter(function(subcmd)
            return vim.startswith(subcmd, ArgLead)
          end, subcommands)
        else
          if subcommand == "start" then
            return vim.fn.getcompletion(ArgLead, "file")
          end
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

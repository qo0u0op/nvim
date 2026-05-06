return {
  -- add this to the file where you setup your other plugins:
  {
    "monkoose/neocodeium",
    -- event = "VeryLazy",
    lazy = true,
    cmd = "NeoCodeium",
    opts = {
      enabled = true,
      -- Path to a custom windsurf server binary (you can download one from:
      -- https://github.com/Exafunction/codeium/releases)
      bin = nil,
      -- When set to `true`, autosuggestions are disabled.
      -- Use `require'neodecodeium'.cycle_or_complete()` to show suggestions manually
      manual = false,
      -- Information about the API server to use
      server = {
        -- API URL to use (for Enterprise mode)
        api_url = nil,
        -- Portal URL to use (for registering a user and downloading the binary)
        portal_url = nil,
      },
      -- Set to `false` to disable showing the number of suggestions label in the line number column
      show_label = true,
      -- Set to `true` to enable suggestions debounce
      debounce = false,
      -- Maximum number of lines parsed from loaded buffers (current buffer always fully parsed)
      -- Set to `0` to disable parsing non-current buffers (may lower suggestion quality)
      -- Set it to `-1` to parse all lines
      max_lines = 10000,
      -- Set to `true` to disable some non-important messages, like "NeoCodeium: server started..."
      silent = false,
      -- Set to `false` to enable suggestions in special buftypes, like `nofile` etc.
      disable_in_special_buftypes = true,
      -- Sets default log level. One of "trace", "debug", "info", "warn", "error"
      log_level = "warn",
      -- Set `enabled` to `true` to enable single line mode.
      -- In this mode, multi-line suggestions would collapse into a single line and only
      -- shows full lines when on the end of the suggested (accepted) line.
      -- So it is less distracting and works better with other completion plugins.
      single_line = {
        enabled = false,
        label = "...", -- Label indicating that there is multi-line suggestion.
      },
      -- Set to a function that returns `true` if a buffer should be enabled
      -- and `false` if the buffer should be disabled
      -- You can still enable disabled by this option buffer with `:NeoCodeium enable_buffer`
      filter = function(bufnr)
        -- List of patterns to ignore.
        -- We use string.find, which supports basic pattern matching.
        -- Setting ignore sicret files to disable codeium.
        local ignore_patterns = {
          "/home/d0w0b/.ssh/",
          "/home/d0w0b/.config/ssh/",
          "/home/d0w0b/.local/share/gnupg/",
          "/home/d0w0b/.local/share/kwalletd/",
          "env.fish$", -- The '$' anchors the match to the end of the string.
        }

        local buf_name = vim.api.nvim_buf_get_name(bufnr)
        if buf_name == "" then
          return true
        end

        -- Get the full, absolute path of the buffer.
        local full_path = vim.fn.fnamemodify(buf_name, ":p")

        for _, pattern in ipairs(ignore_patterns) do
          if string.find(full_path, pattern) then
            -- Uncomment the next line for debugging to see which files are being ignored.
            -- vim.notify("NeoCodeium disabled for: " .. full_path, vim.log.levels.WARN)
            return false -- Disable Codeium if a pattern matches.
          end
        end

        return true -- Enable Codeium for all other files.
      end,
      -- Set to `false` to disable suggestions in buffers with specific filetypes
      -- You can still enable disabled by this option buffer with `:NeoCodeium enable_buffer`
      filetypes = {
        help = false,
        gitcommit = false,
        gitrebase = false,
        ["."] = false,
      },
      -- List of directories and files to detect workspace root directory for Windsurf Chat
      root_dir = { ".bzr", ".git", ".hg", ".svn", "_FOSSIL_", "package.json", "mise.toml" },
    },
    config = function(_, opts)
      require("neocodeium").setup(opts)
      vim.api.nvim_set_hl(0, "NeoCodeiumSuggestion", { fg = "#627C62" })
      vim.api.nvim_set_hl(0, "NeoCodeiumLabel", { link = "DiagnosticInfo", reverse = true })
      vim.api.nvim_set_hl(0, "NeoCodeiumSingleLineLabel", { fg = "#808080", bold = true })
    end,
    keys = {
      -- 控制按鍵
      {
        "<leader>aa",
        function()
          require("neocodeium") -- 觸發加載
          vim.notify("NeoCodeium activated!", vim.log.levels.INFO)
        end,
        mode = "n",
        desc = "Start NeoCodeium",
      },
      {
        "<leader>ac",
        function()
          vim.cmd("NeoCodeium toggle")
          vim.notify("NeoCodeium toggled!", vim.log.levels.INFO)
        end,
        mode = "n",
        desc = "Toggle AI coding",
      },
      {
        "<A-f>",
        function()
          require("neocodeium").accept()
        end,
        mode = "i",
        desc = "Accept suggestion",
      },
      {
        "<A-w>",
        function()
          require("neocodeium").accept_word()
        end,
        mode = "i",
        desc = "Accept word",
      },
      {
        "<A-q>",
        function()
          require("neocodeium").accept_line()
        end,
        mode = "i",
        desc = "Accept line",
      },
      {
        "<A-r>",
        function()
          require("neocodeium").cycle_or_complete()
        end,
        mode = "i",
        desc = "Cycle or complete",
      },
      {
        "<A-x>",
        function()
          require("neocodeium").clear()
        end,
        mode = "i",
        desc = "Clear suggestion",
      },
    },
  },
}

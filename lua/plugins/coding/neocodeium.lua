-- 筆電軌：Windsurf（前 Codeium）免費層，Tab autocomplete 無限。
-- 只在這台機器是需要雲端補全的筆電時載入；桌機走 minuet.lua。
local ai = require("config.ai")
local started = false

return {
  {
    "monkoose/neocodeium",
    cond = function()
      return ai.provider() == "neocodeium"
    end,
    lazy = true,
    cmd = "NeoCodeium",
    keys = {
      {
        "<leader>aa",
        function()
          if not started then
            started = true
            vim.notify("NeoCodeium: started", vim.log.levels.INFO)
            return
          end

          -- bang = true：停止補全「而且」殺掉 Windsurf language server
          -- （false 只會停請求，server 仍在背景跑）
          local enabled = require("neocodeium.options").options.enabled
          require("neocodeium.commands").toggle(true)
          vim.notify(
            enabled and "NeoCodeium: stopped (server killed)" or "NeoCodeium: started",
            vim.log.levels.INFO
          )
        end,
        mode = "n",
        desc = "Toggle AI completion",
      },
      -- 與 minuet 同一組鍵，兩台機器肌肉記憶一致
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
        "<A-l>",
        function()
          require("neocodeium").cycle_or_complete()
        end,
        mode = "i",
        desc = "Next suggestion / request",
      },
      {
        "<A-h>",
        function()
          require("neocodeium").cycle(-1)
        end,
        mode = "i",
        desc = "Prev suggestion",
      },
      {
        "<A-x>",
        function()
          require("neocodeium").clear()
        end,
        mode = "i",
        desc = "Dismiss suggestion",
      },
    },
    opts = {
      -- 在行號欄顯示建議數量
      show_label = true,
      -- 筆電外出時減少上傳量與請求頻率
      max_lines = 4000,
      debounce = true,
      filetypes = {
        help = false,
        gitcommit = false,
        gitrebase = false,
        ["."] = false,
      },
      -- 就算專案是公開的 AGPL，這些路徑也不該送出去
      filter = function(bufnr)
        local ignore_patterns = {
          "/%.ssh/",
          "/%.config/ssh/",
          "/gnupg/",
          "/kwalletd/",
          "env%.fish$",
          "/%.env$",
          "/%.env%.",
          "/secrets/",
          "/%.secrets/",
          "%.pem$",
          "%.key$",
          "%.p12$",
          "%.pfx$",
          "/%.aws/",
          "/%.config/gh/",
          "/%.docker/config%.json$",
          "/id_rsa",
          "/id_ed25519",
          "/credentials",
          "/%.npmrc$",
          "/%.pypirc$",
          "/%.git%-credentials$",
          "/%.netrc$",
        }

        local buf_name = vim.api.nvim_buf_get_name(bufnr)
        if buf_name == "" then
          return true
        end

        local full_path = vim.fn.fnamemodify(buf_name, ":p")
        for _, pattern in ipairs(ignore_patterns) do
          if string.find(full_path, pattern) then
            return false
          end
        end
        return true
      end,
      root_dir = { ".bzr", ".git", ".hg", ".svn", "_FOSSIL_", "package.json", "mise.toml" },
    },
    config = function(_, opts)
      require("neocodeium").setup(opts)
      -- 與 minuet 的 ghost text 同色
      vim.api.nvim_set_hl(0, "NeoCodeiumSuggestion", { fg = "#627C62" })
      vim.api.nvim_set_hl(0, "NeoCodeiumLabel", { link = "DiagnosticInfo", reverse = true })
      vim.api.nvim_set_hl(0, "NeoCodeiumSingleLineLabel", { fg = "#808080", bold = true })

      -- plugin 自己沒有離開清理；這裡明確殺掉 language server，
      -- 避免 nvim 關掉後行程還留著（那是唯一會持續連外的東西）。
      vim.api.nvim_create_autocmd("VimLeavePre", {
        group = vim.api.nvim_create_augroup("neocodeium_cleanup", { clear = true }),
        callback = function()
          local ok, server = pcall(require, "neocodeium.server")
          if ok and server.pid then
            server:stop()
          end
        end,
      })
    end,
  },
}

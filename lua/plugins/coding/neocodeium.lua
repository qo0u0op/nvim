-- 筆電軌：Windsurf（前 Codeium）免費層，Tab autocomplete 無限。
-- 只在這台機器是需要雲端補全的筆電時載入；桌機走 minuet.lua。
local ai = require("config.ai")

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
          require("neocodeium") -- 觸發 lazy 載入，config 會啟動 windsurf server
          vim.notify("NeoCodeium: started", vim.log.levels.INFO)
        end,
        mode = "n",
        desc = "Start AI completion",
      },
      {
        "<leader>ac",
        function()
          vim.cmd("NeoCodeium toggle")
          vim.notify("NeoCodeium: toggled", vim.log.levels.INFO)
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
          require("neocodeium").cycle(1)
        end,
        mode = "i",
        desc = "Next suggestion",
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
        "<A-r>",
        function()
          require("neocodeium").cycle_or_complete()
        end,
        mode = "i",
        desc = "Cycle or request suggestion",
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
      filetypes = {
        help = false,
        gitcommit = false,
        gitrebase = false,
        ["."] = false,
      },
      -- 就算專案是公開的 AGPL，這些路徑也不該送出去
      filter = function(bufnr)
        local ignore_patterns = {
          "/.ssh/",
          "/gnupg/",
          "/kwalletd/",
          "env%.fish$",
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
    end,
  },
}

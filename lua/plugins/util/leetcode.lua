return {
  {
    "kawre/leetcode.nvim",
    -- lazy = false,
    dependencies = {
      -- include a picker of your choice, see picker section for more details
      "nvim-lua/plenary.nvim",
      "MunifTanjim/nui.nvim",
    },
    opts = {
      -- configuration goes here
      -- arg = "lt",
      lang = "java",
      cn = { -- leetcode.cn
        enabled = true,
        translator = true,
        translate_problems = true,
      },
      storage = {
        home = "~/Documents/Workspace/leetcode",
        cache = vim.fn.stdpath("cache") .. "/leetcode",
      },
    },
    keys = {
      { "<leader>ktT", "<cmd>Leet<cr>", desc = "LeetCode Menu" },
    },
    config = function(_, opts)
      require("leetcode").setup(opts)
      -- 使用路徑匹配：當開啟路徑在 ~/leetcode/ 下的任何檔案時觸發
      vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile" }, {
        -- 這裡使用 opts.storage.home 定義的路徑加上通配符
        pattern = vim.fn.expand(opts.storage.home) .. "/*",
        callback = function()
          local wk = require("which-key")
          -- 設定僅限於該 Buffer 的快捷鍵
          wk.add({
            { "<leader>kt", group = "LeetCode", buffer = true },
            { "<leader>ktt", "<cmd>Leet test<cr>", desc = "LeetCode Test", buffer = true },
            { "<leader>kts", "<cmd>Leet submit<cr>", desc = "LeetCode Submit", buffer = true },
            { "<leader>kti", "<cmd>Leet info<cr>", desc = "LeetCode Info", buffer = true },
            { "<leader>ktc", "<cmd>Leet console<cr>", desc = "LeetCode Console", buffer = true },
            { "<leader>ktd", "<cmd>Leet desc<cr>", desc = "Toggle Description", buffer = true },
          })
        end,
      })
    end,
  },
}

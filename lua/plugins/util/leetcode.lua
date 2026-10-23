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
      -- LeetCode's judge endpoints reject curl's HTTP/2 fingerprint via
      -- Cloudflare. Force HTTP/1.1 for leetcode requests only.
      if not vim.g.leetcode_http1_patch then
        vim.g.leetcode_http1_patch = true
        local curl = require("plenary.curl")
        for _, method in ipairs({ "get", "post", "put" }) do
          local original = curl[method]
          curl[method] = function(url, options)
            if type(url) == "string" and url:match("^https://leetcode%.") then
              options = options or {}
              if type(options.raw) ~= "table" then
                options.raw = {}
              end
              table.insert(options.raw, "--http1.1")
            end
            return original(url, options)
          end
        end
      end

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

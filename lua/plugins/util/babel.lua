-- ~/.config/nvim/lua/plugins/babel.lua
return {
  "acidsugarx/babel.nvim",
  version = "*",
  opts = {
    source = "en", -- 自動偵測來源語言
    target = "zh-TW", -- 目標語言（zh = 中文）
    provider = "google", -- 翻譯提供者："google" 或 "deepl"
    languages = {
      auto = "Auto-detect",
      en = "English",
      ["zh-TW"] = "Chinese (Traditional)",
      zh = "Chinese (Simplified)",
      -- 其他你需要的語言...
    },

    network = {
      connect_timeout = 5,
      request_timeout = 15,
    },

    cache = {
      enabled = true,
      limit = 200,
    },

    history = {
      enabled = true,
      limit = 50,
    },

    display = "float", -- "float" 或 "picker"
    picker = "auto", -- 自動偵測：telescope / fzf / snacks / mini

    float = {
      border = "rounded",
      mode = "cursor", -- "center" 或 "cursor"
      max_width = 80,
      max_height = 20,
      enter = true,
      auto_close = false,
    },

    keymaps = {
      translate = "gt",
      translate_word = "<leader>klw",
      lang = "<leader>kll",
      swap = "<leader>kls",
      history = "<leader>klh",
    },
  },
}

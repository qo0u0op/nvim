return {
  "uga-rosa/ccc.nvim",
  cmd = { "CccPick", "CccConvert", "CccHighlighterToggle" },
  opts = {
    highlighter = {
      auto_enable = true,
      lsp = true,
    },
  },
  keys = {
    { "<leader>kc", "<cmd>CccPick<cr>", desc = "Color Picker" },
    { "<leader>ut", "<cmd>CccHighlighterToggle<cr>", desc = "Toggle Color Highlight" },
  },
}

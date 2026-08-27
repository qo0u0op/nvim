return {
  "chomosuke/typst-preview.nvim",
  ft = "typst",
  version = "1.*",
  keys = {
    { "<leader>kpt", "<cmd>TypstPreviewToggle<cr>", desc = "Typst Preview" },
  },
  opts = {
    open_cmd = "terminal-browser open %s --split right --size 0.5",
  },
}

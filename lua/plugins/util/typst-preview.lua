return {
  "chomosuke/typst-preview.nvim",
  ft = "typst",
  version = "1.*",
  keys = {
    { "<leader>kpt", "<cmd>TypstPreviewToggle<cr>", desc = "Typst Preview" },
  },
  opts = {}, -- lazy.nvim will implicitly calls `setup {}`
}

return {
  "brianhuster/live-preview.nvim",
  dependencies = {
    -- You can choose one of the following pickers
    "nvim-telescope/telescope.nvim",
    "ibhagwan/fzf-lua",
    "nvim-mini/mini.pick",
    "folke/snacks.nvim",
  },
  ft = { "markdown", "svg", "html", "css", "javascript" },
  keys = {
    { "<leader>kpl", "<cmd>LivePreview start<cr>", desc = "Start LivePreview" },
    { "<leader>kpc", "<cmd>LivePreview close<cr>", desc = "Close LivePreview" },
  },
  opts = {
    browser = "chromium",
  },
}

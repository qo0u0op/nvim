return {
  "jkeresman01/spring-initializr.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "MunifTanjim/nui.nvim",
    "nvim-telescope/telescope.nvim",
  },
  cmd = { "SpringInitializr", "SpringGenerateProject" },
  keys = {
    { "<leader>rss", "<CMD>SpringInitializr<CR>", desc = "Initializr" },
    { "<leader>rsg", "<CMD>SpringGenerateProject<CR>", desc = "Generate Project" },
  },
  config = function()
    require("spring-initializr").setup()
  end,
}

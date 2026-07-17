return {
  "nvim-treesitter/nvim-treesitter",
  opts = {
    ensure_installed = {
      "kitty",
    },
    parsers = {
      kitty = {
        install_info = {
          url = "https://github.com/OXY2DEV/tree-sitter-kitty",
          files = { "src/parser.c" },
          branch = "main",
        },
      },
    },
  },
  config = function(_, opts)
    require("nvim-treesitter").setup(opts)
    vim.treesitter.language.register("kitty", "kitty")
  end,
}

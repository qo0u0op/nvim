-- local is_ssh = vim.env.SSH_TTY ~= nil or vim.env.SSH_CONNECTION ~= nil

return {
  -- add colorscheme:
  {
    "catppuccin/nvim",
    name = "catppuccin",
    priority = 1000,
  },
  {
    "LazyVim/LazyVim",
    opts = {
      -- colorscheme = is_ssh and "catppuccin-latte" or "catppuccin-mocha",
      colorscheme = "catppuccin-mocha",
    },
  },
}

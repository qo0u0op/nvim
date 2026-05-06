-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here
vim.opt.wrap = true
vim.opt.colorcolumn = { "80", "120" }

-- Root directory detection
vim.g.root_spec = { "lsp", { ".git", "lua", "pom.xml", "mise.toml" }, "cwd" }

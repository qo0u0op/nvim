-- bootstrap lazy.nvim, LazyVim and your plugins
require("config.lazy")
local in_wsl = vim.fn.has("wsl") == 1

if in_wsl then
  vim.g.clipboard = {
    name = "win32yank-wsl",
    copy = {
      ["+"] = "win32yank.exe -i --crlf",
      ["*"] = "win32yank.exe -i --crlf",
    },
    paste = {
      ["+"] = "win32yank.exe -o --lf",
      ["*"] = "win32yank.exe -o --lf",
    },
    cache_enabled = 0,
  }
end

vim.opt.spell = true
vim.opt.spelloptions = "camel"
vim.opt.spelllang = { "en", "cjk" } -- 英文拼字 + 不標記中文錯誤

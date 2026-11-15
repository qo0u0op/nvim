-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

local map = vim.keymap.set

-- Helper to safely unmap or disable
local function disable(mode, lhs)
  pcall(vim.keymap.del, mode, lhs) -- try to disable
  map(mode, lhs, "<nop>", { desc = "Disabled" }) -- disable
end

-- Disable conflicting keymaps
disable("n", "<leader>cd")
disable("n", "<C-w>d")
disable("n", "<C-w><C-d>")
disable("n", "<leader>e")
disable("n", "<leader>E")
disable("n", "<leader>-")
disable("n", "<leader>|")
disable("n", "<leader>`")
disable("n", "<leader>D")
disable("n", "<leader>L")

-- Restore / Redefine window management
map("n", "<C-w>d", "<C-w>c", { desc = "Delete window" })
map("n", "<leader>wd", "<C-w>c", { desc = "Delete window" })
map("n", "<leader>w<", "<C-w><", { desc = "Decrease width" })

-- Map diagnostics to <leader>x
map("n", "<leader>xd", function()
  vim.diagnostic.open_float()
end, { desc = "Line Diagnostics" })

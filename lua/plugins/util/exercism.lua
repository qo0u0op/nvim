-- exercism 的 Java/Kotlin track 都用 Gradle，但 CLI 的 test 會跑 ./gradlew；
-- 這裡改成在專案根目錄直接跑 PATH 上的 gradle（mise），避免下載 wrapper
local function test_exercise()
  local root = vim.fs.root(0, { "build.gradle", "build.gradle.kts" })
  if not root then
    -- 其他語言沒有 Gradle，交回 CLI 原本的 runner
    vim.cmd("Exercism test")
    return
  end

  local cmd = ("cd %s && gradle test --console=plain"):format(vim.fn.shellescape(root))
  if vim.fn.exists(":STerm") == 2 then
    vim.cmd("STerm " .. cmd)
  else
    vim.cmd("terminal " .. cmd)
  end
end

return {
  "2kabhishek/exercism.nvim",
  cmd = { "Exercism" },
  dependencies = {
    "2kabhishek/utils.nvim",
    "2kabhishek/termim.nvim", -- 選用，提供 :STerm 跑測試
    "nvim-lua/plenary.nvim",
  },
  opts = {
    exercism_workspace = "/home/d0w0b/Documents/Workspace/exercism",
    default_language = "java",
    -- 關掉外掛預設的 <leader>ex*，改用 <leader>ke* 前綴
    add_default_keybindings = false,
  },
  keys = {
    { "<leader>kea", "<cmd>Exercism languages<cr>", desc = "Exercism Languages" },
    { "<leader>kel", "<cmd>Exercism list<cr>", desc = "Exercism List" },
    { "<leader>ker", "<cmd>Exercism recents<cr>", desc = "Exercism Recents" },
    { "<leader>ket", test_exercise, desc = "Exercism Test (gradle)" },
    { "<leader>kes", "<cmd>Exercism submit<cr>", desc = "Exercism Submit" },
  },
}

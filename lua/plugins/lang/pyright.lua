return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        pyright = {
          settings = {
            python = {
              -- 動態設定 pythonPath
              pythonPath = (function()
                -- 執行 `mise which python` 來取得當前 mise 環境的 python 路徑
                local mise_python = vim.fn.trim(vim.fn.system("mise which python"))
                -- vim.v.shell_error 會在最後一個 shell 命令失敗時設定為非零值
                if vim.v.shell_error == 0 then
                  return mise_python
                end
                -- 如果命令失敗，返回 nil，讓 pyright 使用預設的 python
                return nil
              end)(),
            },
          },
        },
      },
    },
  },
}

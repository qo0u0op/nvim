return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        vtsls = {
          -- TypeScript track 用 Yarn PnP；JavaScript track 用 pnpm（沒有 PnP）。
          -- 只有偵測到 .yarn/sdks 時才指定 tsdk，否則 vtsls 會對 JS 練習噴
          -- "doesn't point to a valid tsserver install" 警告。
          -- 注意：vtsls 必須搭配 vtsls.autoUseWorkspaceTsdk = true（LazyVim 預設）。
          before_init = function(_, config)
            config.settings = config.settings or {}
            config.settings.typescript = config.settings.typescript or {}
            local tsdk = config.root_dir and (config.root_dir .. "/.yarn/sdks/typescript/lib")
            local tsserver = tsdk and (tsdk .. "/tsserver.js")
            if tsserver and vim.uv.fs_stat(tsserver) then
              config.settings.typescript.tsdk = ".yarn/sdks/typescript/lib"
            else
              config.settings.typescript.tsdk = nil
            end
          end,
        },
        eslint = {
          settings = {
            -- Yarn PnP 專案：讓 vscode-eslint 從 SDK wrapper 解析 eslint。
            -- 非 PnP 專案（JS track）路徑不存在時會 fallback 到 node_modules。
            nodePath = ".yarn/sdks",
          },
        },
      },
    },
  },
}

return {
  {
    "saghen/blink.cmp",
    opts = {
      keymap = {
        preset = "none",
        ["<C-CR>"] = { "show", "show_documentation", "hide_documentation" },
        -- ['<ESC>'] = { 'hide', 'fallback' },
        ["<CR>"] = { "accept", "fallback" },

        ["<Tab>"] = { "select_next", "snippet_forward", "fallback" },
        ["<S-Tab>"] = { "select_prev", "snippet_backward", "fallback" },

        ["<Up>"] = { "select_prev", "fallback" },
        ["<Down>"] = { "select_next", "fallback" },
        ["<Left>"] = { "snippet_backward", "fallback" },
        ["<Right>"] = { "snippet_forward", "fallback" },

        ["<C-b>"] = { "scroll_documentation_up", "fallback" },
        ["<C-f>"] = { "scroll_documentation_down", "fallback" },

        ["<C-k>"] = { "show_signature", "hide_signature", "fallback" },

        -- Manual AI completion (does not auto-trigger). Backend 由 config.ai 決定。
        ["<A-y>"] = {
          function(cmp)
            if require("config.ai").provider() == "neocodeium" then
              local ok, neocodeium = pcall(require, "neocodeium")
              if not ok then
                vim.notify("NeoCodeium is not ready; press <leader>aa first", vim.log.levels.WARN)
                return
              end
              neocodeium.cycle_or_complete()
              return
            end

            local ok, minuet = pcall(require, "minuet")
            if not (ok and minuet.config) then
              vim.notify("Minuet is not ready; press <leader>aa first", vim.log.levels.WARN)
              return
            end
            minuet.make_blink_map()[1](cmp)
          end,
        },
      },
      completion = {
        trigger = { prefetch_on_insert = false },
        keyword = {
          -- 'prefix' will fuzzy match on the text before the cursor
          -- 'full' will fuzzy match on the text before _and_ after the cursor
          -- example: 'foo_|_bar' will match 'foo_' for 'prefix' and 'foo__bar' for 'full'
          range = "full",
        },
        list = {
          selection = {
            -- When `true`, will automatically select the first item in the completion list
            preselect = false,
            -- preselect = function(ctx) return vim.bo.filetype ~= 'markdown' end,

            -- When `true`, inserts the completion item automatically when selecting it
            -- You may want to bind a key to the `cancel` command (default <C-e>) when using this option,
            -- which will both undo the selection and hide the completion menu
            auto_insert = true,
            -- auto_insert = function(ctx) return vim.bo.filetype ~= 'markdown' end
          },
        },
      },
      sources = {
        -- `lsp`, `buffer`, `snippets`, `path` and `omni` are built-in
        -- so you don't need to define them in `sources.providers`
        default = { "lsp", "buffer", "snippets", "path" },
        -- providers = {
        --   lsp = { score_offset = 3 },
        --   buffer = { score_offset = 2 },
        --   snippets = { score_offset = 1 },
        --   path = { score_offset = 0 },
        -- Manual only; not in `default` to avoid double requests.
        providers = {
          minuet = {
            name = "minuet",
            module = "minuet.blink",
            async = true,
            timeout_ms = 2000,
            score_offset = 50,
          },
        },
      },
    },
  },
}

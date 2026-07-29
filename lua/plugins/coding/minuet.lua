return {
  {
    "milanglacier/minuet-ai.nvim",
    lazy = true,
    cmd = "Minuet",
    keys = {
      { "<leader>al", "<cmd>Minuet virtualtext toggle<cr>", desc = "Llama toggle" },
    },
    opts = {
      provider = "openai_fim_compatible",
      virtualtext = {
        auto_trigger_ft = { "*" },
        keymap = {
          accept = "<A-f>",
          accept_line = "<A-q>",
          accept_n_lines = "<A-w>",
          next = "<A-r>",
          prev = "<A-e>",
          dismiss = "<A-x>",
        },
      },
      n_completions = 1,
      context_window = 4096,
      debounce = 400,
      throttle = 1000,
      request_timeout = 5,
      notify = "warn",
      provider_options = {
        openai_fim_compatible = {
          api_key = "TERM",
          name = "llamastash",
          end_point = "http://127.0.0.1:11435/v1/completions",
          model = "qwen2.5-coder-3b",
          optional = {
            max_tokens = 256,
            top_p = 0.9,
          },
          template = {
            prompt = function(context_before_cursor, context_after_cursor, _)
              return "<|fim_prefix|>"
                .. context_before_cursor
                .. "<|fim_suffix|>"
                .. context_after_cursor
                .. "<|fim_middle|>"
            end,
            suffix = false,
          },
        },
      },
    },
    config = function(_, opts)
      require("minuet").setup(opts)
      vim.api.nvim_set_hl(0, "MinuetVirtualText", { fg = "#627C62" })

      vim.defer_fn(function()
        vim.fn.jobstart({ "llamastash", "start", "qwen2.5-coder-3b" }, {
          stdout = false,
          stderr = false,
        })
      end, 1000)

      vim.api.nvim_create_autocmd("VimLeavePre", {
        group = vim.api.nvim_create_augroup("minuet_cleanup", { clear = true }),
        callback = function()
          vim.fn.jobstart({ "llamastash", "stop", "qwen2.5-coder-3b" }, { detach = true })
        end,
      })
    end,
  },
}

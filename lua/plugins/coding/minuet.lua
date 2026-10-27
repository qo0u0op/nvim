-- 桌機軌：llamastash + 本機 llama.cpp，完全離線。
-- 筆電不載入這個 spec（筆電走 neocodeium.lua），由 config.ai 判斷。
local ai = require("config.ai")

-- Fork includes accept_word (ported from PR #87).
local model = "qwen2.5-coder-3b"
local started_here = false
local starting = false
local ghost_on = false

local function local_ready()
  local out = vim.fn.system({ "llamastash", "status" })
  return out:find("qwen2%.5%-coder%-3b") ~= nil and out:find("ready") ~= nil
end

local function enable_ghost()
  vim.cmd("Minuet virtualtext enable")
  ghost_on = true
  vim.notify("Minuet: local model ready", vim.log.levels.INFO)
end

local function start_ghost()
  if vim.fn.executable("llamastash") == 0 then
    vim.notify("Minuet: llamastash not found", vim.log.levels.ERROR)
    return
  end

  if starting then
    vim.notify("Minuet: local model is loading", vim.log.levels.INFO)
    return
  end

  if local_ready() then
    enable_ghost()
    return
  end

  starting = true
  started_here = true
  vim.fn.jobstart({
    "llamastash",
    "start",
    model,
    "--wait",
    "--flash-attn",
    "on",
    "--cache-type-k",
    "q8_0",
    "--cache-type-v",
    "q8_0",
    "--n-gpu-layers",
    "99",
  }, {
    stdout = false,
    stderr = false,
    on_exit = function(_, code)
      starting = false
      if code == 0 or local_ready() then
        enable_ghost()
      else
        vim.notify("Minuet: local model failed to start", vim.log.levels.ERROR)
      end
    end,
  })
end

local function toggle_ghost()
  if ghost_on then
    vim.cmd("Minuet virtualtext disable")
    ghost_on = false
    vim.notify("Minuet: ghost off", vim.log.levels.INFO)
  else
    start_ghost()
  end
end

return {
  {
    "qo0u0op/minuet-ai.nvim",
    cond = function()
      return ai.provider() == "minuet"
    end,
    lazy = true,
    cmd = "Minuet",
    keys = {
      { "<leader>aa", toggle_ghost, desc = "Toggle Minuet" },
    },
    opts = {
      provider = "openai_fim_compatible",
      virtualtext = {
        auto_trigger_ft = { "*" },
        keymap = {
          accept = "<A-f>",
          accept_word = "<A-w>",
          accept_line = "<A-q>",
          next = "<A-l>",
          prev = "<A-h>",
          dismiss = "<A-x>",
        },
      },
      n_completions = 1,
      context_window = 4096,
      -- Wait 1s after the last keystroke; cap the request at 1s so the
      -- ghost appears at most ~2s after the user stops typing.
      debounce = 1000,
      throttle = 1000,
      request_timeout = 1,
      notify = "warn",
      provider_options = {
        openai_fim_compatible = {
          api_key = "TERM",
          name = "llamastash",
          end_point = "http://127.0.0.1:11435/v1/completions",
          model = model,
          optional = {
            max_tokens = 64,
            temperature = 0.2,
            top_p = 0.9,
            stop = { "<|endoftext|>", "\n\n" },
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

      -- Manual mode: no ghost until <leader>aa starts the local model.
      vim.cmd("Minuet virtualtext disable")
      ghost_on = false

      vim.api.nvim_create_autocmd("VimLeavePre", {
        group = vim.api.nvim_create_augroup("minuet_cleanup", { clear = true }),
        callback = function()
          if started_here then
            vim.fn.jobstart({ "llamastash", "stop", model }, { detach = true })
          end
        end,
      })
    end,
  },
}

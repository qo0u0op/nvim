-- 桌機使用 llama.vim + llamastash 本機 FIM。
local ai = require("config.ai")

local model = "qwen2.5-coder-3b"
local model_ready = false
local model_starting = false
local started_here = false
local enabled = false

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO)
end

local function set_endpoint(port)
  local config = vim.g.llama_config or {}
  config.endpoint_fim = ("http://127.0.0.1:%d/infill"):format(port)
  config.endpoint_inst = ("http://127.0.0.1:%d/v1/chat/completions"):format(port)
  -- vim.g 的 nested table 修改不會自動寫回，必須整份重新賦值
  vim.g.llama_config = config
end

---@return integer?
local function find_ready_model()
  if vim.fn.executable("llamastash") == 0 then
    return nil
  end

  local ok, result = pcall(function()
    return vim.system({ "llamastash", "status", "--json", "--no-spawn" }, { text = true }):wait()
  end)
  if not ok or not result or result.code ~= 0 then
    return nil
  end

  local decoded_ok, decoded = pcall(vim.json.decode, result.stdout or "")
  if not decoded_ok or not decoded or not decoded.models then
    return nil
  end

  for _, item in ipairs(decoded.models) do
    local path = item.model_path or (item.id and item.id.path) or ""
    if item.state == "ready" and path:find("qwen2%.5%-coder%-3b") then
      return item.port
    end
  end
end

local function start_model(cb)
  if vim.fn.executable("llamastash") == 0 then
    notify("llama.vim: llamastash not found", vim.log.levels.ERROR)
    cb(false)
    return
  end

  model_starting = true
  started_here = true

  vim.system({
    "llamastash",
    "start",
    model,
    "--wait",
    "--json",
    "--flash-attn",
    "on",
    "--cache-type-k",
    "q8_0",
    "--cache-type-v",
    "q8_0",
    "--n-gpu-layers",
    "99",
  }, { text = true }, function(result)
    vim.schedule(function()
      model_starting = false

      if result.code ~= 0 then
        local existing = find_ready_model()
        if existing then
          started_here = false
          model_ready = true
          set_endpoint(existing)
          cb(true)
          return
        end

        started_here = false
        notify("llama.vim: failed to start model\n" .. (result.stderr or ""), vim.log.levels.ERROR)
        cb(false)
        return
      end

      local decoded_ok, decoded = pcall(vim.json.decode, result.stdout or "")
      local port = decoded_ok and decoded and decoded.port
      if not port then
        started_here = false
        notify("llama.vim: could not read model port", vim.log.levels.ERROR)
        cb(false)
        return
      end

      model_ready = true
      set_endpoint(port)
      cb(true)
    end)
  end)
end

local function enable_llama()
  local ok, err = pcall(vim.fn["llama#enable"])
  if not ok then
    notify("llama.vim: " .. tostring(err), vim.log.levels.ERROR)
    return
  end
  enabled = true
  notify(("llama.vim: on (port %s)"):format(vim.g.llama_config.endpoint_fim:match(":(%d+)/")))
end

local function ensure_model(cb)
  if model_ready then
    cb(true)
    return
  end

  local existing = find_ready_model()
  if existing then
    set_endpoint(existing)
    model_ready = true
    started_here = false
    cb(true)
    return
  end

  start_model(cb)
end

local function toggle_llama()
  if model_starting then
    notify("llama.vim: model is loading")
    return
  end

  if not model_ready then
    ensure_model(function(ok)
      if ok then
        enable_llama()
      end
    end)
    return
  end

  if enabled then
    pcall(vim.fn["llama#disable"])
    enabled = false
    notify("llama.vim: off")
  else
    enable_llama()
  end
end

return {
  {
    "ggml-org/llama.vim",
    url = "https://github.com/ggml-org/llama.vim.git",
    cond = function()
      return ai.provider() == "llama"
    end,
    lazy = true,
    keys = {
      { "<leader>aa", toggle_llama, desc = "Toggle llama.vim" },
    },
    init = function()
      vim.g.llama_config = {
        -- 佔位；實際 port 會在 <leader>aa 啟動/找到 model 後更新
        endpoint_fim = "http://127.0.0.1:41100/infill",
        endpoint_inst = "http://127.0.0.1:41100/v1/chat/completions",

        n_predict = 64,
        t_max_predict_ms = 1000,
        show_info = 0,

        auto_fim = true,
        fim_debounce_ms = 300,
        max_line_suffix = 8,

        n_prefix = 128,
        n_suffix = 32,
        ring_n_chunks = 8,

        keymap_fim_trigger = "<A-e>",
        keymap_fim_accept_full = "<A-f>",
        keymap_fim_accept_word = "<A-w>",
        keymap_fim_accept_line = "<A-q>",
        keymap_fim_next = "<A-l>",
        keymap_fim_prev = "<A-h>",

        -- 不使用 instruction 模式
        keymap_debug_toggle = "",
        keymap_inst_trigger = "",
        keymap_inst_rerun = "",
        keymap_inst_continue = "",
        keymap_inst_accept = "",
        keymap_inst_cancel = "",
      }
    end,
    config = function()
      vim.keymap.set("i", "<A-x>", function()
        pcall(vim.fn["llama#fim_hide"])
      end, { desc = "Dismiss llama.vim suggestion" })

      -- 預設是飽和橘 #ff772f；改成低對比的 muted orange
      local function set_highlights()
        vim.api.nvim_set_hl(0, "llama_hl_fim_hint", { fg = "#b07a50" })
        vim.api.nvim_set_hl(0, "llama_hl_fim_info", { fg = "#808080" })
      end

      set_highlights()
      vim.api.nvim_create_autocmd("ColorScheme", {
        group = vim.api.nvim_create_augroup("llama_highlights", { clear = true }),
        callback = set_highlights,
      })

      vim.api.nvim_create_autocmd("VimLeavePre", {
        group = vim.api.nvim_create_augroup("llama_cleanup", { clear = true }),
        callback = function()
          if started_here then
            vim.fn.jobstart({ "llamastash", "stop", model }, { detach = true })
          end
        end,
      })
    end,
  },
}

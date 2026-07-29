return {
  "nickjvandyke/opencode.nvim",
  version = "*", -- Latest stable release
  config = function()
    ---@type opencode.Opts
    vim.g.opencode_opts = {
      server = {
        start = function()
          local function fallback()
            vim.cmd("vsplit | terminal opencode --port")
            local buf = vim.api.nvim_get_current_buf()
            vim.api.nvim_create_autocmd("TermClose", {
              buffer = buf,
              once = true,
              callback = function()
                if vim.api.nvim_buf_is_valid(buf) then
                  vim.api.nvim_buf_delete(buf, { force = true })
                end
              end,
            })
            vim.cmd("wincmd p")
          end

          if vim.fn.executable("herdr") == 0 then
            return fallback()
          end

          vim.fn.jobstart({ "herdr", "pane", "list" }, {
            stdout_buffered = true,
            on_exit = function(_, code)
              if code ~= 0 then
                return fallback()
              end
              vim.fn.jobstart({
                "herdr", "pane", "split",
                "--current", "--direction", "right",
                "--cwd", vim.fn.getcwd(), "--no-focus",
              }, {
                stdout_buffered = true,
                on_stdout = function(_, data)
                  local output = table.concat(data or {}, "")
                  local ok, result = pcall(vim.fn.json_decode, output)
                  if not (ok and result and result.result and result.result.pane) then
                    return fallback()
                  end
                  vim.fn.jobstart({
                    "herdr", "pane", "run", result.result.pane.pane_id,
                    "opencode", "--port",
                  })
                end,
              })
            end,
          })
        end,
      },
    }

    vim.o.autoread = true -- Required for `vim.g.opencode_opts.events.reload`

    -- Recommended/example keymaps
    vim.keymap.set({ "n", "x" }, "<leader>ao", function()
      require("opencode").ask("@this: ")
    end, { desc = "Ask OpenCode…" })
    vim.keymap.set({ "n", "x" }, "<leader>as", function()
      require("opencode").select()
    end, { desc = "Select OpenCode…" })

    vim.keymap.set({ "n", "x" }, "go", function()
      return require("opencode").operator("@this ")
    end, { desc = "Append range to OpenCode", expr = true })
    vim.keymap.set("n", "goo", function()
      return require("opencode").operator("@this ") .. "_"
    end, { desc = "Append line to OpenCode", expr = true })

    vim.keymap.set("n", "<M-C-u>", function()
      require("opencode").command("session.half.page.up")
    end, { desc = "Scroll OpenCode up" })
    vim.keymap.set("n", "<M-C-d>", function()
      require("opencode").command("session.half.page.down")
    end, { desc = "Scroll OpenCode down" })
  end,
}

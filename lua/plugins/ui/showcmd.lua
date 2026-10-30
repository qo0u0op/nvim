-- Keep the last `showcmd` visible (native/noice behavior) while updating it
-- immediately as keys are typed, and clear it when Esc is pressed.
--
-- noice captures `msg_showcmd` via ext_messages and exposes it through the
-- `status.command` component. lualine only redraws on events like CursorMoved,
-- so counts (1 -> 12 -> 12j) were invisible until the command finished.
-- A `vim.schedule` after each key is too late here, so redraw right after
-- noice has stored the new showcmd message.
--
-- Neovim clears showcmd by sending an empty message, and Esc shows up as "^[".
-- Both are handled here: the empty message is ignored (to keep the value) and
-- Esc removes it instead of displaying "^[".
return {
  {
    "folke/noice.nvim",
    init = function()
      LazyVim.on_load("noice.nvim", function()
        local Msg = require("noice.ui.msg")
        local Manager = require("noice.message.manager")
        local State = require("noice.ui.state")

        if type(Msg.on_showcmd) ~= "function" then
          return
        end

        local function refresh()
          if not package.loaded["lualine"] then
            return
          end
          pcall(function()
            require("lualine").refresh({
              force = true,
              scope = "window",
              place = { "statusline" },
            })
            vim.cmd.redrawstatus()
          end)
        end

        ---Remove the showcmd message so the statusline component is hidden.
        local function clear()
          Manager.remove(Msg.get("msg_showcmd"))
          -- let the next key be reported again, even if it was typed before
          State.clear("msg_showcmd")
          refresh()
        end

        local on_showcmd = Msg.on_showcmd
        Msg.on_showcmd = function(event, content)
          local text = content[1] and content[1][2] or ""
          -- Esc: "^[" or "3^[", also the raw escape byte -> clear, don't show it
          if text:find("%^%[$") or text:find("\27") then
            clear()
            return
          end
          on_showcmd(event, content)
          if content and content[1] then
            refresh()
          end
        end

        -- Esc in insert/cmdline modes sends no msg_showcmd event at all
        vim.on_key(function(key)
          if key == "\27" then
            clear()
          end
        end, vim.api.nvim_create_namespace("showcmd_esc_clear"))
      end)
    end,
  },
}

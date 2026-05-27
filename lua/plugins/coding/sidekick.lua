return {
  {
    "folke/sidekick.nvim",
    opts = {
      -- add any options here
      nes = { enabled = false },
      signs = { enabled = false },
      cli = {
        mux = {
          backend = "zellij",
          enabled = true,
          split = { size = 0.3 },
        },
        tools = { gemini = { cmd = { "gemini" } } },
      },
      copilot = {
        status = {
          enabled = false,
          level = vim.log.levels.WARN,
          -- set to vim.log.levels.OFF to disable notifications
          -- level = vim.log.levels.OFF,
        },
      },
    },
    keys = {
      {
        "<tab>",
        false,
      },
      {
        "<c-.>",
        false,
        mode = { "n", "t", "i", "x" },
      },
      {
        "<leader>aa",
        false,
        -- function()
        --   require("sidekick.cli").toggle()
        -- end,
        -- desc = "Sidekick Toggle CLI",
      },
      {
        "<leader>as",
        false,
        -- function()
        --   require("sidekick.cli").select()
        -- end,
        -- Or to select only installed tools:
        -- require("sidekick.cli").select({ filter = { installed = true } })
        -- desc = "Select CLI",
      },
      {
        "<leader>ad",
        function()
          require("sidekick.cli").close()
        end,
        desc = "Detach a CLI Session",
      },
      {
        "<leader>at",
        function()
          require("sidekick.cli").send({ msg = "{this}" })
        end,
        mode = { "x", "n" },
        desc = "Send This",
      },
      {
        "<leader>af",
        function()
          require("sidekick.cli").send({ msg = "{file}" })
        end,
        desc = "Send File",
      },
      {
        "<leader>av",
        function()
          require("sidekick.cli").send({ msg = "{selection}" })
        end,
        mode = { "x" },
        desc = "Send Visual Selection",
      },
      {
        "<leader>ap",
        function()
          require("sidekick.cli").prompt()
        end,
        mode = { "n", "x" },
        desc = "Sidekick Select Prompt",
      },
      -- Example of a keybinding to open Claude directly
      {
        "<leader>ag",
        function()
          require("sidekick.cli").toggle({ name = "gemini", focus = true })
        end,
        desc = "Sidekick Toggle Gemini",
      },
      {
        "<leader>ax",
        function()
          require("sidekick.cli").toggle({ name = "codex", focus = true })
        end,
        desc = "Sidekick Toggle Codex",
      },
    },
  },
}

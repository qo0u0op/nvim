local function kulala(method)
  return function()
    require("kulala")[method]()
  end
end
return {
  "mistweaverco/kulala.nvim",
  keys = {
    { "<leader>rrs", kulala("run"), desc = "Send request" },
    { "<leader>rra", kulala("run_all"), desc = "Send all requests" },
    { "<leader>rrb", kulala("scratchpad"), desc = "Open scratchpad" },
    { "<leader>rro", kulala("open"), desc = "Open kulala" },
    { "<leader>rrr", kulala("replay"), desc = "Replay the last request" },
    { "<leader>rrn", kulala("jump_next"), desc = "Jump to next request" },
    { "<leader>rrp", kulala("jump_prev"), desc = "Jump to previous request" },
    { "<leader>rrf", kulala("search"), desc = "Find request" },
    { "<leader>rrX", kulala("clear_cached_files"), desc = "Clear cached files" },
  },
  ft = { "http", "rest" },
  opts = {
    -- your configuration comes here
    global_keymaps = false,
    global_keymaps_prefix = "<leader>rr",
    kulala_keymaps_prefix = "",
  },
}

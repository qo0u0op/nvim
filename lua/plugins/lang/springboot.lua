local function spring(method)
  return function()
    local root_file = vim.fs.find({ "pom.xml", "build.gradle", "build.gradle.kts" }, {
      upward = true,
      path = vim.fn.expand("%:p:h"),
    })[1]

    if root_file then
      local project_root = vim.fs.dirname(root_file)
      local old_cwd = vim.fn.getcwd()
      vim.api.nvim_set_current_dir(project_root)
      local ok, err = pcall(require("springboot-nvim")[method])
      vim.api.nvim_set_current_dir(old_cwd)
      if not ok then
        vim.notify("Spring Boot Error: " .. tostring(err), vim.log.levels.ERROR)
      end
    else
      require("springboot-nvim")[method]()
    end
  end
end
return {
  "elmcgill/springboot-nvim",
  ft = "java",
  cond = function()
    return vim.fs.find({ "pom.xml", "build.gradle", "build.gradle.kts" }, { upward = true, path = vim.fn.expand("%:p:h") })[1] ~= nil
  end,
  dependencies = {
    "neovim/nvim-lspconfig",
    "mfussenegger/nvim-jdtls",
  },
  keys = {
    { "<leader>rsr", spring("boot_run"), desc = "Spring Boot Run Project" },
    { "<leader>rsc", spring("generate_class"), desc = "Java Create Class" },
    { "<leader>rsi", spring("generate_interface"), desc = "Java Create Interface" },
    { "<leader>rse", spring("generate_enum"), desc = "Java Create Enum" },
  },
  opts = {},
}

local xdg_config = vim.env.XDG_CONFIG_HOME or vim.fn.expand("~/.config")
local xdg_data = vim.env.XDG_DATA_HOME or vim.fn.expand("~/.local/share")
local maven_settings = vim.fn.expand("~/.config/maven/settings.xml")
local maven_local_repo = xdg_data .. "/maven/repository"

return {
  {
    "mfussenegger/nvim-jdtls",
    opts = function(_, opts)
      -- 1. 啟動 jdtls 本體必須用系統 JDK (≥21)，與專案編譯 JDK 分離
      --    jdtls.py 會優先讀 --java-executable，忽略 mise 污染的 JAVA_HOME
      local system_java = "/usr/lib/jvm/default/bin/java"
      opts.cmd = opts.cmd or { vim.fn.exepath("jdtls") or "jdtls" }
      do
        local has_exec = false
        for _, a in ipairs(opts.cmd) do
          if a:find("--java-executable", 1, true) then
            has_exec = true
            break
          end
        end
        if not has_exec and vim.fn.executable(system_java) == 1 then
          -- 插在 jdtls 之後，避免影響位置相關參數
          table.insert(opts.cmd, 2, "--java-executable=" .. system_java)
        end
      end

      opts.settings = vim.tbl_deep_extend("force", opts.settings or {}, {
        java = {
          configuration = {
            maven = {
              userSettings = maven_settings,
            },
          },
        },
      })

      -- 3. 確保 cmd 存在並加入 JVM 參數（maven 設定 + XDG）
      --    fish 的 MAVEN_ARGS/MAVEN_OPTS 僅對 `mvn` CLI 有效，mason 內嵌的 m2e (eclipse) 不讀環境變數
      --    必須同時透過 JVM 系統屬性與 LSP settings 強制指定，才不會第一次開專案就回落到 ~/.m2/repository
      local has_userSettings, has_repoLocal, has_prefs = false, false, false
      for _, arg in ipairs(opts.cmd) do
        if arg:find("maven.user.settings", 1, true) then
          has_userSettings = true
        end
        if arg:find("maven.repo.local", 1, true) then
          has_repoLocal = true
        end
        if arg:find("java.util.prefs.userRoot", 1, true) then
          has_prefs = true
        end
      end
      if not has_userSettings then
        table.insert(opts.cmd, "--jvm-arg=-Dmaven.user.settings=" .. maven_settings)
      end
      if not has_repoLocal then
        -- 與 ~/.config/maven/settings.xml 的 <localRepository> 保持一致
        table.insert(opts.cmd, "--jvm-arg=-Dmaven.repo.local=" .. maven_local_repo)
      end
      if not has_prefs then
        table.insert(opts.cmd, "--jvm-arg=-Djava.util.prefs.userRoot=" .. xdg_config .. "/java")
      end

      return opts
    end,
  },
}

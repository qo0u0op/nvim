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

      -- 同時設定 userSettings 與 globalSettings，避免 JdtWipe 後第一次 import 讀不到 ~/.config/maven/settings.xml 而 fallback 到 ~/.m2
      opts.settings = vim.tbl_deep_extend("force", opts.settings or {}, {
        java = {
          configuration = {
            maven = {
              userSettings = maven_settings,
              globalSettings = maven_settings,
            },
            updateBuildConfiguration = "automatic",
          },
          import = {
            maven = {
              enabled = true,
            },
          },
        },
      })
      -- 同步寫入 opts.jdtls.settings，確保 LazyVim 的 extend_or_override 合併時不會遺失（config 會以 opts.jdtls 覆蓋 base settings）
      opts.jdtls = opts.jdtls or {}
      opts.jdtls.settings = vim.tbl_deep_extend("force", opts.jdtls.settings or {}, {
        java = {
          configuration = {
            maven = {
              userSettings = maven_settings,
              globalSettings = maven_settings,
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

      -- 3.5 預先播種 workspace 的 m2e / jdt prefs，避免 JdtWipe 後第一次 import 就 fallback 到 ~/.m2
      --     JdtWipe 會清空 ~/.cache/nvim/jdtls/<project>/workspace/.metadata，裡面的
      --     org.eclipse.m2e.core.prefs 與 org.eclipse.jdt.core.prefs 若不存在，m2e 會先用預設 ~/.m2
      --     這裡劫持 jdtls_workspace_dir，在返回前同步寫入正確的 userSettingsFile 與 M2_REPO
      do
        local orig_ws_dir = opts.jdtls_workspace_dir
        opts.jdtls_workspace_dir = function(project_name)
          local dir = nil
          if orig_ws_dir then
            dir = orig_ws_dir(project_name)
          else
            -- 回退到 LazyVim 預設：stdpath("cache").."/jdtls/"..project_name.."/workspace"
            dir = vim.fn.stdpath("cache") .. "/jdtls/" .. (project_name or "default") .. "/workspace"
          end
          local prefs_dir = dir .. "/.metadata/.plugins/org.eclipse.core.runtime/.settings"
          pcall(vim.fn.mkdir, prefs_dir, "p")
          local m2e_prefs = prefs_dir .. "/org.eclipse.m2e.core.prefs"
          local jdt_prefs = prefs_dir .. "/org.eclipse.jdt.core.prefs"
          -- m2e：確保 userSettingsFile 指向 XDG
          if vim.fn.filereadable(m2e_prefs) == 0 then
            pcall(vim.fn.writefile, {
              "eclipse.preferences.version=1",
              "eclipse.m2.userSettingsFile=" .. maven_settings,
            }, m2e_prefs)
          else
            local lines = vim.fn.readfile(m2e_prefs)
            local found = false
            for i, l in ipairs(lines) do
              if l:match("^eclipse%.m2%.userSettingsFile=") then
                lines[i] = "eclipse.m2.userSettingsFile=" .. maven_settings
                found = true
                break
              end
            end
            if not found then
              table.insert(lines, "eclipse.m2.userSettingsFile=" .. maven_settings)
            end
            pcall(vim.fn.writefile, lines, m2e_prefs)
          end
          -- jdt：確保 M2_REPO 指向 XDG
          if vim.fn.filereadable(jdt_prefs) == 0 then
            pcall(vim.fn.writefile, {
              "eclipse.preferences.version=1",
              "org.eclipse.jdt.core.classpathVariable.M2_REPO=" .. maven_local_repo,
            }, jdt_prefs)
          else
            local lines = vim.fn.readfile(jdt_prefs)
            local found = false
            for i, l in ipairs(lines) do
              if l:match("^org%.eclipse%.jdt%.core%.classpathVariable%.M2_REPO=") then
                lines[i] = "org.eclipse.jdt.core.classpathVariable.M2_REPO=" .. maven_local_repo
                found = true
                break
              end
            end
            if not found then
              table.insert(lines, "org.eclipse.jdt.core.classpathVariable.M2_REPO=" .. maven_local_repo)
            end
            pcall(vim.fn.writefile, lines, jdt_prefs)
          end
          return dir
        end
      end

      -- 4. 修復 java-test bundles 遺失（對應錯誤：No LSP client found that supports resolving possible test cases）
      --    LazyVim 預設在 config 階段用 vim.fn.glob("$MASON/share/...") 收集 bundles，
      --    但 $MASON 依賴 mason.nvim 的 setup 才寫入 vim.env.MASON，啟動順序或合併規則可能導致空陣列
      --    這裡用 mason-registry 的實體路徑直接寫入 opts.jdtls.init_options.bundles，確保 jdtls 啟動時必定載入
      do
        local ok, mason_registry = pcall(require, "mason-registry")
        if ok then
          -- 保留 LazyVim 預設：test=true, dap 啟用時才載入 bundles
          if opts.test == nil then
            opts.test = true
          end
          if opts.dap == nil then
            opts.dap = { hotcodereplace = "auto", config_overrides = {} }
          end
          if opts.dap ~= false and mason_registry.is_installed("java-debug-adapter") then
            local bundles = {}
            local debug_pkg = mason_registry.get_package("java-debug-adapter")
            local debug_path = debug_pkg:get_install_path()
            vim.list_extend(bundles, vim.fn.glob(debug_path .. "/extension/server/com.microsoft.java.debug.plugin-*.jar", false, true))
            -- 相容 share 目錄的 symlink 寫法（mason 會在 data/mason/share 建立連結）
            if #bundles == 0 then
              vim.list_extend(bundles, vim.fn.glob(vim.fn.stdpath("data") .. "/mason/share/java-debug-adapter/*.jar", false, true))
            end
            if opts.test ~= false and mason_registry.is_installed("java-test") then
              local test_pkg = mason_registry.get_package("java-test")
              local test_path = test_pkg:get_install_path()
              vim.list_extend(bundles, vim.fn.glob(test_path .. "/extension/server/*.jar", false, true))
              -- 去重（同時 glob packages 與 share 可能重複）
              local seen, uniq = {}, {}
              for _, b in ipairs(bundles) do
                if not seen[b] then
                  seen[b] = true
                  table.insert(uniq, b)
                end
              end
              bundles = uniq
            end
            if #bundles > 0 then
              opts.jdtls = opts.jdtls or {}
              opts.jdtls.init_options = opts.jdtls.init_options or {}
              opts.jdtls.init_options.bundles = bundles
            end
          end
        end
      end

      return opts
    end,
  },
}

local xdg_config = vim.env.XDG_CONFIG_HOME or vim.fs.normalize("~/.config")
local xdg_data = vim.env.XDG_DATA_HOME or vim.fs.normalize("~/.local/share")
local mason_data = vim.fn.stdpath("data") .. "/mason"

-- jdtls 本體固定用系統 JDK，與專案編譯用的 JDK 分離
local system_java = "/usr/lib/jvm/default/bin/java"

--------------------------------------------------------------------------
-- 小工具
--------------------------------------------------------------------------

local function is_dir(path)
  local stat = path and vim.uv.fs_stat(path)
  return stat ~= nil and stat.type == "directory"
end

local function is_executable(path)
  return path ~= nil and vim.uv.fs_access(path, "X") == true
end

local function ensure_dir(path)
  if is_dir(path) then
    return true
  end
  local parent = vim.fs.dirname(path)
  if parent and parent ~= path then
    ensure_dir(parent)
  end
  return vim.uv.fs_mkdir(path, 493) ~= nil -- 0755
end

local function read_lines(path)
  local file = io.open(path, "r")
  if not file then
    return nil
  end
  local lines = {}
  for line in file:lines() do
    lines[#lines + 1] = line
  end
  file:close()
  return lines
end

local function write_lines(path, lines)
  local file = io.open(path, "w")
  if not file then
    return false
  end
  file:write(table.concat(lines, "\n"), "\n")
  file:close()
  return true
end

-- 更新 Eclipse prefs 的單一 key，不存在就附加
local function set_pref(path, key, value)
  local lines = read_lines(path) or { "eclipse.preferences.version=1" }
  local entry = key .. "=" .. value
  local pattern = "^" .. vim.pesc(key) .. "="

  for i, line in ipairs(lines) do
    if line:match(pattern) then
      lines[i] = entry
      return write_lines(path, lines)
    end
  end

  lines[#lines + 1] = entry
  return write_lines(path, lines)
end

-- 列出目錄中檔名符合 Lua pattern 的檔案（含 symlink）
local function list_files(dir, pattern)
  local files = {}
  if not is_dir(dir) then
    return files
  end

  for name in vim.fs.dir(dir) do
    local path = dir .. "/" .. name
    local stat = vim.uv.fs_stat(path)
    if stat and stat.type == "file" and name:match(pattern) then
      files[#files + 1] = path
    end
  end

  return files
end

local function unique(list)
  local seen, result = {}, {}
  for _, item in ipairs(list) do
    if not seen[item] then
      seen[item] = true
      result[#result + 1] = item
    end
  end
  return result
end

local function has_arg(cmd, needle)
  for _, arg in ipairs(cmd) do
    if arg:find(needle, 1, true) then
      return true
    end
  end
  return false
end

-- 只補上還沒有的 -D 屬性
local function ensure_jvm_args(cmd, properties)
  for _, property in ipairs(properties) do
    local key = property:match("^%-D([^=]+)=")
    if key and not has_arg(cmd, key) then
      cmd[#cmd + 1] = "--jvm-arg=" .. property
    end
  end
end

local function ensure_java_executable(cmd, java)
  if not is_executable(java) or has_arg(cmd, "--java-executable") then
    return
  end
  -- 插在 jdtls 之後，避免影響位置相關參數
  table.insert(cmd, 2, "--java-executable=" .. java)
end

--------------------------------------------------------------------------
-- Maven：settings 與 local repository 都放 XDG
--------------------------------------------------------------------------

local maven = {
  settings = xdg_config .. "/maven/settings.xml",
  repository = xdg_data .. "/maven/repository",
}

function maven.lsp_configuration()
  return {
    userSettings = maven.settings,
    globalSettings = maven.settings,
  }
end

function maven.lsp_import()
  return { enabled = true }
end

function maven.jvm_properties()
  return {
    "-Dmaven.user.settings=" .. maven.settings,
    "-Dmaven.repo.local=" .. maven.repository,
  }
end

-- JdtWipe 後 workspace prefs 不存在時，m2e 會先用預設 ~/.m2，先寫入正確值
function maven.seed_workspace(workspace_dir)
  local prefs_dir = workspace_dir .. "/.metadata/.plugins/org.eclipse.core.runtime/.settings"
  ensure_dir(prefs_dir)

  set_pref(prefs_dir .. "/org.eclipse.m2e.core.prefs", "eclipse.m2.userSettingsFile", maven.settings)
  set_pref(
    prefs_dir .. "/org.eclipse.jdt.core.prefs",
    "org.eclipse.jdt.core.classpathVariable.M2_REPO",
    maven.repository
  )
end

--------------------------------------------------------------------------
-- Gradle：停用 wrapper 改用 mise 的安裝，快取放 XDG 與指令列共用
--------------------------------------------------------------------------

local gradle = {
  user_home = xdg_data .. "/gradle",
  installation = (function()
    local result = vim.system({ "mise", "where", "gradle" }, { text = true }):wait()
    if result.code ~= 0 then
      return nil
    end
    local dir = vim.trim(result.stdout or "")
    return is_dir(dir) and dir or nil
  end)(),
}

function gradle.lsp_import()
  return {
    enabled = true,
    wrapper = { enabled = false },
    home = gradle.installation,
    user = { home = gradle.user_home },
  }
end

function gradle.jvm_properties()
  return { "-Dgradle.user.home=" .. gradle.user_home }
end

--------------------------------------------------------------------------
-- 共用的 java settings
--------------------------------------------------------------------------

local java_prefs_root = xdg_config .. "/java"

local function java_settings()
  return {
    java = {
      configuration = {
        maven = maven.lsp_configuration(),
        updateBuildConfiguration = "automatic",
      },
      import = {
        maven = maven.lsp_import(),
        gradle = gradle.lsp_import(),
      },
    },
  }
end

-- java-test / java-debug-adapter bundles（避免依賴 LazyVim 的 $MASON 時序）
local function collect_bundles(include_tests)
  local ok, registry = pcall(require, "mason-registry")
  if not ok then
    return {}
  end

  local function install_path(name)
    if not registry.is_installed(name) then
      return nil
    end
    return registry.get_package(name):get_install_path()
  end

  local debug_dir = install_path("java-debug-adapter")
  if not debug_dir then
    return {}
  end

  local bundles =
    list_files(debug_dir .. "/extension/server", "^com%.microsoft%.java%.debug%.plugin%-.*%.jar$")

  if #bundles == 0 then
    -- mason 會在 share 目錄建立 symlink
    vim.list_extend(bundles, list_files(mason_data .. "/share/java-debug-adapter", "%.jar$"))
  end

  local test_dir = include_tests and install_path("java-test")
  if test_dir then
    vim.list_extend(bundles, list_files(test_dir .. "/extension/server", "%.jar$"))
  end

  return unique(bundles)
end

return {
  {
    "mfussenegger/nvim-jdtls",
    opts = function(_, opts)
      opts.cmd = opts.cmd or { vim.fn.exepath("jdtls") or "jdtls" }
      ensure_java_executable(opts.cmd, system_java)

      local settings = java_settings()
      opts.settings = vim.tbl_deep_extend("force", opts.settings or {}, settings)

      opts.jdtls = opts.jdtls or {}
      -- LazyVim 會以 opts.jdtls 覆蓋 base settings，兩邊都要寫
      opts.jdtls.settings = vim.tbl_deep_extend("force", opts.jdtls.settings or {}, settings)
      -- import 在 initialize 階段就開始，settings 要放 initializationOptions 才趕得上
      opts.jdtls.init_options = opts.jdtls.init_options or {}
      opts.jdtls.init_options.settings =
        vim.tbl_deep_extend("force", opts.jdtls.init_options.settings or {}, settings)

      -- fish 的 MAVEN_ARGS/MAVEN_OPTS 只對 mvn CLI 有效，m2e/Buildship 要另外給 JVM 屬性
      local jvm_properties = { "-Djava.util.prefs.userRoot=" .. java_prefs_root }
      vim.list_extend(jvm_properties, maven.jvm_properties())
      vim.list_extend(jvm_properties, gradle.jvm_properties())
      ensure_jvm_args(opts.cmd, jvm_properties)

      local workspace_dir = opts.jdtls_workspace_dir
      opts.jdtls_workspace_dir = function(project_name)
        local dir = workspace_dir and workspace_dir(project_name)
          or vim.fn.stdpath("cache") .. "/jdtls/" .. (project_name or "default") .. "/workspace"
        maven.seed_workspace(dir)
        return dir
      end

      -- 保留 LazyVim 預設：test=true，dap 啟用時才載入 bundles
      if opts.test == nil then
        opts.test = true
      end
      if opts.dap == nil then
        opts.dap = { hotcodereplace = "auto", config_overrides = {} }
      end
      if opts.dap ~= false then
        local bundles = collect_bundles(opts.test ~= false)
        if #bundles > 0 then
          opts.jdtls.init_options.bundles = bundles
        end
      end

      return opts
    end,
  },
}

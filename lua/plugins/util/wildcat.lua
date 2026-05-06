return {
  "https://codeberg.org/caskstrength/nvim-wildcat.git",
  lazy = true,
  cmd = { "WildcatRun", "WildcatUp", "WildcatServer" },
  ft = { "java" },
  event = { "BufReadPost pom.xml", "BufReadPost build.gradle" },
  dependencies = {
    "https://codeberg.org/caskstrength/nvim-popcorn.git",
    "https://codeberg.org/caskstrength/nvim-spinetta.git",
  },
  keys = {
    {
      "<leader>rwr",
      "<cmd>WildcatRun<cr>",
      desc = "Wildcat Run",
    },
    {
      "<leader>rwd",
      "<cmd>WildcatDown<cr>",
      desc = "Wildcat Down",
    },
    {
      "<leader>rwc",
      "<cmd>WildcatClean<cr>",
      desc = "Wildcat Clean",
    },
  },
  opts = {

    -- Optional. Default 15
    -- The size of the server console
    console_size = 5,

    -- Optional. Default "jboss"
    -- Default server (jboss or tomcat)
    default_server = "tomcat",

    -- Optional. Default "maven"
    -- Build tool (maven or gradle)
    build_tool = "maven",

    -- Optional. Default JAVA_HOME from the system
    -- If a different java home is required
    java_home = "/usr/lib/jvm/java-21-openjdk/",

    -- Optional
    -- Default path CATALINA_HOME from the system
    -- Default app_base "webapps"
    tomcat = {
      -- path = " ~/.local/share/asdf/installs/tomcat/10.1.52/",
      app_base = "webapps",
    },
  },
}

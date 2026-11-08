-- luacheck configuration.
-- cfflatex.lua runs in LuaTeX and texlua, which use Lua 5.3.
std = "lua53"

-- l3build reads its settings from global variables that these files set but
-- never read themselves, so unused globals (131) are expected.
local l3build_config = {allow_defined_top = true, ignore = {"131"}}
-- build.lua also wraps l3build's install and uninstall targets, reading the
-- command-line options of l3build.
files["build.lua"] = {allow_defined_top = true, ignore = {"131"},
  globals = {"target_list"}, read_globals = {"options"}}
files["config-*.lua"] = l3build_config

-- The CLI tests use texlua's environment setter to isolate the TeX cache.
files["tests/test_cfflatexpand.lua"] = {read_globals = {"os.setenv"}}
files["cfflatexpand-authors.lua"] = {read_globals = {"os.setenv"}}

-- l3build output, and the scripts lt3luabridge generates when pdfLaTeX
-- compiles a document (also listed in .gitignore).
exclude_files = {"build/**", "**/*.luabridge.lua"}

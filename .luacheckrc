-- luacheck configuration.
-- cfflatex.lua runs in LuaTeX and texlua, which use Lua 5.3.
std = "lua53"

-- l3build reads its settings from global variables that these files set but
-- never read themselves, so unused globals (131) are expected.
local l3build_config = {allow_defined_top = true, ignore = {"131"}}
files["build.lua"] = l3build_config
files["config-*.lua"] = l3build_config

-- l3build output, including lt3luabridge's generated scripts.
exclude_files = {"build/**"}

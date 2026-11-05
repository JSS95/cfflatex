-- l3build configuration: run `l3build check` to test cfflatex.
module = "cfflatex"

sourcefiles = {"cfflatex.sty", "cfflatex.lua"}
installfiles = sourcefiles

-- pdfLaTeX runs cfflatex.lua through the shell; LuaLaTeX runs it directly.
checkengines = {"pdftex", "luatex"}
checkopts = "-interaction=nonstopmode --shell-escape"

-- config-noshell.lua runs testfiles-noshell/ without shell escape.
checkconfigs = {"build", "config-noshell"}

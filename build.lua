-- l3build configuration.
--   l3build check        run the tests
--   l3build doc          typeset the manual, cfflatex.pdf
--   l3build tag VERSION  set the version and today's date in the sources
--   l3build ctan         run the tests and build the CTAN archive
--   l3build upload       submit the CTAN archive (asks for your email)
module = "cfflatex"

sourcefiles = {"cfflatex.sty", "cfflatex.lua"}
installfiles = sourcefiles

-- Tests ---------------------------------------------------------------------

-- pdfLaTeX runs cfflatex.lua through the shell; LuaLaTeX runs it directly.
checkengines = {"pdftex", "luatex"}
checkopts = "-interaction=nonstopmode --shell-escape"

-- config-noshell.lua runs testfiles-noshell/ without shell escape.
checkconfigs = {"build", "config-noshell"}

-- Documentation -------------------------------------------------------------

-- The manual reads its title and author from CITATION.cff with cfflatex.
-- LuaLaTeX runs cfflatex.lua without shell escape.
typesetfiles = {"cfflatex.tex"}
typesetexe = "lualatex"
docfiles = {"CITATION.cff"}
demofiles = {"example.tex", "example.cff"}
textfiles = {"README.md", "CHANGELOG.md", "LICENSE"}

-- Release -------------------------------------------------------------------

-- The version and date live in \ProvidesExplPackage in cfflatex.sty; the
-- manual reads them from there with \GetFileInfo.
local function package_version()
  local file = assert(io.open("cfflatex.sty", "r"))
  local content = file:read("a")
  file:close()
  return content:match("\\ProvidesExplPackage{cfflatex}{[^}]*}{([^}]*)}")
end

tagfiles = {"cfflatex.sty", "CITATION.cff"}

function update_tag(file, content, tagname, tagdate)
  if file == "cfflatex.sty" then
    return (content:gsub(
      "(\\ProvidesExplPackage{cfflatex}){[^}]*}{[^}]*}",
      "%1{" .. tagdate .. "}{" .. tagname .. "}"))
  elseif file == "CITATION.cff" then
    content = content:gsub("\nversion: [^\n]*", "\nversion: " .. tagname)
    return (content:gsub("\ndate%-released: [^\n]*",
      "\ndate-released: " .. tagdate))
  end
  return content
end

-- l3build asks for the uploader's email, or takes it from --email. It also
-- asks CTAN whether this is a new package or an update.
uploadconfig = {
  pkg = "cfflatex",
  version = package_version(),
  author = "Jisoo Song",
  uploader = "Jisoo Song",
  license = "mit",
  summary = "Import Citation File Format metadata into LaTeX",
  description = [[
    The package reads the title and authors of a citation from a Citation
    File Format (CFF) file, such as the CITATION.cff file of a research
    software repository, into a LaTeX document, so that the metadata is
    written only once. It works with LuaLaTeX, and with pdfLaTeX when shell
    escape is enabled.
  ]],
  ctanPath = "/macros/latex/contrib/cfflatex",
  topic = {"metadata", "data-import"},
  home = "https://github.com/JSS95/cfflatex",
  repository = "https://github.com/JSS95/cfflatex",
  bugtracker = "https://github.com/JSS95/cfflatex/issues",
}

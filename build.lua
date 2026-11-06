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
-- -recorder writes the .fls file that the .fvt tests below compare.
checkengines = {"pdftex", "luatex"}
checkopts = "-interaction=nonstopmode --shell-escape -recorder"

-- config-noshell.lua runs testfiles-noshell/ without shell escape.
checkconfigs = {"build", "config-noshell"}

-- Besides the usual .lvt tests, .fvt tests check that the CFF files a
-- document reads are listed in the .fls file, which latexmk and LaTeX
-- Workshop use to rebuild when a dependency changes. The .fls file, reduced
-- to its sorted, distinct CFF inputs, is compared with the .tfl reference.
local function rewrite_fls(source, result)
  local inputs, seen = {}, {}
  for line in io.lines(source) do
    local file = line:gsub("\r$", ""):match("^INPUT (.+%.cff)$")
    if file then
      file = file:gsub("^%./", "")
      if not seen[file] then
        seen[file] = true
        inputs[#inputs + 1] = "INPUT " .. file
      end
    end
  end
  table.sort(inputs)
  local output = assert(io.open(result, "w"))
  output:write(table.concat(inputs, "\n"), "\n")
  output:close()
end

test_types = {
  fls = {test = ".fvt", generated = ".fls", reference = ".tfl",
    rewrite = rewrite_fls},
}
test_order = {"log", "pdf", "fls"}

-- Documentation -------------------------------------------------------------

-- The manual reads its metadata from CITATION.cff with cfflatex.
-- LuaLaTeX runs cfflatex.lua without shell escape.
typesetfiles = {"cfflatex.tex"}
typesetexe = "lualatex"
docfiles = {"CITATION.cff", "cfflatex.bib"}
-- l3build defaults to bibtex8, which is not in every TeX Live installation.
bibtexexe = "bibtex"
bibtexopts = ""
textfiles = {"README.md", "CHANGELOG.md", "LICENSE"}

-- The manual shows the version and date of cfflatex.sty, unless the
-- environment variables CFFLATEX_DOC_VERSION and CFFLATEX_DOC_DATE give
-- others. CI sets them to the commit hash and commit date for a push, and to
-- the tag and publication date for a release (see .github/workflows/ci.yml).
local function doc_value(name)
  local value = os.getenv(name)
  if value == nil or value == "" then
    return nil
  end
  -- The value is put in the shell command that runs LuaLaTeX.
  assert(value:match("^[%w.+-]+$"),
    name .. " may contain only letters, digits, '.', '+', and '-'")
  return value
end

local doc_version = doc_value("CFFLATEX_DOC_VERSION")
local doc_date = doc_value("CFFLATEX_DOC_DATE")
typesetcmds = (doc_version and ("\\def\\cfflatexdocversion{" .. doc_version .. "}") or "")
  .. (doc_date and ("\\def\\cfflatexdocdate{" .. doc_date .. "}") or "")

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

-- l3build asks for the uploader's email, or takes it from --email. CD passes
-- --file with the GitHub Release notes as the CTAN announcement.
uploadconfig = {
  pkg = "cfflatex",
  version = package_version(),
  author = "Jisoo Song",
  uploader = "Jisoo Song",
  license = "mit",
  summary = "Import Citation File Format metadata into LaTeX",
  description = [[
    The package reads metadata from a Citation File Format (CFF) file of a
    research software repository, into a LaTeX document.
    It works with LuaLaTeX, and with pdfLaTeX when shell escape is enabled.
  ]],
  ctanPath = "/macros/latex/contrib/cfflatex",
  topic = {"metadata", "data-import"},
  home = "https://github.com/JSS95/cfflatex",
  repository = "https://github.com/JSS95/cfflatex",
  bugtracker = "https://github.com/JSS95/cfflatex/issues",
}

-- CD opts into noninteractive submission of the archive it already built.
-- Treat HTTP errors as failures, including errors from the upload endpoint.
if os.getenv("CFFLATEX_CTAN_UPLOAD") == "true" then
  ctanupload = true
  curlexe = "curl --fail-with-body --silent --show-error"
    .. " --connect-timeout 30 --max-time 300"
end

-- The catalogue lookup in cd.yml distinguishes a new package from an update.
local ctan_update = os.getenv("CFFLATEX_CTAN_UPDATE")
if ctan_update then
  uploadconfig.update = ctan_update == "true"
end

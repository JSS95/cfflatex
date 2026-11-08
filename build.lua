-- l3build configuration.
--   l3build check        run the tests
--   l3build doc          typeset the manual, import-citation-cff.pdf
--   l3build tag VERSION  set the version and today's date in the sources
--   l3build ctan         run the tests and build the CTAN archive
--   l3build upload       submit the CTAN archive (asks for your email)
module = "import-citation-cff"

sourcefiles = {
  "import-citation-cff.sty", "cfflatex-style-*.def", "cfflatex.lua", "cfflatex-data.lua",
  "cfflatexpand", "cfflatexpand.lua", "cfflatexpand-authors.lua",
}
-- l3build separates scriptfiles from the TeX runtime files during installation.
installfiles = sourcefiles
scriptfiles = {"cfflatexpand"}
-- Preserve the command's executable bit in both CTAN and TDS archives.
exefiles = scriptfiles
-- CTAN installs a TDS archive only when TeX Live asks for it, so the CTAN
-- archive leaves it out. l3build still writes it to build/distrib/tds/, where
-- CD tests it and attaches it to the GitHub release.
packtdszip = false

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

-- The manual reads its metadata from CITATION.cff with import-citation-cff.
-- LuaLaTeX runs cfflatex.lua without shell escape.
typesetfiles = {"import-citation-cff.tex"}
typesetexe = "lualatex"
docfiles = {"CITATION.cff", "import-citation-cff.bib"}
-- l3build defaults to bibtex8, which is not in every TeX Live installation.
bibtexexe = "bibtex"
bibtexopts = ""
textfiles = {"README.md", "CHANGELOG.md", "LICENSE"}

-- The manual shows the version and date of import-citation-cff.sty, unless the
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

-- The version and date live in \ProvidesExplPackage in import-citation-cff.sty; the
-- manual reads them from there with \GetFileInfo.
local function package_version()
  local file = assert(io.open("import-citation-cff.sty", "r"))
  local content = file:read("a")
  file:close()
  return content:match("\\ProvidesExplPackage{import%-citation%-cff}{[^}]*}{([^}]*)}")
end

local version = assert(package_version(), "Missing package version in import-citation-cff.sty")
ctanzip = module .. "-" .. version

tagfiles = {"import-citation-cff.sty", "CITATION.cff"}

function update_tag(file, content, tagname, tagdate)
  if file == "import-citation-cff.sty" then
    return (content:gsub(
      "(\\ProvidesExplPackage{import%-citation%-cff}){[^}]*}{[^}]*}",
      "%1{" .. tagdate .. "}{" .. tagname .. "}"))
  elseif file == "CITATION.cff" then
    content = content:gsub("\nversion: [^\n]*", "\nversion: " .. tagname)
    return (content:gsub("\ndate%-released: [^\n]*",
      "\ndate-released: " .. tagdate))
  end
  return content
end

-- l3build asks for the uploader's email, or takes it from --email. CD passes
-- --file with the CHANGELOG entry shared with GitHub as the CTAN announcement.
uploadconfig = {
  pkg = "import-citation-cff",
  version = version,
  author = "Jisoo Song",
  uploader = "Jisoo Song",
  license = "mit",
  summary = "Import Citation File Format metadata into LaTeX",
  description = [[
    The package reads metadata from a Citation File Format (CFF) file of a
    research software repository, into a LaTeX document.
    It works with LuaLaTeX, and with pdfLaTeX when shell escape is enabled.
  ]],
  ctanPath = "/macros/latex/contrib/import-citation-cff",
  topic = {"metadata", "data-import"},
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

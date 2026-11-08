-- l3build configuration.
--   l3build check        run the tests
--   l3build doc          typeset the manual, import-citation-cff.pdf
--   l3build tag VERSION  set the version and today's date in the sources
--   l3build ctan         run the tests and build the CTAN archive
--   l3build upload       submit the CTAN archive (asks for your email)
--   l3build install      install into TEXMFHOME and link the command
--   l3build uninstall    remove the installation and the command link
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

-- Command link --------------------------------------------------------------

-- TeX Live links cfflatexpand into its binary directory, and tlmgr removes the
-- link with the package. For the personal tree, l3build install links the
-- command into $CFFLATEXPAND_BINDIR, by default ~/.local/bin, and l3build
-- uninstall removes that link; an empty CFFLATEXPAND_BINDIR makes no link.
-- An environment variable, because l3build reads its command-line options
-- before this file and rejects unknown ones.
local lfs = require("lfs")
local windows = package.config:sub(1, 1) == "\\"

local function absolute(path)
  return path:match("^/") and path or lfs.currentdir() .. "/" .. path
end

-- The link and the installed command it points to, or nil for no link.
local function command_link()
  local bindir = os.getenv("CFFLATEXPAND_BINDIR")
  if bindir == nil then
    bindir = os.getenv("HOME") and os.getenv("HOME") .. "/.local/bin" or ""
  end
  if bindir == "" or windows then
    return nil
  end
  -- The tree that l3build installs into: --texmfhome, or else TEXMFHOME.
  local texmfhome = options["texmfhome"]
  if not texmfhome then
    local kpse = require("kpse")
    kpse.set_program_name("latex")
    texmfhome = kpse.var_value("TEXMFHOME")
  end
  return absolute(bindir) .. "/cfflatexpand",
    absolute(texmfhome) .. "/scripts/" .. module .. "/cfflatexpand"
end

local function is_link_to(link, target)
  return lfs.symlinkattributes(link, "mode") == "link" and lfs.readlink(link) == target
end

local function make_directory(path)
  if path == "" or lfs.attributes(path, "mode") == "directory" then
    return
  end
  make_directory(path:match("^(.*)/[^/]*$") or "")
  lfs.mkdir(path)
end

local function in_path(directory)
  for entry in ((os.getenv("PATH") or "") .. ":"):gmatch("([^:]*):") do
    if entry:gsub("/$", "") == directory then
      return true
    end
  end
  return false
end

local install_files_target = target_list.install.func
target_list.install.func = function(names)
  local errorlevel = install_files_target(names)
  local link, command = command_link()
  if errorlevel ~= 0 then
    return errorlevel
  elseif windows then
    print("\nRun cfflatexpand with texlua and its full path; it is not linked on Windows.")
    return 0
  elseif not link then
    return 0
  elseif options["dry-run"] then
    print("\nFor linking the command:\n- " .. link .. " -> " .. command)
    return 0
  end
  local directory = link:match("^(.*)/[^/]*$")
  if not is_link_to(link, command) then
    if lfs.symlinkattributes(link, "mode") then
      print("\nWarning: " .. link .. " exists, so cfflatexpand is not linked there."
        .. " Set CFFLATEXPAND_BINDIR to link it elsewhere.")
      return 0
    end
    make_directory(directory)
    lfs.link(command, link, true)
    if not is_link_to(link, command) then
      print("\nError: cannot link " .. link .. " to " .. command)
      return 1
    end
  end
  print("\nLinked " .. link .. " -> " .. command)
  if not in_path(directory) then
    print("Add " .. directory .. " to PATH to run cfflatexpand by name.")
  end
  return 0
end

-- Only a link to the command of this tree is removed, never another file.
local uninstall_files_target = target_list.uninstall.func
target_list.uninstall.func = function(names)
  local link, command = command_link()
  if link and is_link_to(link, command) then
    if options["dry-run"] then
      print("\nFor removal of the command link:\n- " .. link)
    else
      assert(os.remove(link))
      print("\nRemoved the link " .. link)
    end
  end
  return uninstall_files_target(names)
end

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

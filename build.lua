-- l3build configuration.
--   l3build check        run the tests
--   l3build doc          typeset the manual, import-citation-cff.pdf
--   l3build tag VERSION  set the version and today's date in the sources
--   l3build ctan         run the tests and build the CTAN archive
--   l3build upload       submit the CTAN archive (asks for your email)
--   l3build install      install into TEXMFHOME and link the command; --full
--                        also installs the manual and the man page, and
--                        links the man page
--   l3build uninstall    remove the installation and the links
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
-- The man page of the command goes to doc/man/man1 in TDS archives and
-- installations, where TeX Live's man directory finds it.
scriptmanfiles = {"cfflatexpand.1"}
-- CTAN installs a TDS archive only when TeX Live asks for it, so the CTAN
-- archive leaves it out. l3build still writes it to build/distrib/tds/, where
-- CD tests it and attaches it to the GitHub release.
packtdszip = false

-- Command link --------------------------------------------------------------

-- TeX Live links cfflatexpand into its binary directory, and tlmgr removes the
-- link with the package. For the personal tree, l3build install links the
-- command into $CFFLATEXPAND_BINDIR, by default ~/.local/bin, and with --full
-- the man page into the share/man/man1 beside it, by default
-- ~/.local/share/man/man1. l3build uninstall removes the links; an empty
-- CFFLATEXPAND_BINDIR makes no links.
-- An environment variable, because l3build reads its command-line options
-- before this file and rejects unknown ones.
--
-- Windows runs neither symbolic links, which need privileges, nor scripts
-- without an extension, so the link there is cfflatexpand.cmd, a batch file
-- that runs the command with texlua. The default directory is
-- %USERPROFILE%\.local\bin.
local lfs = require("lfs")
local windows = package.config:sub(1, 1) == "\\"

local function absolute(path)
  if path:match("^[/\\]") or path:match("^%a:[/\\]") then
    return path
  end
  return lfs.currentdir() .. "/" .. path
end

local function native(path)
  return windows and (path:gsub("/", "\\")) or path
end

local function parent(path)
  return path:match("^(.*)[/\\][^/\\]*$")
end

-- The links to make, each with the installed file that it points to: the
-- command, and with man_page, a link to the man page in share/man/man1 beside
-- the command's directory, where man looks for the pages of a bin directory
-- in PATH. None for an empty CFFLATEXPAND_BINDIR.
local function command_links(man_page)
  local bindir = os.getenv("CFFLATEXPAND_BINDIR")
  if bindir == nil then
    local home = os.getenv(windows and "USERPROFILE" or "HOME")
    bindir = home and home .. "/.local/bin" or ""
  end
  if bindir == "" then
    return {}
  end
  -- The tree that l3build installs into: --texmfhome, or else TEXMFHOME.
  local texmfhome = options["texmfhome"]
  if not texmfhome then
    local kpse = require("kpse")
    kpse.set_program_name("latex")
    texmfhome = kpse.var_value("TEXMFHOME")
  end
  bindir, texmfhome = absolute(bindir), absolute(texmfhome)
  local links = {{
    name = "the command",
    link = native(bindir .. "/cfflatexpand" .. (windows and ".cmd" or "")),
    target = native(texmfhome .. "/scripts/" .. module .. "/cfflatexpand"),
  }}
  if man_page and not windows then
    links[2] = {
      name = "the man page",
      link = (parent(bindir) or "") .. "/share/man/man1/cfflatexpand.1",
      target = texmfhome .. "/doc/man/man1/cfflatexpand.1",
    }
  end
  return links
end

-- The batch file stands for the link on Windows. %% is a literal % in batch
-- files; exit /b passes the exit status of texlua to the caller.
local function batch_file(command)
  return "@echo off\r\ntexlua \"" .. command:gsub("%%", "%%%%")
    .. "\" %*\r\nexit /b %errorlevel%\r\n"
end

local function is_link_to(link, command)
  if windows then
    local file = io.open(link, "rb")
    local text = file and file:read("a")
    if file then
      file:close()
    end
    return text == batch_file(command)
  end
  return lfs.symlinkattributes(link, "mode") == "link" and lfs.readlink(link) == command
end

local function make_link(link, command)
  if windows then
    local file = io.open(link, "wb")
    if file then
      file:write(batch_file(command))
      file:close()
    end
  else
    lfs.link(command, link, true)
  end
end

local function make_directory(path)
  if path == "" or lfs.attributes(path, "mode") == "directory" then
    return
  end
  make_directory(parent(path) or "")
  lfs.mkdir(path)
end

local function in_path(directory)
  local function normalize(path)
    path = path:gsub("[/\\]+$", "")
    return windows and native(path):lower() or path
  end
  local separator = windows and ";" or ":"
  for entry in ((os.getenv("PATH") or "") .. separator):gmatch("([^" .. separator .. "]*)" .. separator) do
    if normalize(entry) == normalize(directory) then
      return true
    end
  end
  return false
end

-- An existing file that is not the link is never replaced.
local function link_installed(item)
  if not is_link_to(item.link, item.target) then
    if lfs.symlinkattributes(item.link, "mode") then
      print("\nWarning: " .. item.link .. " exists, so " .. item.name
        .. " is not linked there. Set CFFLATEXPAND_BINDIR to link it elsewhere.")
      return 0
    end
    make_directory(parent(item.link))
    make_link(item.link, item.target)
    if not is_link_to(item.link, item.target) then
      print("\nError: cannot link " .. item.link .. " to " .. item.target)
      return 1
    end
  end
  print("\nLinked " .. item.link .. " -> " .. item.target)
  return 0
end

local install_files_target = target_list.install.func
target_list.install.func = function(names)
  local errorlevel = install_files_target(names)
  if errorlevel ~= 0 then
    return errorlevel
  end
  -- l3build installs the man page only with --full.
  local links = command_links(options["full"])
  for _, item in ipairs(links) do
    if options["dry-run"] then
      print("\nFor linking " .. item.name .. ":\n- " .. item.link .. " -> " .. item.target)
    else
      errorlevel = link_installed(item)
      if errorlevel ~= 0 then
        return errorlevel
      end
    end
  end
  local directory = links[1] and parent(links[1].link)
  if directory and not options["dry-run"] and not in_path(directory) then
    print("Add " .. directory .. " to PATH to run cfflatexpand by name.")
  end
  return 0
end

-- Only the links to the files of this tree are removed, never another file.
local uninstall_files_target = target_list.uninstall.func
target_list.uninstall.func = function(names)
  -- l3build removes the man page with or without --full, and so its link.
  for _, item in ipairs(command_links(true)) do
    if is_link_to(item.link, item.target) then
      if options["dry-run"] then
        print("\nFor removal of the link to " .. item.name .. ":\n- " .. item.link)
      else
        assert(os.remove(item.link))
        print("\nRemoved the link " .. item.link)
      end
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

-- With pdfTeX, lt3luabridge reads the result of Lua from a shell command, and
-- the log of a fatal error shows that command as an input file, (|COMMAND).
-- The command is a sh script on Unix and a cmd.exe one on Windows, so it is
-- replaced with (|...) after l3build's own normalization, and one .tlg file
-- serves both. The command can contain parentheses, so the replacement
-- reaches the parenthesis that balances the opening one.
local function hide_shell_commands(text)
  local pieces, cursor = {}, 1
  while true do
    local start = text:find("(|", cursor, true)
    if not start then
      break
    end
    local depth, position = 0, start
    repeat
      local character = text:sub(position, position)
      if character == "(" then
        depth = depth + 1
      elseif character == ")" then
        depth = depth - 1
      end
      position = position + 1
    until depth == 0 or position > #text
    pieces[#pieces + 1] = text:sub(cursor, start - 1) .. "(|...)"
    cursor = position
  end
  pieces[#pieces + 1] = text:sub(cursor)
  return table.concat(pieces)
end

local function rewrite_log_without_shell(source, result, engine, errlevels)
  rewrite_log(source, result, engine, errlevels)
  local file = assert(io.open(result, "rb"))
  local content = file:read("a"):gsub("\r\n", "\n")
  file:close()
  file = assert(io.open(result, "w"))
  file:write(hide_shell_commands(content))
  file:close()
end

test_types = {
  -- l3build's defaults, except for the rewrite.
  log = {test = ".lvt", generated = ".log", reference = ".tlg", expectation = ".lve",
    compare = compare_tlg, rewrite = rewrite_log_without_shell},
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

tagfiles = {"import-citation-cff.sty", "CITATION.cff", "cfflatexpand.1"}

function update_tag(file, content, tagname, tagdate)
  if file == "import-citation-cff.sty" then
    return (content:gsub(
      "(\\ProvidesExplPackage{import%-citation%-cff}){[^}]*}{[^}]*}",
      "%1{" .. tagdate .. "}{" .. tagname .. "}"))
  elseif file == "cfflatexpand.1" then
    -- The date and the source of the man page title line.
    return (content:gsub(
      '(\n%.TH CFFLATEXPAND 1) "[^"]*" "import%-citation%-cff [^"]*"',
      '%1 "' .. tagdate .. '" "import-citation-cff ' .. tagname .. '"'))
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

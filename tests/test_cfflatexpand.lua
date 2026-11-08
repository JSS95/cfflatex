-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 import-citation-cff contributors
-- Run with texlua tests/test_cfflatexpand.lua; no test framework is required.
-- CLI and package checks run in separate processes with temporary files.
-- --installed tests a temporary l3build installation; --tds ZIP tests an archive.

local lfs = require("lfs")
local windows = package.config:sub(1, 1) == "\\"
local initial_directory = assert(lfs.currentdir())
local script = arg[0]
if not script:match("^[/\\]") and not script:match("^%a:[/\\]") then
  script = initial_directory .. "/" .. script
end
local root = assert(script:match("^(.*)[/\\]tests[/\\][^/\\]+$"))
local cli = root .. "/cfflatexpand"
local texlua = "texlua"
local installed = arg[1] == "--installed" or arg[1] == "--tds"
local tds = arg[1] == "--tds" and arg[2] or nil
if (#arg > 0 and not installed) or (arg[1] == "--installed" and #arg ~= 1)
  or (arg[1] == "--tds" and (#arg ~= 2 or tds == "")) then
  io.stderr:write("Usage: texlua tests/test_cfflatexpand.lua [--installed | --tds ZIP]\n")
  os.exit(1)
end
if tds and not tds:match("^[/\\]") and not tds:match("^%a:[/\\]") then
  tds = initial_directory .. "/" .. tds
end

local citation = "title: Example Paper\nauthors:\n  - family-names: Doe\n"
local preamble = "\\documentclass{article}\n\\usepackage{import-citation-cff}\n"
  .. "\\includecff{CITATION.cff}\n"
local document = preamble .. "\\title{\\cff{title}}\n\\author{Jane Doe}\n\\date{}\n"
  .. "\\begin{document}\n\\maketitle\n\\end{document}\n"
local rich_citation = [[
title: Research Paper
abstract: A & B
version: 2
date-released: 2026-11-06
keywords: [LaTeX, CFF]
identifiers:
  - type: doi
    value: 10.1/x
nullable: null
empty: []
nested:
  flag: false
which: authors/2/given-names
"custom  field": spaced value
authors:
  - family-names: One
    given-names: Ann
    affiliation: Univ A
    roles: [creator, editor]
    "custom  field": spaced author
  - family-names: Two
    given-names: Ben
    affiliation: 'Univ B;  Univ A;'
  - name: Team & Co
contact:
  - name: Support Team
    email: help_a@example.org
  - family-names: Two
    given-names: Ben
    email: ben@example.org
preferred-citation:
  title: Other Paper
  authors:
    - name: Other Team
  keywords: [only]
]]

local function write_file(filename, text)
  local file = assert(io.open(filename, "wb"))
  assert(file:write(text))
  assert(file:close())
end

local function read_file(filename)
  local file = assert(io.open(filename, "rb"))
  local text = assert(file:read("*a"))
  assert(file:close())
  return text
end

local function equal(actual, expected)
  if actual ~= expected then
    error("expected " .. string.format("%q", expected)
      .. ", got " .. string.format("%q", actual), 2)
  end
end

local function contains(text, expected)
  assert(text:find(expected, 1, true), "missing " .. string.format("%q", expected)
    .. " in " .. string.format("%q", text))
end

local function replace(text, before, after)
  local pieces, cursor = {}, 1
  while true do
    local first, last = text:find(before, cursor, true)
    if not first then
      pieces[#pieces + 1] = text:sub(cursor)
      return table.concat(pieces)
    end
    pieces[#pieces + 1] = text:sub(cursor, first - 1)
    pieces[#pieces + 1] = after
    cursor = last + 1
  end
end

local function mkdir(directory)
  assert(lfs.mkdir(directory))
  return directory
end

local function remove_tree(directory)
  for name in lfs.dir(directory) do
    if name ~= "." and name ~= ".." then
      local filename = directory .. "/" .. name
      if lfs.symlinkattributes(filename, "mode") == "directory" then
        remove_tree(filename)
      else
        assert(os.remove(filename))
      end
    end
  end
  assert(lfs.rmdir(directory))
end

local function names(directory)
  local result = {}
  for name in lfs.dir(directory) do
    if name ~= "." and name ~= ".." then
      result[#result + 1] = name
    end
  end
  table.sort(result)
  return table.concat(result, ",")
end

local function quote(value)
  if windows then
    -- These characters require additional cmd.exe expansion rules and are
    -- not used in the test arguments. Refuse them instead of misquoting.
    assert(not value:find('["%%!\r\n]'), "unsupported cmd.exe argument")
    return '"' .. value .. '"'
  end
  return "'" .. value:gsub("'", "'\\''") .. "'"
end

local function executable(name)
  local separator = windows and ";" or ":"
  for directory in ((os.getenv("PATH") or "") .. separator):gmatch(
    "(.-)" .. separator) do
    local filename = (directory ~= "" and directory or ".") .. "/" .. name
    if lfs.attributes(filename, "mode") == "file"
      or (windows and lfs.attributes(filename .. ".exe", "mode") == "file") then
      return true
    end
  end
  return false
end

-- Allocate a unique directory and release os.tmpname's reservation file on
-- platforms that create one. Remove all fixtures after the suite.
local reservation = os.tmpname()
local temporary = mkdir(reservation .. ".cfflatexpand")
if lfs.attributes(reservation) then
  assert(os.remove(reservation))
end
local cache = mkdir(temporary .. "/tex-cache")
local old_texmfvar, old_texmfcache = os.getenv("TEXMFVAR"), os.getenv("TEXMFCACHE")
local old_texmfhome, old_path = os.getenv("TEXMFHOME"), os.getenv("PATH")
local old_bindir = os.getenv("CFFLATEXPAND_BINDIR")
os.setenv("TEXMFVAR", cache)
os.setenv("TEXMFCACHE", cache)

local function run_command(arguments, directory, redirected_stdout)
  local quoted = {}
  for index, value in ipairs(arguments) do
    quoted[index] = quote(value)
  end
  local stdout = redirected_stdout or temporary .. "/stdout"
  local stderr = temporary .. "/stderr"
  local command = table.concat(quoted, " ") .. " > " .. quote(stdout)
    .. " 2> " .. quote(stderr)
  local previous = assert(lfs.currentdir())
  assert(lfs.chdir(directory))
  local status, _, code = os.execute(command)
  assert(lfs.chdir(previous))
  -- texlua returns a numeric status; also accept standard Lua's return tuple.
  if type(status) ~= "number" then
    status = status == true and 0 or code or 1
  end
  return {
    code = status,
    stdout = redirected_stdout and "" or read_file(stdout),
    stderr = read_file(stderr),
  }
end

local function success(result)
  assert(result.code == 0, "exit status " .. result.code .. ": " .. result.stderr .. result.stdout)
  equal(result.stderr, "")
end

local function failure(result, message)
  assert(result.code ~= 0, "unexpected success: " .. result.stdout)
  equal(result.stdout, "")
  contains(result.stderr, message)
  assert(not result.stderr:find("stack traceback", 1, true), result.stderr)
end

local function expansion(fixture, text, expected)
  write_file(fixture.input, preamble .. text)
  local result = fixture:cli(fixture.input)
  success(result)
  local header = replace(preamble, "\\usepackage{import-citation-cff}", "")
  header = replace(header, "\\includecff{CITATION.cff}", "")
  equal(result.stdout, header .. expected)
end

local function compile(directory, filename)
  local result = run_command({"lualatex", "--no-shell-escape",
    "-interaction=nonstopmode", "-halt-on-error", filename}, directory)
  assert(result.code == 0, result.stdout .. result.stderr)
  assert(lfs.attributes(directory .. "/"
    .. filename:gsub("%.tex$", ".pdf"), "mode") == "file")
end

local passed, failed, skipped, count = 0, 0, 0, 0
local function test(name, body, skip)
  count = count + 1
  if skip then
    skipped = skipped + 1
    io.write("SKIP ", name, ": ", skip, "\n")
    return
  end
  local directory = mkdir(temporary .. "/case-" .. count)
  local fixture = {
    directory = directory,
    input = directory .. "/manuscript.tex",
    cff = directory .. "/CITATION.cff",
  }
  write_file(fixture.input, document)
  write_file(fixture.cff, citation)
  function fixture:cli(...)
    return run_command({texlua, cli, ...}, self.directory)
  end
  local ok, message = xpcall(function() body(fixture) end, debug.traceback)
  if ok then
    passed = passed + 1
    io.write("PASS ", name, "\n")
  else
    failed = failed + 1
    io.stderr:write("FAIL ", name, "\n", message, "\n")
  end
  remove_tree(directory)
end

local ok, message = xpcall(function()
  local texmf, installed_command
  -- l3build install links the command here, a directory that it creates.
  local link_directory = temporary .. "/bin"
  if installed then
    texmf = mkdir(temporary .. "/texmf")
    if tds then
      success(run_command({"unzip", "-q", tds, "-d", texmf}, temporary))
      for _, filename in ipairs({"import-citation-cff.pdf", "README.md", "LICENSE"}) do
        assert(lfs.isfile(texmf .. "/doc/latex/import-citation-cff/" .. filename),
          "TDS archive is missing " .. filename)
      end
    else
      os.setenv("CFFLATEXPAND_BINDIR", link_directory)
      success(run_command({"l3build", "install", "--texmfhome", texmf}, root))
    end
    os.setenv("TEXMFHOME", texmf)
    installed_command = texmf .. "/scripts/import-citation-cff/cfflatexpand"
    equal(read_file(installed_command), read_file(root .. "/cfflatexpand"))
    for _, filename in ipairs({"import-citation-cff.sty", "cfflatex.lua", "cfflatex-data.lua",
      "cfflatex-style-standard.def", "cfflatex-style-authblk.def",
      "cfflatexpand.lua", "cfflatexpand-authors.lua"}) do
      local path = texmf .. "/tex/latex/import-citation-cff/" .. filename
      equal(read_file(path), read_file(root .. "/" .. filename))
      local located = run_command({"kpsewhich", filename}, temporary)
      success(located)
      equal(located.stdout:gsub("[\r\n]+$", ""):gsub("\\", "/"), path:gsub("\\", "/"))
    end
    if windows then
      cli = installed_command
    else
      assert(lfs.attributes(installed_command, "permissions"):sub(3, 3) == "x",
        "installed cfflatexpand is not executable")
      cli = link_directory .. "/cfflatexpand"
      if tds then
        -- An unpacked archive is not linked: link it as a user would.
        mkdir(link_directory)
        assert(lfs.link(installed_command, cli, true))
      end
      assert(lfs.symlinkattributes(cli, "mode") == "link" and lfs.readlink(cli) == installed_command,
        "the command is not linked to " .. cli)
      os.setenv("PATH", link_directory .. ":" .. old_path)
    end
    io.write(tds and "Testing the TDS archive\n" or "Testing l3build install\n")
  end

  test("stdout from another directory", function(f)
    local result = f:cli(f.input)
    success(result)
    local expected = replace(document, "\\usepackage{import-citation-cff}", "")
    expected = replace(expected, "\\includecff{CITATION.cff}", "")
    equal(result.stdout, replace(expected, "\\cff{title}", "Example Paper"))
    equal(read_file(f.input), document)
  end)

  test("executable entry point", function(f)
    success(run_command({installed and "cfflatexpand" or cli, f.input}, f.directory))
  end, windows and "POSIX shebang" or nil)

  test("output options and stdout alias", function(f)
    local output = f.directory .. "/submission.tex"
    for _, arguments in ipairs({{"--output", output}, {"-o", output},
      {"--output=" .. output}}) do
      write_file(output, "old output")
      local result = f:cli(f.input, table.unpack(arguments))
      success(result)
      equal(result.stdout, "")
      contains(read_file(output), "\\title{Example Paper}")
      equal(names(f.directory), "CITATION.cff,manuscript.tex,submission.tex")
    end
    local result = f:cli(f.input, "-o", "-")
    success(result)
    contains(result.stdout, "\\title{Example Paper}")
  end)

  test("shell redirection", function(f)
    local output = f.directory .. "/submission.tex"
    success(run_command({texlua, cli, f.input}, f.directory, output))
    contains(read_file(output), "\\title{Example Paper}")
  end)

  test("help, version, and option errors", function(f)
    for _, pair in ipairs({{"--help", "--output"}, {"--version", "import-citation-cff"}}) do
      local result = f:cli(pair[1])
      success(result)
      contains(result.stdout, pair[2])
    end
    for _, arguments in ipairs({{}, {"--wat"}, {"-o"}, {"--output="},
      {f.input, f.input}, {f.input, "-o", "a", "-o", "b"}}) do
      failure(f:cli(table.unpack(arguments)), "cfflatexpand:")
    end
  end)

  test("end of options", function(f)
    assert(os.rename(f.input, f.directory .. "/-manuscript.tex"))
    success(f:cli("--", "-manuscript.tex"))
  end)

  test("CFF paths relative to the input directory", function(f)
    local folder = mkdir(f.directory .. "/papers with spaces")
    local manuscript = folder .. "/paper's draft.tex"
    write_file(manuscript, replace(document, "CITATION.cff", "data file.cff"))
    write_file(folder .. "/data file.cff", replace(citation, "Example Paper", "Right"))
    local result = f:cli(manuscript)
    success(result)
    contains(result.stdout, "\\title{Right}")
  end)

  test("source selection and literal braces", function(f)
    write_file(f.cff, citation .. "preferred-citation:\n  title: Selected\n"
      .. "  authors:\n    - name: Research Team\n")
    for _, options in ipairs({"source=preferred-citation", "source={preferred-citation}",
      "source=preferred-citation,", " source = preferred-citation "}) do
      write_file(f.input, replace(document, "\\includecff{", "\\includecff[" .. options .. "]{"))
      local result = f:cli(f.input)
      success(result)
      contains(result.stdout, "\\title{Selected}")
    end
  end)

  test("native escaping, Unicode, and multiline values", function(f)
    write_file(f.cff, "title: |\n  Résumé 한글: \\ {x} % # $ & _ ~ ^\n  next line\n"
      .. "authors:\n  - name: Research Team\n")
    local result = f:cli(f.input)
    success(result)
    contains(result.stdout, [[\title{Résumé 한글: \textbackslash{} \{x\} \% \# \$ \& \_ ]]
      .. [[\textasciitilde{} \textasciicircum{} next line}]])
    for _, value in ipairs({"true", "42", '"   "'}) do
      write_file(f.cff, "title: " .. value .. "\nauthors:\n  - name: Team\n")
      success(f:cli(f.input))
    end
  end)

  test("nested groups, comments, escaped symbols, and verbatim", function(f)
    local opaque = "% \\cffsetauthors \\includecff{missing} {\n"
      .. [[\verb|\cff{title}%{| \verb*+\input{missing}}+]] .. "\n"
      .. "\\begin{verbatim}\n\\cff{title} { % \\newcommand\n\\end{verbatim}\n"
      .. "\\begin{Verbatim}\n\\cff{title} }\n\\end{Verbatim}\n"
      .. "\\begin{lstlisting}[language=TeX]\n\\cff{title}\n\\end{lstlisting}\n"
      .. "\\begin{minted}{tex}\n\\cff{title}\n\\end{minted}\n"
      .. [[Escaped \% \{ \} \\cff{title}]] .. "\n"
    write_file(f.input, preamble .. "\\title{{A {\\cff{title}}}}\n"
      .. "\\begin{document}\n" .. opaque .. "\\end{document}\n")
    local result = f:cli(f.input)
    success(result)
    contains(result.stdout, "\\title{{A {Example Paper}}}")
    contains(result.stdout, opaque)
  end)

  test("comments between metadata command arguments", function(f)
    local text = replace(document, "\\includecff{CITATION.cff}",
      "\\includecff% comment with }\n{CITA% another comment\n  TION.cff}")
    write_file(f.input, replace(text, "\\cff{title}", "\\cff% comment\n{ti% comment\n  tle}"))
    local result = f:cli(f.input)
    success(result)
    contains(result.stdout, "\\title{Example Paper}")
  end)

  test("mixed package lists preserve other packages and comments", function(f)
    for _, pair in ipairs({{"import-citation-cff,fontenc", "fontenc"}, {"fontenc,import-citation-cff", "fontenc"},
      {"fontenc, import-citation-cff, hyperref", "fontenc,  hyperref"},
      {"fontenc,% keep\n import-citation-cff, hyperref", "fontenc,% keep\n  hyperref"}}) do
      write_file(f.input, replace(document, "\\usepackage{import-citation-cff}",
        "\\usepackage{" .. pair[1] .. "}"))
      local result = f:cli(f.input)
      success(result)
      contains(result.stdout, "\\usepackage{" .. pair[2] .. "}")
    end
    write_file(f.input, replace(document, "\\usepackage{import-citation-cff}",
      "\\RequirePackage[check=false]{import-citation-cff}[2026/11/06]"))
    success(f:cli(f.input))
  end)

  test("control word boundaries survive replacement", function(f)
    write_file(f.input, replace(document, "\\title{\\cff{title}}", "\\title{\\relax\\cff{title}}"))
    local result = f:cli(f.input)
    success(result)
    contains(result.stdout, "\\title{\\relax Example Paper}")
  end)

  test("CRLF bytes and Unicode error columns", function(f)
    local source = replace(document, "\n", "\r\n")
    write_file(f.input, source)
    local result = f:cli(f.input)
    success(result)
    local expected = replace(source, "\\usepackage{import-citation-cff}", "")
    expected = replace(expected, "\\includecff{CITATION.cff}", "")
    equal(result.stdout, replace(expected, "\\cff{title}", "Example Paper"))
    write_file(f.input, replace(preamble .. "한글 \\cffemit", "\n", "\r\n"))
    failure(f:cli(f.input), f.input .. ":4:4:")
  end)

  test("invalid literal options and filenames", function(f)
    for _, pair in ipairs({{"{import-citation-cff}", "[unknown=true]{import-citation-cff}"},
      {"\\includecff{", "\\includecff[unknown=key]{"},
      {"\\includecff{", "\\includecff[source=a,source=b]{"},
      {"{CITATION.cff}", "{}"}, {"{CITATION.cff}", "{\\filename}"}}) do
      write_file(f.input, replace(document, pair[1], pair[2]))
      failure(f:cli(f.input), f.input .. ":")
    end
  end)

  test("invalid CFF and sources report the include location", function(f)
    for _, pair in ipairs({{"title: Missing authors\n", "authors"},
      {"authors:\n  - name: Team\n", "title"},
      {"title: [wrong]\nauthors:\n  - name: Team\n", "title"},
      {citation .. "contact: []\n", "contact"},
      {"title: Bad\nauthors:\n  - name: Team\n    affiliation: 'A;;B'\n", "affiliation"},
      {"title: [broken\n", "cannot read CFF"}}) do
      write_file(f.cff, pair[1])
      local result = f:cli(f.input)
      failure(result, pair[2])
      contains(result.stderr, f.input .. ":3:1:")
    end
    write_file(f.cff, citation)
    write_file(f.input, replace(document, "\\includecff{", "\\includecff[source=absent]{"))
    failure(f:cli(f.input), "has no 'absent'")
    write_file(f.input, document)
    assert(os.remove(f.cff))
    failure(f:cli(f.input), "cannot read CFF")
  end)

  test("commands the package does not define are copied unchanged", function(f)
    for _, construct in ipairs({[[\cffunknown{title}]], [[\input{other}]],
      [[\def\foo{bar}]], [[\newcommand{\foo}{bar}]], [[\providecommand\foo{bar}]],
      [[\iffalse x\else y\fi]], [[\ifx a b\fi]], [[\let\ifdraft\iftrue]], [[\newif\ifdraft]],
      [[\ifnum1=1 x\else\ifx a b y\else z\fi\fi]], [[\fi]], [[\else]], [[\catcode1=2]],
      [[\csname cff\endcsname{title}]], [[\uppercase{x}]], [[^^5ccff{title}]],
      [[\makeatletter\def\cff@x{}\makeatother]],
      [[\ExplSyntaxOn\cs_new:Npn \cff_x:n #1 {}\ExplSyntaxOff]]}) do
      write_file(f.input, replace(document, "\\title{\\cff{title}}", construct))
      local result = f:cli(f.input)
      success(result)
      contains(result.stdout, "\n" .. construct .. "\n")
    end
  end)

  test("metadata commands inside other commands are expanded", function(f)
    write_file(f.input, replace(document, "\\title{\\cff{title}}",
      [[\newcommand{\paper}{\cff{title}}\iffalse\cff{title}\fi\def\x{\cffcount{authors}}]]))
    local result = f:cli(f.input)
    success(result)
    contains(result.stdout, [[\newcommand{\paper}{Example Paper}\iffalse Example Paper\fi\def\x{1}]])
  end)

  test("package commands that cannot be converted fail without output", function(f)
    for _, construct in ipairs({[[\cffauthornames]], [[\cffemit{x}]], [[\cffrenderauthor]],
      [[\cffrenderaffiliation]], [[\cffdeclareauthorstyle{x}{}]]}) do
      write_file(f.input, replace(document, "\\title{\\cff{title}}", construct))
      failure(f:cli(f.input), f.input .. ":4:1:")
    end
  end)

  test("verbatim arguments and short verbatim are copied unchanged", function(f)
    local opaque = [[\Verb|\cff{title}| \Verb*+\cff+ \lstinline[language=TeX]{\cff{title}}]]
      .. [[ \mintinline{latex}{\cff{a}} \mintinline[x]{tex}|\cff| \path|\cff|]]
      .. [[ \url{https://example.org/%7E\cff{title}}]]
    write_file(f.input, replace(document, "\\maketitle",
      opaque .. "\n\\href{https://example.org/%20}{\\cff{title}}"))
    local result = f:cli(f.input)
    success(result)
    contains(result.stdout, opaque .. "\n\\href{https://example.org/%20}{Example Paper}")
    local short = "\\MakeShortVerb{\\|}\n|\\cff{title}|\n\\DeleteShortVerb\\|\n|\\cff{title}|\n"
    write_file(f.input, replace(document, "\\maketitle\n", short))
    result = f:cli(f.input)
    success(result)
    contains(result.stdout, "\\MakeShortVerb{\\|}\n|\\cff{title}|\n\\DeleteShortVerb\\|\n"
      .. "|Example Paper|\n")
  end)

  test("l3doc short verbatim and command lists are copied unchanged", function(f)
    write_file(f.input, replace(preamble, "{article}", "{l3doc}")
      .. "\\title{|\\cff{title}|}\n\\begin{document}\n"
      .. [[|\cff{title}| "\cffforeachauthor" \cff{title}]] .. "\n"
      .. "\\begin{function}[EXP]{\\cff,\n  \\cffauthorindex}\n\\cff{title}\n\\end{function}\n"
      .. "\\end{document}\n")
    local result = f:cli(f.input)
    success(result)
    -- l3doc makes | a short verbatim character only in the document body.
    contains(result.stdout, "\\title{|Example Paper|}")
    contains(result.stdout, [[|\cff{title}| "\cffforeachauthor" Example Paper]])
    contains(result.stdout, "\\begin{function}[EXP]{\\cff,\n  \\cffauthorindex}\n"
      .. "Example Paper\n\\end{function}")
  end)

  test("reloaded, nested, or late CFF includes are rejected", function(f)
    for _, pair in ipairs({
      {replace(document, "\\title{", "\\includecff{CITATION.cff}\n\\title{"), "only once"},
      {replace(document, "\\includecff{CITATION.cff}", "{\\includecff{CITATION.cff}}"), "top level"},
      {replace(document, "\\includecff{CITATION.cff}\n", ""), "call \\includecff"},
      {replace(document, "\\usepackage{import-citation-cff}\n", ""), "load import-citation-cff"},
      {replace(document, "{import-citation-cff}", "{import-citation-cff,import-citation-cff}"), "only once"}}) do
      write_file(f.input, pair[1])
      failure(f:cli(f.input), pair[2])
    end
    write_file(f.input, replace(preamble, "\\includecff", "\\begin{document}\n\\includecff"))
    failure(f:cli(f.input), "top level")
  end)

  test("malformed source reports a location without output", function(f)
    for _, suffix in ipairs({[[\title{\cff{title}]], [[\verb|unclosed]], "}",
      "\\begin{verbatim}\n", [[\cff]], [[\usepackage[check=false]]}) do
      write_file(f.input, preamble .. suffix)
      failure(f:cli(f.input), f.input .. ":")
    end
  end)

  test("failed conversion preserves the destination", function(f)
    write_file(f.input, replace(document, "\\maketitle", "\\cffemit"))
    local output = f.directory .. "/submission.tex"
    failure(f:cli(f.input, "--output", output), "unsupported")
    assert(not lfs.attributes(output))
    write_file(output, "old output")
    failure(f:cli(f.input, "-o", output), "unsupported")
    equal(read_file(output), "old output")
  end)

  test("input and output aliases are rejected", function(f)
    local aliases = {f.input, f.directory .. "/./manuscript.tex"}
    if not windows then
      local symlink, hardlink = f.directory .. "/alias.tex", f.directory .. "/hardlink.tex"
      assert(lfs.link(f.input, symlink, true))
      assert(lfs.link(f.input, hardlink))
      aliases[#aliases + 1], aliases[#aliases + 2] = symlink, hardlink
    end
    for _, alias in ipairs(aliases) do
      failure(f:cli(f.input, "--output", alias), "overwrite the input")
      equal(read_file(f.input), document)
    end
  end)

  test("write errors clean up temporary output", function(f)
    local output = mkdir(f.directory .. "/submission.tex")
    failure(f:cli(f.input, "-o", output), "cfflatexpand:")
    equal(lfs.attributes(output, "mode"), "directory")
    equal(names(f.directory), "CITATION.cff,manuscript.tex,submission.tex")
  end)

  test("stdout flush errors fail", function(f)
    failure(run_command({texlua, cli, f.input}, f.directory, "/dev/full"), "cfflatexpand:")
  end, not lfs.attributes("/dev/full") and "/dev/full is required" or nil)

  test("metadata-free source and ignored trailing text", function(f)
    local plain = "\\documentclass{article}\nText % \\cff{title}\n"
    write_file(f.input, plain)
    local result = f:cli(f.input)
    success(result)
    equal(result.stdout, plain)
    local trailing = "\\cff{unsupported} {\\input{ignored}\n"
    write_file(f.input, document .. trailing)
    result = f:cli(f.input)
    success(result)
    equal(result.stdout:sub(-#trailing), trailing)
  end)

  test("output compiles without import-citation-cff or CFF files", function(f)
    local output = mkdir(f.directory .. "/submission")
    success(f:cli(f.input, "-o", output .. "/paper.tex"))
    assert(os.remove(f.input))
    assert(os.remove(f.cff))
    write_file(output .. "/import-citation-cff.sty",
      "\\errmessage{Export unexpectedly requires import-citation-cff}\\endinput\n")
    compile(output, "paper.tex")
  end, not executable("lualatex") and "lualatex is required" or nil)

  test("generic paths, scalar kinds, and collection lengths", function(f)
    write_file(f.cff, rich_citation)
    expansion(f, [[\cff{title}|\cff{abstract}|\cff{version}|\cff{date-released}|]]
      .. [[\cff{keywords/2}|\cff{identifiers/1/value}|\cff{nested/flag}|]]
      .. [[\cff{preferred-citation/title}|\cffcount{authors},\cffcount{keywords},]]
      .. [[\cffcount{preferred-citation/authors}]],
      [[Research Paper|A \& B|2|2026-11-06|CFF|10.1/x|false|Other Paper|3,2,1]])
    expansion(f, [[\cff{custom  field}|\cffauthor{1}{custom  field}]],
      "spaced value|spaced author")
  end)

  test("missing paths and nulls", function(f)
    write_file(f.cff, rich_citation)
    expansion(f, [=[[\cff{absent}][\cff{nullable}][\cff{authors/99/name}]]=]
      .. [[[\cff{ title }]|\cffcount{absent},\cffcount{nullable}]],
      "[][][][]|0,0")
  end)

  test("collections are not values and scalars are not lists", function(f)
    write_file(f.cff, rich_citation)
    for _, pair in ipairs({{[[\cff{authors}]], "not a value"},
      {[[\cff{authors/1}]], "not a value"}, {[[\cff{empty}]], "not a value"},
      {[[\cffcount{title}]], "not a list"}, {[[\cffcount{nested}]], "not a list"},
      {[[\cffcount{authors/1}]], "not a list"}}) do
      write_file(f.input, preamble .. pair[1])
      failure(f:cli(f.input), pair[2])
    end
  end)

  test("flattened paths keep TeX's separate field and kind lookups", function(f)
    write_file(f.cff, citation .. '"nested/value": scalar\nnested:\n  value: [one, two]\n')
    expansion(f, [[\cff{nested/value}|\cffcount{nested/value}]], "scalar|2")
  end)

  test("named author, contact, and affiliation accessors", function(f)
    write_file(f.cff, rich_citation)
    expansion(f, [[\cffauthor{1}{given-names}|\cffauthor{3}{name}|]]
      .. [[[\cffauthor{3}{given-names}][\cffcontact{1}{given-names}]|]]
      .. [[\cffcontact{1}{email}|\cffauthoraffiliationcount{2}|]]
      .. [[\cffauthoraffiliationcount{3}|\cffauthoraffiliation{2}{1}|]]
      .. [[\cffconvertaffiliationindex{2}{1}|\cffaffiliationcount|\cffaffiliation{1}]],
      [[Ann|Team \& Co|[][]|help\_a@example.org|2|0|Univ B|2|2|Univ A]])
    expansion(f, [[\cffauthor{2}{affiliation}|\cffauthor{2}{affiliation-names/1}|]]
      .. [[\cffauthor{2}{affiliation-indices/2}|\cff{affiliations/1}]],
      "Univ B;  Univ A;|Univ B|1|")
  end)

  test("decimal integer expressions and computed indices", function(f)
    write_file(f.cff, rich_citation)
    expansion(f, [[\cffauthor{1+1}{given-names}|\cffauthor{-(-2)}{given-names}|]]
      .. [[\cffauthor{3/2}{given-names}|\cffauthor{(-3)/(-2)}{given-names}|]]
      .. [[\cffauthor{(2*3-1)/2}{name}|\cffauthor{\cffcount{authors}-1}{given-names}|]]
      .. [[\cffauthoraffiliation{1+1}{\cffauthoraffiliationcount{2}}]],
      [[Ben|Ben|Ben|Ben|Team \& Co|Ben|Univ A]])
  end)

  test("invalid and overflowing integer expressions", function(f)
    for _, value in ipairs({"0", "2", "-1", "", "1.5", "0x1", "1/0", "(1", "1 1",
      "2147483648", "2147483647*2", "1;invalid()", "1\n\n+1",
      [[\numexpr1+1\relax]]}) do
      write_file(f.input, preamble .. "\\cffauthor{" .. value .. "}{name}")
      failure(f:cli(f.input), f.input .. ":4:")
    end
  end)

  test("all named indices are checked", function(f)
    write_file(f.cff, rich_citation)
    for _, pair in ipairs({{[[\cffauthor{4}{name}]], "author"},
      {[[\cffcontact{3}{name}]], "contact"},
      {[[\cffaffiliation{3}]], "affiliation"},
      {[[\cffauthoraffiliationcount{0}]], "author"},
      {[[\cffauthoraffiliation{3}{1}]], "affiliation"},
      {[[\cffconvertaffiliationindex{2}{3}]], "affiliation"},
      {[[\cffforeachauthoraffiliation{4}{}]], "author"}}) do
      write_file(f.input, preamble .. pair[1])
      failure(f:cli(f.input), pair[2] .. " index")
    end
  end)

  test("metadata accessors require a loaded citation", function(f)
    for _, command in ipairs({[[\cff{title}]], [[\cffcount{authors}]],
      [[\cffauthor{1}{name}]], [[\cffcontact{1}{email}]], [[\cffaffiliationcount]],
      [[\cffaffiliation{1}]], [[\cffauthoraffiliationcount{1}]],
      [[\cffauthoraffiliation{1}{1}]], [[\cffconvertaffiliationindex{1}{1}]],
      [[\cffforeachauthor{}]], [[\cffforeachcontact{}]], [[\cffforeachaffiliation{}]],
      [[\cffforeachauthoraffiliation{1}{}]]}) do
      write_file(f.input, "\\usepackage{import-citation-cff}\n" .. command)
      failure(f:cli(f.input), "call \\includecff")
    end
  end)

  test("author loops and metadata accessors inside paths", function(f)
    write_file(f.cff, rich_citation)
    expansion(f, [[\cffforeachauthor{[\cffauthorindex:\cff{authors/\cffauthorindex/given-names}]]
      .. [[\cff{authors/\cffauthorindex/name};\cffcount{authors/\cffauthorindex/roles}]}|]]
      .. [[\cff{\cff{which}}|\cff{authors/\cffcount{authors}/name}]],
      [[[1:Ann;2][2:Ben;0][3:Team \& Co;0]|Ben|Team \& Co]])
  end)

  test("affiliation and contact loops", function(f)
    write_file(f.cff, rich_citation)
    expansion(f, [[\cffforeachaffiliation{\cffaffiliationindex=]]
      .. [[\cffaffiliation{\cffaffiliationindex};}|]]
      .. [[\cffforeachauthoraffiliation{2}{\cffauthoraffiliationindex=]]
      .. [[\cffauthoraffiliation{2}{\cffauthoraffiliationindex}/]]
      .. [[\cffconvertaffiliationindex{2}{\cffauthoraffiliationindex};}|]]
      .. [[\cffforeachcontact{\cffcontactindex=\cffcontact{\cffcontactindex}{email};}]],
      [[1=Univ A;2=Univ B;|1=Univ B/2;2=Univ A/1;|]]
      .. [[1=help\_a@example.org;2=ben@example.org;]])
  end)

  test("nested loops restore every enclosing index", function(f)
    write_file(f.cff, rich_citation)
    expansion(f, [[\cffforeachauthor{\cffauthorindex(]]
      .. [[\cffforeachauthor{\cffauthorindex})\cffauthorindex;}]],
      "1(123)1;2(123)2;3(123)3;")
    expansion(f, [[\cffforeachauthor{\cffauthorindex(]]
      .. [[\cffforeachauthoraffiliation{\cffauthorindex}{\cffauthoraffiliationindex:]]
      .. [[\cffauthoraffiliation{\cffauthorindex}{\cffauthoraffiliationindex};})}]],
      "1(1:Univ A;)2(1:Univ B;2:Univ A;)3()")
    for _, pair in ipairs({{"cffforeachaffiliation", "cffaffiliationindex"},
      {"cffforeachcontact", "cffcontactindex"},
      {"cffforeachauthoraffiliation{2}", "cffauthoraffiliationindex"}}) do
      local loop = "\\" .. pair[1]
      local index = "\\" .. pair[2]
      expansion(f, loop .. "{" .. index .. "(" .. loop .. "{" .. index .. "})"
        .. index .. ";}", "1(12)1;2(12)2;")
    end
  end)

  test("empty loops do not execute their bodies", function(f)
    expansion(f, [[A\cffforeachcontact{\cffcontact{99}{email}\cffsetauthors}]]
      .. [[B\cffforeachaffiliation{\cffaffiliation{99}}]]
      .. [[C\cffforeachauthoraffiliation{1}{\cffauthoraffiliation{1}{99}}D]], "ABCD")
  end)

  test("loop indices are local to the matching loop", function(f)
    for _, pair in ipairs({{"cffforeachauthor", "cffauthorindex"},
      {"cffforeachaffiliation", "cffaffiliationindex"},
      {"cffforeachauthoraffiliation{1}", "cffauthoraffiliationindex"},
      {"cffforeachcontact", "cffcontactindex"}}) do
      write_file(f.input, preamble .. "\\" .. pair[2])
      failure(f:cli(f.input), "only valid inside")
      write_file(f.input, preamble .. "\\" .. pair[1] .. "{}\\" .. pair[2])
      failure(f:cli(f.input), "only valid inside")
    end
  end)

  test("zero-argument getters discard only ignored whitespace", function(f)
    write_file(f.cff, rich_citation)
    expansion(f, "\\cffaffiliationcount \tNext|\\cffaffiliationcount\n  Next|"
      .. "\\cffaffiliationcount\n\nNext|\\cffaffiliationcount% keep\n  Next",
      "2Next|2Next|2%\n\nNext|2% keep\n  Next")
    expansion(f, [[\cffforeachauthor{\cff{authors/\cffauthorindex /given-names};}]],
      "Ann;Ben;;")
  end)

  test("loop bodies preserve comments and verbatim", function(f)
    write_file(f.cff, rich_citation)
    local body = [[\verb|\cffauthorindex|\cffauthorindex;% keep]] .. "\n"
    expansion(f, "\\cffforeachauthor{" .. body .. "}",
      [[\verb|\cffauthorindex|1;% keep]] .. "\n"
      .. [[\verb|\cffauthorindex|2;% keep]] .. "\n"
      .. [[\verb|\cffauthorindex|3;% keep]] .. "\n")
  end)

  test("numeric conditionals remain TeX with expanded operands", function(f)
    write_file(f.cff, rich_citation)
    expansion(f, [[\cffforeachauthor{\ifnum\cffauthorindex>1 \and\fi]]
      .. [[\cffauthor{\cffauthorindex}{given-names}}]]
      .. [[\ifodd\cffcount{authors} odd\else even\fi]],
      [[\ifnum1>1 \and\fi Ann\ifnum2>1 \and\fi Ben\ifnum3>1 \and\fi]]
      .. [[\ifodd3 odd\else even\fi]])
  end)

  test("numeric conditions cannot hide CFF loads or cross loop boundaries", function(f)
    for _, source in ipairs({
      "\\ifnum1=1 " .. preamble .. "\\fi",
      "\\usepackage{import-citation-cff}\n\\ifodd1 \\includecff{CITATION.cff}\\fi",
      preamble .. [[\cffforeachauthor{\ifnum\cffauthorindex>1 x}]],
      preamble .. [[\ifnum1=1 x]],
    }) do
      write_file(f.input, source)
      failure(f:cli(f.input), f.input .. ":")
    end
  end)

  test("loop errors keep the original source location", function(f)
    write_file(f.input, preamble .. "\\cffforeachauthor{\n\\cffauthor{99}{name}\n}")
    failure(f:cli(f.input), f.input .. ":5:1:")
    for _, source in ipairs({[[\cffforeachauthor{\cff}]],
      [[\cffforeachauthor{\cffauthor{1}}]], [[\cff{authors/\cffauthorindex/name}]]}) do
      write_file(f.input, preamble .. source)
      failure(f:cli(f.input), f.input .. ":4:")
    end
  end)

  test("included files are copied unchanged, not read", function(f)
    write_file(f.directory .. "/chapter.tex", "\\cff{title}")
    for _, command in ipairs({[[\input{chapter}]], [[\include{chapter}]],
      [[\includeonly{chapter}]]}) do
      write_file(f.input, preamble .. command .. "\n")
      local result = f:cli(f.input)
      success(result)
      contains(result.stdout, "\n" .. command .. "\n")
    end
  end)

  test("standard authors and author names use literal metadata", function(f)
    write_file(f.cff, rich_citation)
    write_file(f.input, preamble .. [[\cffsetauthors
\title{\cff{title}}
\begin{document}\cffauthornames\end{document}
]])
    local result = f:cli(f.input)
    success(result)
    contains(result.stdout, [[\author {Ann\nobreakspace One\and Ben\nobreakspace Two]])
    contains(result.stdout, [[\@cfflatexpand@thanks{E-mail: ben@example.org}]])
    contains(result.stdout, [[Ann\nobreakspace One, Ben\nobreakspace Two, \nobreakspace]])
    assert(not result.stdout:find("\\affil", 1, true))
    assert(not result.stdout:find("\\cffsetauthors", 1, true))
    assert(not result.stdout:find("\\cffauthornames", 1, true))
    equal(names(f.directory), "CITATION.cff,manuscript.tex")
  end)

  test("authblk affiliations, mark formats, and separators", function(f)
    write_file(f.cff, rich_citation)
    for _, marks in ipairs({{"alph", "a", "b"}, {"Alph", "A", "B"},
      {"arabic", "1", "2"}, {"roman", "i", "ii"}, {"Roman", "I", "II"}}) do
      write_file(f.input, preamble .. "\\cffsetauthors[style=authblk,contact={},"
        .. "affiliation-mark=" .. marks[1] .. ",separator={/}]")
      local result = f:cli(f.input)
      success(result)
      contains(result.stdout, "\\author [{" .. marks[3] .. "/" .. marks[2]
        .. "}]{Ben\\nobreakspace Two}")
      contains(result.stdout, "\\affil [" .. marks[2] .. "]{Univ A}")
      contains(result.stdout, "\\affil [" .. marks[3] .. "]{Univ B}")
      assert(not result.stdout:find("thanks", 1, true))
    end
  end)

  test("class templates, contact matches, and repeated notes", function(f)
    write_file(f.cff, rich_citation)
    write_file(f.input, preamble .. [=[\cffsetauthors[
style=authblk,name={\textsc{#1{given-names}#1{family-names}#1{name}}},
author={\journalAuthor{#1}{#2}},affiliation={\journalAffil{#1}{#2}},
contact={Contact: \texttt{#1{email}}},
note={1+1}{First \cff{title}},note={\cffcount{authors}-1}{Second},
note={3}{Team note}]
\hypersetup{pdfauthor={\cffauthornames}}
]=])
    local result = f:cli(f.input)
    success(result)
    contains(result.stdout, [[\journalAuthor {a}{\textsc {AnnOne}}]])
    contains(result.stdout, [[\journalAuthor {b,a,\@cfflatexpand@thanks{Contact: \texttt {ben@example.org}},]])
    contains(result.stdout, [[\@cfflatexpand@thanks{First Research Paper},\@cfflatexpand@thanks{Second}]])
    contains(result.stdout, [[\journalAffil {b}{Univ B}]])
    contains(result.stdout, [[\textsc {Team \& Co}]])
    assert(not result.stdout:find("help", 1, true), "non-author contact was rendered")
    assert(not result.stdout:find("__cfflatex", 1, true))
    assert(not result.stdout:find("\\protect \\cff", 1, true))
  end)

  test("entity contacts and disabled affiliations", function(f)
    write_file(f.cff, "title: Test\nauthors:\n  - name: Team\n    affiliation: Lab\n"
      .. "contact:\n  - name: Team\n    email: one@example.org\n"
      .. "  - name: Team\n    email: two@example.org\n")
    write_file(f.input, preamble .. [=[\cffsetauthors[style=authblk,affiliation={},name={#1{name}}]]=])
    local result = f:cli(f.input)
    success(result)
    contains(result.stdout, [[\author [{{}\@cfflatexpand@thanks{E-mail: one@example.org},]])
    contains(result.stdout, [[\@cfflatexpand@thanks{E-mail: two@example.org}}]{Team}]])
    assert(not result.stdout:find("\\affil", 1, true))
  end)

  test("document-local plugins run hooks and custom renderers during export", function(f)
    local source = mkdir(f.directory .. "/source files")
    local input = source .. "/paper.tex"
    write_file(source .. "/CITATION.cff", rich_citation)
    write_file(source .. "/cfflatex-style-journal.def", [[
\cffdeclareauthorstyle{journal}{
requires={cfflatex-nonexistent},
validate={\PackageError{journal}{Validation must not run during export}{}},
name={#1{family-names}},contact={},affiliation-mark=Roman,
begin={\cffemit{\journalBegin{\cff{title}}}},
prepare-author={\cffemit{\journalIndex{#1}}},
author-code={\cffemit{\journalAuthor{#1}{#2}}},
affiliation-code={\cffemit{\journalAffiliation{#1}{#2}}},
render={
  \cffforeachaffiliation{\cffrenderaffiliation{\cffaffiliationindex}}
  \cffforeachauthor{\cffrenderauthor{\cffauthorindex}}},
end={\cffemit{\journalEnd}},
}
]])
    write_file(input, preamble .. [[\cffsetauthors[style=journal]
\hypersetup{pdfauthor={\cffauthornames}}
]])
    local result = f:cli(input)
    success(result)
    contains(result.stdout, [[\journalBegin {Research Paper}]])
    contains(result.stdout, [[\journalIndex {2}]])
    contains(result.stdout, [[\journalAffiliation {II}{Univ B}]])
    contains(result.stdout, [[\journalAuthor {II,I}{Two}]])
    contains(result.stdout, [[\journalEnd]])
    contains(result.stdout, [[\hypersetup{pdfauthor={One, Two, }}]])
    assert(result.stdout:find("\\journalAffiliation", 1, true)
      < result.stdout:find("\\journalAuthor", 1, true), "renderer order was lost")
    assert(not result.stdout:find("\\cff", 1, true), "export retained a plugin command")
    equal(names(source), "CITATION.cff,cfflatex-style-journal.def,paper.tex")
    -- User overrides win even when they precede style=.
    write_file(input, preamble .. [=[\cffsetauthors[name={#1{given-names}},style=journal]]=])
    result = f:cli(input)
    success(result)
    contains(result.stdout, [[\journalAuthor {II,I}{Ben}]])
  end)

  test("plugins are also found on the caller's TeX input search path", function(f)
    local plugins = mkdir(f.directory .. "/plugins")
    write_file(plugins .. "/cfflatex-style-searchpath.def", [[
\cffdeclareauthorstyle{searchpath}{
  contact={},name={#1{family-names}},author={\journalAuthor{#2}}}
]])
    write_file(f.input, preamble .. [=[\cffsetauthors[style=searchpath]]=])
    local previous = os.getenv("TEXINPUTS")
    os.setenv("TEXINPUTS", plugins .. (windows and ";" or ":") .. (previous or ""))
    local worked, result = pcall(function() return f:cli(f.input) end)
    os.setenv("TEXINPUTS", previous)
    assert(worked, result)
    success(result)
    contains(result.stdout, [[\journalAuthor {Doe}]])
  end)

  test("the style option of the package is the default author style", function(f)
    write_file(f.cff, rich_citation)
    -- Check keys are part of the style but do not affect the export.
    write_file(f.directory .. "/cfflatex-style-titleblock.def", [[
\cffdeclareauthorstyle{titleblock}{
  contact={},name={#1{family-names}},author={\journalAuthor{#2}},
  check-fields={title,authors,abstract},
  check-region={hooks={env/@twocolumnfalse/begin}{env/@twocolumnfalse/end},document},
}
]])
    local header = replace(preamble, "{import-citation-cff}", "[check, style=titleblock]{import-citation-cff}")
    write_file(f.input, header .. "\\cffsetauthors\n")
    local result = f:cli(f.input)
    success(result)
    contains(result.stdout, [[\journalAuthor {One}]])
    contains(result.stdout, [[\journalAuthor {Two}]])
    assert(not result.stdout:find("titleblock", 1, true), "export retained the package option")
    -- style= of \cffsetauthors overrides the option of the package.
    write_file(f.input, header .. "\\cffsetauthors[style=standard]\n")
    result = f:cli(f.input)
    success(result)
    contains(result.stdout, [[\author {Ann\nobreakspace One\and Ben\nobreakspace Two]])
    for _, pair in ipairs({{"style=../titleblock", "invalid author style name"},
      {"style=titleblock,unknown", "style=NAME options are supported"},
      {"style={titleblock}", "without TeX commands"}}) do
      write_file(f.input, replace(preamble, "{import-citation-cff}", "[" .. pair[1] .. "]{import-citation-cff}"))
      local rejected = f:cli(f.input)
      failure(rejected, pair[2])
      contains(rejected.stderr, f.input .. ":2:")
    end
  end)

  test("the rsc style exports the commands of its title block", function(f)
    write_file(f.cff, rich_citation)
    local header = replace(preamble, "{import-citation-cff}", "[style=rsc]{import-citation-cff}")
    write_file(f.input, header .. [=[\cffsetauthors[name={#1{family-names}#1{name}},note={1}{Equal.}]
\begin{document}
\begin{@twocolumnfalse}\cff{title}\par\rscauthors\end{@twocolumnfalse}
\rscfootnotes
\end{document}
]=])
    local result = f:cli(f.input)
    success(result)
    contains(result.stdout, [[\newcommand \rscauthors {One,\textit {$^{a\ddag }$} ]]
      .. [[Two,\textit {$^{\ast ba}$} and Team \& Co}]])
    contains(result.stdout, [[\newcommand \rscfootnotes {]]
      .. [[\footnotetext {\textit {$^{\ast }$\nobreakspace Corresponding author. ]]
      .. [[E-mail: ben@example.org}}]]
      .. [[\footnotetext {\textit {$^{a}$\nobreakspace Univ A}}]]
      .. [[\footnotetext {\textit {$^{b}$\nobreakspace Univ B}}]]
      .. [[\footnotetext {\textit {$^{\ddag }$\nobreakspace Equal.}}}]])
    assert(not result.stdout:find("\\cff", 1, true), "export retained an import-citation-cff command")
    -- The output compiles without import-citation-cff or the CFF file.
    write_file(f.input, result.stdout)
    assert(os.remove(f.cff))
    compile(f.directory, "manuscript.tex")
  end)

  test("plugin loading errors and inline definitions keep source diagnostics", function(f)
    write_file(f.directory .. "/cfflatex-style-empty.def", "\\endinput\n")
    for _, pair in ipairs({
      {"\\cffsetauthors[style=empty]", "Author style 'empty' was not registered"},
      {"\\cffsetauthors[style=../invalid]", "Invalid author style name"},
      {"\\cffdeclareauthorstyle{inline}{}", "cfflatex-style-NAME.def"},
    }) do
      write_file(f.input, preamble .. pair[1])
      local result = f:cli(f.input)
      failure(result, pair[2])
      contains(result.stderr, f.input .. ":4:1:")
    end
  end)

  test("author declarations require one preamble call after loading", function(f)
    for _, pair in ipairs({
      {"\\cffsetauthors\n" .. preamble, "call \\includecff"},
      {preamble .. "{\\cffsetauthors}", "top level"},
      {preamble .. "\\begin{document}\\cffsetauthors", "top level"},
      {preamble .. "\\cffforeachauthor{\\cffsetauthors}", "top level"},
      {preamble .. "\\ifnum1=1 \\cffsetauthors\\fi", "top level"},
      {preamble .. "\\cffsetauthors\\cffsetauthors", "only one"},
      {preamble .. "\\cffauthornames\\cffsetauthors", "call \\cffsetauthors"},
    }) do
      write_file(f.input, pair[1])
      failure(f:cli(f.input), pair[2])
    end
  end)

  test("invalid author options and fields preserve the destination", function(f)
    local output = f.directory .. "/submission.tex"
    for _, options in ipairs({"unknown=value", "style=absent", "note={99}{Bad}",
      "name={\\cffauthor{99}{name}}", "note={1}{\\cff{authors}}"}) do
      write_file(f.input, preamble .. "\\cffsetauthors[" .. options .. "]")
      write_file(output, "old output")
      failure(f:cli(f.input, "-o", output), f.input .. ":4:1:")
      equal(read_file(output), "old output")
      equal(names(f.directory), "CITATION.cff,manuscript.tex,submission.tex")
    end
  end)

  test("only author declarations invoke the isolated TeX engine", function(f)
    local bin = mkdir(f.directory .. "/bin")
    local marker = f.directory .. "/engine-call"
    write_file(bin .. "/lualatex", [[#!/bin/sh
printf '%s\n' "$PWD" "$@" > "$CFFLATEXPAND_TEST_ENGINE_CALL"
cat options.tex >> "$CFFLATEXPAND_TEST_ENGINE_CALL"
printf 'engine failure\n'
exit 1
]])
    success(run_command({"chmod", "+x", bin .. "/lualatex"}, f.directory))
    local engine_path = os.getenv("PATH")
    os.setenv("PATH", bin .. ":" .. engine_path)
    os.setenv("CFFLATEXPAND_TEST_ENGINE_CALL", marker)
    local worked, detail = pcall(function()
      success(f:cli(f.input))
      assert(not lfs.attributes(marker), "data-only expansion started TeX")
      -- The engine runs the options as they are, as compiling the document would.
      for _, command in ipairs({[[\input{unseen}]], [[\directlua{error('bad')}]],
        [[\def\hidden{bad}]], [[\cffsetauthors]], [[^^5ccff{title}]]}) do
        local options = "note={1}{" .. command .. "}"
        write_file(f.input, preamble .. "\\cffsetauthors[" .. options .. "]")
        failure(f:cli(f.input), "LuaLaTeX author rendering failed: engine failure")
        contains(read_file(marker), "\\cffsetauthors[" .. options .. "]")
        assert(os.remove(marker))
      end
      write_file(f.input, preamble .. "\\cffsetauthors")
      failure(f:cli(f.input), "LuaLaTeX author rendering failed: engine failure")
      local call = read_file(marker)
      contains(call, "\n--no-shell-escape\n")
      contains(call, "\n-halt-on-error\ndriver.tex\n")
      local directory = assert(call:match("^[^\n]+"))
      assert(not lfs.attributes(directory), "helper directory was not removed")
    end)
    os.setenv("PATH", engine_path)
    os.setenv("CFFLATEXPAND_TEST_ENGINE_CALL", nil)
    assert(worked, detail)
  end, windows and "POSIX engine stub" or nil)

  for _, style in ipairs({"standard", "authblk", "journal"}) do
    test(style .. " author export matches native rendering and footnotes", function(f)
      write_file(f.cff, rich_citation)
      for _, filename in ipairs({"import-citation-cff.sty", "cfflatex.lua", "cfflatex-data.lua",
        "cfflatex-style-standard.def", "cfflatex-style-authblk.def"}) do
        write_file(f.directory .. "/" .. filename, read_file(root .. "/" .. filename))
      end
      write_file(f.directory .. "/cfflatex-style-journal.def", [[
\cffdeclareauthorstyle{journal}{
  requires={authblk},
  validate={\IfPackageLoadedTF{authblk}{}{\PackageError{journal}{Load authblk}{}}},
  author={\author[{{}#1}]{#2}},affiliation={\affil[#1]{#2}},
  render={
    \cffforeachauthor{
      \cffrenderauthor{\cffauthorindex}
      \cffforeachauthoraffiliation{\cffauthorindex}{
        \cffrenderaffiliation{\cffconvertaffiliationindex
          {\cffauthorindex}{\cffauthoraffiliationindex}}}}
  },
}
]])
      -- Observe shipped glyphs and executed footnotes, including authblk's
      -- protected expansion when collecting its authors.
      local observer = [[\ProvidesPackage{observer}
\makeatletter
\let\export@footnotetext\footnotetext
\renewcommand\footnotetext[2][]{%
\typeout{EXPORT:footnote=#1/#2}%
\export@footnotetext[#1]{#2}}
\makeatother
\directlua{dofile('observer.lua')}
]]
      local observation = [[
local output = assert(io.open('glyphs.txt', 'w'))
local glyph, hlist, vlist = node.id('glyph'), node.id('hlist'), node.id('vlist')
local function collect(head)
  for item in node.traverse(head) do
    if item.id == glyph then
      output:write(utf8.char(item.char))
    elseif item.id == hlist or item.id == vlist then
      collect(item.head)
    end
  end
end
luatexbase.add_to_callback('pre_shipout_filter', function(head)
  collect(head)
  output:flush()
  return true
end, 'cfflatexpand-test')
]]
      write_file(f.directory .. "/observer.sty", observer)
      write_file(f.directory .. "/observer.lua", observation)
      local header = replace(preamble, "{import-citation-cff}", "[check=false]{import-citation-cff}")
      header = replace(header, "\\usepackage[check=false]",
        "\\usepackage{authblk}\n\\usepackage[check=false]")
      write_file(f.input, header .. "\\usepackage{observer}\n\\cffsetauthors[style=" .. style .. [=[,
name={#1{given-names}\nobreakspace#1{family-names}#1{name}},
affiliation-mark=Roman,separator={/},
contact={Contact: \texttt{#1{email}}},
note={1}{First \cff{title}},note={1}{Second},note={\cffcount{authors}}{Team note}]
\title{\cff{title}}\date{}
\begin{document}
\maketitle
\typeout{EXPORT:names=\cffauthornames}
\cffauthornames
\end{document}
]=])
      compile(f.directory, "manuscript.tex")
      local output = mkdir(f.directory .. "/submission")
      success(f:cli(f.input, "-o", output .. "/paper.tex"))
      write_file(output .. "/observer.sty", observer)
      write_file(output .. "/observer.lua", observation)
      write_file(output .. "/import-citation-cff.sty", "\\errmessage{Unexpected import-citation-cff load}\\endinput\n")
      assert(os.remove(f.input))
      assert(os.remove(f.cff))
      compile(output, "paper.tex")
      local function records(log)
        local lines = {}
        for line in log:gmatch("EXPORT:[^\r\n]*") do
          lines[#lines + 1] = line
        end
        equal(#lines, 5)
        return table.concat(lines, "\n")
      end
      equal(records(read_file(output .. "/paper.log")),
        records(read_file(f.directory .. "/manuscript.log")))
      equal(read_file(output .. "/glyphs.txt"), read_file(f.directory .. "/glyphs.txt"))
    end, not executable("lualatex") and "lualatex is required" or nil)
  end

  test("metadata export agrees with native TeX and compiles independently", function(f)
    write_file(f.cff, rich_citation)
    for _, filename in ipairs({"import-citation-cff.sty", "cfflatex.lua", "cfflatex-data.lua",
      "cfflatex-style-standard.def", "cfflatex-style-authblk.def"}) do
      write_file(f.directory .. "/" .. filename, read_file(root .. "/" .. filename))
    end
    write_file(f.input, preamble .. [=[
\title{\cff{title}}
\author{\cffforeachauthor{%
  \ifnum\cffauthorindex>1 \and\fi
  \cffauthor{\cffauthorindex}{given-names}%
  \cffauthor{\cffauthorindex}{name}}}
\date{}
\begin{document}
\maketitle
\typeout{EXPORT:plain=\cff{keywords/2}/\cff{version}/\cff{nested/flag}}
\typeout{EXPORT:counts=\cffcount{authors}/\cffcount{keywords}/\cffcount{missing}}
\typeout{EXPORT:calc=\cffauthor{(2*3-1)/2}{name}}
\typeout{EXPORT:spaces=\cff{custom field}/\cffauthor{1}{custom field}}
\typeout{EXPORT:paragraph=\cffaffiliationcount

End}
\cffforeachauthor{%
  \typeout{EXPORT:author=\cffauthorindex/\cff{authors/\cffauthorindex/given-names}}
  \cffforeachauthoraffiliation{\cffauthorindex}{%
    \typeout{EXPORT:local=\cffauthorindex/\cffauthoraffiliationindex}
    \typeout{EXPORT:global=\cffconvertaffiliationindex{\cffauthorindex}{\cffauthoraffiliationindex}}}}
\cffforeachcontact{%
  \typeout{EXPORT:contact=\cffcontactindex/\cffcontact{\cffcontactindex}{email}}}
\cffforeachaffiliation{%
  \typeout{EXPORT:affil=\cffaffiliationindex/\cffaffiliation{\cffaffiliationindex}}}
\ifodd\cffcount{authors}\typeout{EXPORT:odd}\else\typeout{EXPORT:even}\fi
\end{document}
]=])
    compile(f.directory, "manuscript.tex")
    local output = mkdir(f.directory .. "/submission")
    success(f:cli(f.input, "-o", output .. "/paper.tex"))
    assert(os.remove(f.input))
    assert(os.remove(f.cff))
    write_file(output .. "/import-citation-cff.sty", "\\errmessage{Unexpected import-citation-cff load}\\endinput\n")
    compile(output, "paper.tex")
    local function records(log)
      local result = {}
      for line in log:gmatch("EXPORT:[^\r\n]*") do
        result[#result + 1] = line
      end
      assert(#result > 10, log)
      return table.concat(result, "\n")
    end
    equal(records(read_file(output .. "/paper.log")),
      records(read_file(f.directory .. "/manuscript.log")))
  end, not executable("lualatex") and "lualatex is required" or nil)

  test("native package finds its sibling data module outside cwd", function(f)
    local package_directory = mkdir(f.directory .. "/package")
    for _, filename in ipairs({"import-citation-cff.sty", "cfflatex.lua", "cfflatex-data.lua",
      "cfflatex-style-standard.def", "cfflatex-style-authblk.def"}) do
      write_file(package_directory .. "/" .. filename, read_file(root .. "/" .. filename))
    end
    write_file(f.input, replace(replace(document, "{import-citation-cff}",
      "{" .. package_directory .. "/import-citation-cff}"), "\\author{Jane Doe}", "\\cffsetauthors"))
    compile(f.directory, "manuscript.tex")
  end, not executable("lualatex") and "lualatex is required" or nil)

  -- Last, because it removes the installation that the other tests use.
  if installed and not tds and not windows then
    test("l3build uninstall removes the command link", function()
      success(run_command({"l3build", "uninstall", "--texmfhome", texmf}, root))
      assert(not lfs.symlinkattributes(cli, "mode"), "the command link was not removed")
      assert(not lfs.attributes(installed_command), "the installed command was not removed")
    end)
  end
end, debug.traceback)

assert(lfs.chdir(initial_directory))
os.setenv("TEXMFVAR", old_texmfvar)
os.setenv("TEXMFCACHE", old_texmfcache)
os.setenv("TEXMFHOME", old_texmfhome)
os.setenv("PATH", old_path)
os.setenv("CFFLATEXPAND_BINDIR", old_bindir)
remove_tree(temporary)
if not ok then
  io.stderr:write(message, "\n")
  os.exit(1)
end
io.write(string.format("\n%d passed, %d failed, %d skipped\n", passed, failed, skipped))
os.exit(failed == 0 and 0 or 1)

-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 cffLaTeX contributors
-- Run with texlua tests/test_cfflatexpand.lua; no test framework is required.
-- CLI and package checks run in separate processes with temporary files.

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

local citation = "title: Example Paper\nauthors:\n  - family-names: Doe\n"
local preamble = "\\documentclass{article}\n\\usepackage{cfflatex}\n"
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
  local header = replace(preamble, "\\usepackage{cfflatex}", "")
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
  test("stdout from another directory", function(f)
    local result = f:cli(f.input)
    success(result)
    local expected = replace(document, "\\usepackage{cfflatex}", "")
    expected = replace(expected, "\\includecff{CITATION.cff}", "")
    equal(result.stdout, replace(expected, "\\cff{title}", "Example Paper"))
    equal(read_file(f.input), document)
  end)

  test("executable entry point", function(f)
    success(run_command({cli, f.input}, f.directory))
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
    for _, pair in ipairs({{"--help", "--output"}, {"--version", "cfflatex"}}) do
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
    for _, pair in ipairs({{"cfflatex,fontenc", "fontenc"}, {"fontenc,cfflatex", "fontenc"},
      {"fontenc, cfflatex, hyperref", "fontenc,  hyperref"},
      {"fontenc,% keep\n cfflatex, hyperref", "fontenc,% keep\n  hyperref"}}) do
      write_file(f.input, replace(document, "\\usepackage{cfflatex}",
        "\\usepackage{" .. pair[1] .. "}"))
      local result = f:cli(f.input)
      success(result)
      contains(result.stdout, "\\usepackage{" .. pair[2] .. "}")
    end
    write_file(f.input, replace(document, "\\usepackage{cfflatex}",
      "\\RequirePackage[check=false]{cfflatex}[2026/11/06]"))
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
    local expected = replace(source, "\\usepackage{cfflatex}", "")
    expected = replace(expected, "\\includecff{CITATION.cff}", "")
    equal(result.stdout, replace(expected, "\\cff{title}", "Example Paper"))
    write_file(f.input, replace(preamble .. "한글 \\cffsetauthors", "\n", "\r\n"))
    failure(f:cli(f.input), f.input .. ":4:4:")
  end)

  test("invalid literal options and filenames", function(f)
    for _, pair in ipairs({{"{cfflatex}", "[unknown=true]{cfflatex}"},
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

  test("unsupported constructs fail without partial output", function(f)
    for _, construct in ipairs({[[\cffsetauthors]], [[\cffauthornames]], [[\input{other}]],
      [[\include{other}]], [[\newcommand{\foo}{\cff{title}}]], [[\def\foo{\cff{title}}]],
      [[\iffalse\cff{title}\fi]], [[\catcode1=2]], [[\csname cff\endcsname{title}]],
      [[\ExplSyntaxOn]], [[\uppercase{\cff{title}}]], [[^^5ccff{title}]]}) do
      write_file(f.input, replace(document, "\\title{\\cff{title}}", construct))
      failure(f:cli(f.input), f.input .. ":4:1:")
    end
  end)

  test("reloaded, nested, or late CFF includes are rejected", function(f)
    for _, pair in ipairs({
      {replace(document, "\\title{", "\\includecff{CITATION.cff}\n\\title{"), "only one"},
      {replace(document, "\\includecff{CITATION.cff}", "{\\includecff{CITATION.cff}}"), "top level"},
      {replace(document, "\\includecff{CITATION.cff}\n", ""), "call \\includecff"},
      {replace(document, "\\usepackage{cfflatex}\n", ""), "load cfflatex"},
      {replace(document, "{cfflatex}", "{cfflatex,cfflatex}"), "only once"}}) do
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
    write_file(f.input, replace(document, "\\maketitle", "\\cffsetauthors"))
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

  test("output compiles without cfflatex or CFF files", function(f)
    local output = mkdir(f.directory .. "/submission")
    success(f:cli(f.input, "-o", output .. "/paper.tex"))
    assert(os.remove(f.input))
    assert(os.remove(f.cff))
    write_file(output .. "/cfflatex.sty",
      "\\errmessage{Export unexpectedly requires cfflatex}\\endinput\n")
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
      write_file(f.input, "\\usepackage{cfflatex}\n" .. command)
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
      "\\usepackage{cfflatex}\n\\ifodd1 \\includecff{CITATION.cff}\\fi",
      preamble .. [[\cffforeachauthor{\ifnum\cffauthorindex>1 x}]],
      preamble .. [[\else]], preamble .. [[\fi]],
      preamble .. [[\ifnum1=1 x\else y\else z\fi]],
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

  test("multiple-file inputs require explicit prior flattening", function(f)
    write_file(f.directory .. "/chapter.tex", "\\cff{title}")
    for _, command in ipairs({[[\input{chapter}]], [[\include{chapter}]],
      [[\includeonly{chapter}]]}) do
      write_file(f.input, preamble .. command)
      failure(f:cli(f.input), "first flatten the document with latexpand")
    end
  end)

  test("metadata export agrees with native TeX and compiles independently", function(f)
    write_file(f.cff, rich_citation)
    for _, filename in ipairs({"cfflatex.sty", "cfflatex.lua", "cfflatex-data.lua"}) do
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
    write_file(output .. "/cfflatex.sty", "\\errmessage{Unexpected cfflatex load}\\endinput\n")
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
    for _, filename in ipairs({"cfflatex.sty", "cfflatex.lua", "cfflatex-data.lua"}) do
      write_file(package_directory .. "/" .. filename, read_file(root .. "/" .. filename))
    end
    write_file(f.input, replace(document, "{cfflatex}",
      "{" .. package_directory .. "/cfflatex}"))
    compile(f.directory, "manuscript.tex")
  end, not executable("lualatex") and "lualatex is required" or nil)
end, debug.traceback)

assert(lfs.chdir(initial_directory))
os.setenv("TEXMFVAR", old_texmfvar)
os.setenv("TEXMFCACHE", old_texmfcache)
remove_tree(temporary)
if not ok then
  io.stderr:write(message, "\n")
  os.exit(1)
end
io.write(string.format("\n%d passed, %d failed, %d skipped\n", passed, failed, skipped))
os.exit(failed == 0 and 0 or 1)

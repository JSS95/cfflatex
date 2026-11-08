-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 import-citation-cff contributors
-- Run with texlua tests/test_expand_manual.lua. The manual is a document that
-- uses import-citation-cff: expand it with cfflatexpand, check the result, and
-- compile it with LuaLaTeX where loading import-citation-cff is an error.

local kpse = require("kpse")
kpse.set_program_name("luatex")
local lfs = require("lfs")
local windows = package.config:sub(1, 1) == "\\"

local script = arg[0]
if not script:match("^[/\\]") and not script:match("^%a:[/\\]") then
  script = assert(lfs.currentdir()) .. "/" .. script
end
local root = assert(script:match("^(.*)[/\\]tests[/\\][^/\\]+$"))
local manual = "import-citation-cff.tex"

local function read_file(filename)
  local file = assert(io.open(filename, "rb"))
  local text = assert(file:read("*a"))
  assert(file:close())
  return text
end

local function write_file(filename, text)
  local file = assert(io.open(filename, "wb"))
  assert(file:write(text))
  assert(file:close())
end

local function quote(value)
  if windows then
    -- cmd.exe expands these characters, and texlua's os.execute turns ' into ".
    assert(not value:find('["%%!\'\r\n]'), "unsupported cmd.exe argument: " .. value)
    return '"' .. value .. '"'
  end
  return "'" .. value:gsub("'", "'\\''") .. "'"
end

-- Run a program in a directory. The program name is left unquoted: cmd.exe
-- drops the first and the last quote of a command that starts with a quote.
local function run(directory, program, ...)
  local words = {program}
  for _, value in ipairs({...}) do
    words[#words + 1] = quote(value)
  end
  local previous = assert(lfs.currentdir())
  assert(lfs.chdir(directory))
  local status = os.execute(table.concat(words, " ")
    .. " > " .. quote(directory .. "/command.log") .. " 2>&1")
  assert(lfs.chdir(previous))
  return status == 0 or status == true, read_file(directory .. "/command.log")
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

local reservation = os.tmpname()
local directory = reservation .. ".manual"
assert(lfs.mkdir(directory))
if lfs.attributes(reservation) then
  assert(os.remove(reservation))
end

local failures = {}
local function check(condition, message)
  if not condition then
    failures[#failures + 1] = message
  end
end

local ok, message = pcall(function()
  local expanded, log = run(directory, "texlua", root .. "/cfflatexpand",
    root .. "/" .. manual, "--output", directory .. "/" .. manual)
  assert(expanded, "cfflatexpand failed:\n" .. log)
  local source, output = read_file(root .. "/" .. manual), read_file(directory .. "/" .. manual)

  -- The metadata commands become the values of the manual's CITATION.cff.
  local model = dofile(root .. "/cfflatex-data.lua").load(root .. "/CITATION.cff", "")
  check(output:find("\\title{" .. model.fields.title .. "}", 1, true),
    "the title is not expanded to the value of CITATION.cff")
  check(output:find(model.fields.abstract, 1, true),
    "the abstract is not expanded to the value of CITATION.cff")

  -- Commands that the manual shows rather than runs stay as they are: short
  -- verbatim text and the command lists of l3doc's function environments.
  local body = source:match("\\begin{document}(.*)$")
  for text in body:gmatch("|[^|\n]*\\cff[^|\n]*|") do
    check(output:find(text, 1, true), "short verbatim text changed: " .. text)
  end
  for line in source:gmatch("\\begin{function}[^\n]*") do
    check(output:find(line, 1, true), "function environment changed: " .. line)
  end

  -- The expanded manual compiles without the package; only the files that it
  -- shows (CITATION.cff and the help of cfflatexpand, from its Lua modules)
  -- and cites (the bibliography) are still needed.
  for _, name in ipairs({"CITATION.cff", "import-citation-cff.bib", "cfflatexpand.lua",
    "cfflatex-data.lua"}) do
    write_file(directory .. "/" .. name, read_file(root .. "/" .. name))
  end
  write_file(directory .. "/import-citation-cff.sty",
    "\\errmessage{The expanded manual loads import-citation-cff}\\endinput\n")
  local compiled = run(directory, "lualatex", "--no-shell-escape",
    "-interaction=nonstopmode", "-halt-on-error", manual)
  if not compiled then
    local transcript = read_file(directory .. "/import-citation-cff.log")
    check(false, "the expanded manual does not compile:\n" .. transcript:sub(-3000))
  end
end)

remove_tree(directory)
if not ok then
  failures[#failures + 1] = tostring(message)
end
if #failures > 0 then
  io.stderr:write("FAIL expand the manual\n", table.concat(failures, "\n"), "\n")
  os.exit(1)
end
io.write("PASS expand the manual\n")

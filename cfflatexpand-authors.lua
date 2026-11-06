-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 cffLaTeX contributors
-- Collect the existing TeX author renderer's declarations in an isolated run.

local lfs = require("lfs")
local kpse = require("kpse")
local authors = {}

local driver = [[
\documentclass{article}
\usepackage[check=false]{cfflatex}
\ExplSyntaxOn
\iow_new:N \g__cfflatex_export_declarations_iow
\iow_new:N \g__cfflatex_export_names_iow
\iow_open:Nn \g__cfflatex_export_declarations_iow { declarations.tex }
\iow_open:Nn \g__cfflatex_export_names_iow { names.tex }
% Only existence is needed: declarations are collected rather than executed.
\cs_if_exist:NF \affil { \cs_new_eq:NN \affil \use_none:n }
\cs_set_protected:Npn \__cfflatex_emit:n #1
  {
    \tl_if_head_eq_meaning:nNTF {#1} \__cfflatex_standard_author:nn
      {#1}
      {
        \iow_now:Ne \g__cfflatex_export_declarations_iow
          { \tl_to_str:n {#1} }
      }
  }
\cs_set_protected:Npn \__cfflatex_store_author_names:
  {
    \tl_clear:N \l_tmpa_tl
    \seq_map_indexed_inline:Nn \l__cfflatex_names_seq
      {
        \int_compare:nNnT {##1} > { 1 }
          { \tl_put_right:Nn \l_tmpa_tl { ,~ } }
        \tl_put_right:Nn \l_tmpa_tl {##2}
      }
    \iow_now:Ne \g__cfflatex_export_names_iow
      { \tl_to_str:V \l_tmpa_tl }
  }
\file_input:n { metadata.tex }
\ExplSyntaxOff
\input{options.tex}
\ExplSyntaxOn
\iow_close:N \g__cfflatex_export_declarations_iow
\iow_close:N \g__cfflatex_export_names_iow
\ExplSyntaxOff
\begin{document}
\end{document}
]]

local function read_file(filename)
  local input = io.open(filename, "rb")
  if not input then
    return nil
  end
  local text = input:read("*a")
  input:close()
  return text
end

local function write_file(filename, text)
  local output, message = io.open(filename, "wb")
  if not output then
    error(message, 0)
  end
  local written, write_error = output:write(text)
  local closed, close_error = output:close()
  if not written or not closed then
    error(write_error or close_error, 0)
  end
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

function authors.render(model, options, source_directory)
  local reservation = os.tmpname()
  local temporary = reservation .. ".cfflatexpand-authors"
  local created, message = lfs.mkdir(temporary)
  if lfs.attributes(reservation) then
    os.remove(reservation)
  end
  if not created then
    error(message, 0)
  end
  local previous_directory = assert(lfs.currentdir())
  local previous_var, previous_cache = os.getenv("TEXMFVAR"), os.getenv("TEXMFCACHE")
  local ok, result = pcall(function()
    for _, filename in ipairs({"cfflatex.sty", "cfflatex.lua", "cfflatex-data.lua"}) do
      local contents = read_file(source_directory .. filename)
      if not contents then
        contents = read_file(kpse.find_file(filename, "tex") or filename)
      end
      if not contents then
        error("cannot find " .. filename .. " for author rendering", 0)
      end
      write_file(temporary .. "/" .. filename, contents)
    end
    write_file(temporary .. "/driver.tex", driver)
    write_file(temporary .. "/metadata.tex", require("cfflatex").serialize(model))
    write_file(temporary .. "/options.tex", "\\cffsetauthors[" .. options .. "]\n")
    assert(lfs.mkdir(temporary .. "/cache"))
    -- Existing writable caches can be reused; otherwise keep generated files
    -- with the helper instead of writing to the user's default TeX cache.
    os.setenv("TEXMFVAR", previous_var or temporary .. "/cache")
    os.setenv("TEXMFCACHE", previous_cache or temporary .. "/cache")
    assert(lfs.chdir(temporary))
    -- The command and filenames are constant. User text is read from files,
    -- never interpolated into shell arguments, and engine output is captured.
    local status, _, code = os.execute("lualatex --no-shell-escape"
      .. " -interaction=batchmode -halt-on-error driver.tex > engine.stdout 2>&1")
    if type(status) ~= "number" then
      status = status == true and 0 or code or 1
    end
    if status ~= 0 then
      local log = read_file("driver.log") or read_file("engine.stdout") or ""
      local detail = log:match("\n! ([^\r\n]+)") or log:match("([^\r\n]+)[\r\n]*$")
      error("LuaLaTeX author rendering failed: " .. (detail or "install lualatex"), 0)
    end
    local declarations, names = read_file("declarations.tex"), read_file("names.tex")
    if not declarations or not names then
      error("the author renderer did not produce declarations and names", 0)
    end
    return {declarations = declarations, names = names:gsub("[\r\n]+$", "")}
  end)
  assert(lfs.chdir(previous_directory))
  os.setenv("TEXMFVAR", previous_var)
  os.setenv("TEXMFCACHE", previous_cache)
  remove_tree(temporary)
  if not ok then
    error(result, 0)
  end
  return result
end

return authors

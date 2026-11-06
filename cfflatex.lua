-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 cffLaTeX contributors
-- Turns the shared CFF model into the storage commands of cfflatex.sty.

-- Match the helper selected by cfflatex.sty, including an explicit package
-- path outside the current directory or the installed TeX tree.
local helper = ... or "cfflatex.lua"
local directory = helper:match("^(.*[/\\])") or ""
local data_file = require("kpse").find_file(directory .. "cfflatex-data.lua", "tex")
local data = data_file and dofile(data_file) or require("cfflatex-data")
local cfflatex = {}

local function read(filename, source)
  local model = data.load(filename, source)
  local output = {}
  for _, entry in ipairs({
    {model.fields, "__cfflatex_store_field:nn"},
    {model.kinds, "__cfflatex_store_kind:nn"},
    {model.values, "__cfflatex_store:nn"},
  }) do
    for path, value in pairs(entry[1]) do
      output[#output + 1] = "\\csname " .. entry[2] .. "\\endcsname{"
        .. path .. "}{" .. value .. "}"
    end
  end
  output[#output + 1] = "\\csname __cfflatex_finish:n\\endcsname{"
    .. #model.citation.authors .. "}"
  return table.concat(output, "\n")
end

function cfflatex.read(filename, source)
  local success, result = pcall(read, filename, source)
  if success then
    return result
  end
  return "\\csname __cfflatex_fail:n\\endcsname{" .. data.tex_text(result) .. "}"
end

return cfflatex

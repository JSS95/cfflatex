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

local function store(path, value)
  return "\\csname __cfflatex_store:nn\\endcsname{"
    .. path .. "}{" .. data.tex_text(value) .. "}"
end

-- Stores every value of the citation under its path, the keys and the indices
-- of the mappings and sequences that hold it, separated by slashes, for \cff.
-- The length of each sequence is stored as its kind, and a mapping as "map".
local function flatten(value, path, output)
  local value_kind = data.kind(value)
  if value_kind == "map" or value_kind == "seq" then
    output[#output + 1] = "\\csname __cfflatex_store_kind:nn\\endcsname{"
      .. path .. "}{" .. (value_kind == "seq" and #value or "map") .. "}"
    for key, item in pairs(value) do
      local name = data.tex_text(key)
      flatten(item, path == "" and name or path .. "/" .. name, output)
    end
  elseif data.is_scalar(value) then
    output[#output + 1] = "\\csname __cfflatex_store_field:nn\\endcsname{"
      .. path .. "}{" .. data.tex_text(value) .. "}"
  end
end

local function read(filename, source)
  local model = data.load(filename, source)
  local output = {}
  flatten(model.citation, "", output)
  for index, author in ipairs(model.citation.authors) do
    for key, value in pairs(author) do
      if type(key) == "string" and data.is_scalar(value) then
        output[#output + 1] = store("authors/" .. index .. "/" .. data.tex_text(key), value)
      end
    end
    local affiliation = model.author_affiliations[index]
    if affiliation then
      for position, name in ipairs(affiliation.names) do
        local key = "authors/" .. index .. "/affiliation-"
        output[#output + 1] = store(key .. "names/" .. position, name)
        output[#output + 1] = store(key .. "indices/" .. position,
          affiliation.indices[position])
      end
      output[#output + 1] = store("authors/" .. index .. "/affiliation-count",
        #affiliation.names)
    end
  end
  for index, name in ipairs(model.affiliations) do
    output[#output + 1] = store("affiliations/" .. index, name)
  end
  output[#output + 1] = store("affiliation-count", #model.affiliations)
  for index, contact in ipairs(model.citation.contact or {}) do
    for key, value in pairs(contact) do
      if type(key) == "string" and data.is_scalar(value) then
        output[#output + 1] = store("contact/" .. index .. "/" .. data.tex_text(key), value)
      end
    end
  end
  output[#output + 1] = store("contact-count", model.contact_count)
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

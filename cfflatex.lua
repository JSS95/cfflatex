-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 cffLaTeX contributors
-- Reads a CFF file with lua-tinyyaml and returns TeX code that stores the
-- selected citation's title and author fields in cfflatex.sty.

local cfflatex = {}

local escapes = {
  ["\\"] = "\\textbackslash{}",
  ["{"] = "\\{",
  ["}"] = "\\}",
  ["%"] = "\\%",
  ["#"] = "\\#",
  ["$"] = "\\$",
  ["&"] = "\\&",
  ["_"] = "\\_",
  ["~"] = "\\textasciitilde{}",
  ["^"] = "\\textasciicircum{}",
}

-- Each returned line is tokenized by TeX, so line breaks become spaces and
-- TeX special characters are printed literally. Surrounding whitespace, such
-- as the final line break of a YAML literal block, is dropped.
local function tex_text(value)
  return (tostring(value)
    :gsub("\r\n", "\n")
    :gsub("[\r\n\t]", " ")
    :gsub("^ +", "")
    :gsub(" +$", "")
    :gsub("[\\{}%%#$&_~%^]", escapes))
end

-- lua-tinyyaml marks parsed collections and nulls with a __type metatable.
local function kind(value)
  if type(value) ~= "table" then
    return type(value)
  end
  local metadata = getmetatable(value)
  if metadata and metadata.__type then
    return metadata.__type
  end
  return #value > 0 and "seq" or "map"
end

local function is_scalar(value)
  local value_kind = kind(value)
  return value_kind == "string" or value_kind == "number"
    or value_kind == "boolean"
end

local function store(path, value)
  return "\\csname __cfflatex_store:nn\\endcsname{"
    .. path .. "}{" .. tex_text(value) .. "}"
end

-- CFF 1.2.0 gives a person one affiliation, a nonempty string. cffLaTeX reads
-- several affiliations from a string that separates them with semicolons; a
-- single trailing semicolon is allowed. Whitespace runs become single spaces,
-- and each affiliation is trimmed.
local function split_affiliations(value, path)
  if kind(value) ~= "string" then
    error("'" .. path .. "' must be a string", 0)
  end
  local text = value:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", ""):gsub(";$", "")
  if not text:match("%S") then
    error("'" .. path .. "' must not be empty", 0)
  end
  local names, seen = {}, {}
  for part in (text .. ";"):gmatch("([^;]*);") do
    local name = part:match("^ *(.-) *$")
    if name == "" then
      error("'" .. path .. "' has an empty affiliation between semicolons", 0)
    end
    if seen[name] then
      error("'" .. path .. "' lists '" .. name .. "' twice", 0)
    end
    seen[name] = true
    names[#names + 1] = name
  end
  return names
end

-- An empty source selects the top level of the file. Any other source is a
-- top-level key, such as preferred-citation, whose value is the citation.
-- The prefix is put before field names in error messages.
local function select_citation(data, source)
  if kind(data) ~= "map" then
    error("the CFF file must contain a mapping", 0)
  end
  if source == "" then
    return data, ""
  end
  local selected = data[source]
  if selected == nil then
    error("the CFF file has no '" .. source .. "'", 0)
  end
  if kind(selected) ~= "map" then
    error("'" .. source .. "' must be a mapping", 0)
  end
  return selected, source .. "/"
end

local function read(filename, source)
  local available, yaml = pcall(require, "tinyyaml")
  if not available then
    error("install the lua-tinyyaml TeX package", 0)
  end
  local kpse = require("kpse")
  local input, open_error = io.open(kpse.find_file(filename, "tex") or filename, "rb")
  if not input then
    error(open_error, 0)
  end
  local contents = input:read("*a")
  input:close()
  -- Dates stay text, as CFF writes them.
  local data = yaml.parse(contents, {timestamps = false})
  local selected, prefix = select_citation(data, source)

  local output = {}
  if not is_scalar(selected.title) then
    error("'" .. prefix .. "title' must be a string", 0)
  end
  output[#output + 1] = store("title", selected.title)

  -- The abstract is optional; when absent, \cffabstract expands to nothing.
  if selected.abstract ~= nil then
    if not is_scalar(selected.abstract) then
      error("'" .. prefix .. "abstract' must be a string", 0)
    end
    output[#output + 1] = store("abstract", selected.abstract)
  end

  local authors = selected.authors
  if kind(authors) ~= "seq" or #authors == 0 then
    error("'" .. prefix .. "authors' must be a nonempty sequence", 0)
  end
  -- Distinct affiliations are numbered in the order they first appear.
  local numbers, affiliation_count = {}, 0
  for index, author in ipairs(authors) do
    if kind(author) ~= "map" then
      error("'" .. prefix .. "authors/" .. index .. "' must be a mapping", 0)
    end
    for key, value in pairs(author) do
      if type(key) == "string" and is_scalar(value) then
        output[#output + 1] = store("authors/" .. index .. "/" .. tex_text(key), value)
      end
    end
    if author.affiliation ~= nil then
      local path = prefix .. "authors/" .. index .. "/affiliation"
      local names = split_affiliations(author.affiliation, path)
      for position, name in ipairs(names) do
        if numbers[name] == nil then
          affiliation_count = affiliation_count + 1
          numbers[name] = affiliation_count
          output[#output + 1] = store("affiliations/" .. affiliation_count, name)
        end
        output[#output + 1] = store(
          "authors/" .. index .. "/affiliation-names/" .. position, name)
      end
      output[#output + 1] = store("authors/" .. index .. "/affiliation-count", #names)
    end
  end
  output[#output + 1] = store("affiliation-count", affiliation_count)

  output[#output + 1] = "\\csname __cfflatex_finish:n\\endcsname{"
    .. #authors .. "}"
  return table.concat(output, "\n")
end

function cfflatex.read(filename, source)
  local success, result = pcall(read, filename, source)
  if success then
    return result
  end
  return "\\csname __cfflatex_fail:n\\endcsname{" .. tex_text(result) .. "}"
end

return cfflatex

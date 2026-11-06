-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 cffLaTeX contributors
-- Shared CFF interpretation for cfflatex.sty and cfflatexpand.

local data = {}

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

-- Match TeX's existing representation of CFF scalars: escape special
-- characters, turn line breaks and tabs into spaces, and trim the edges.
function data.tex_text(value)
  return (tostring(value)
    :gsub("\r\n", "\n")
    :gsub("[\r\n\t]", " ")
    :gsub("^ +", "")
    :gsub(" +$", "")
    :gsub("[\\{}%%#$&_~%^]", escapes))
end

-- lua-tinyyaml marks parsed collections and nulls with a __type metatable.
function data.kind(value)
  if type(value) ~= "table" then
    return type(value)
  end
  local metadata = getmetatable(value)
  if metadata and metadata.__type then
    return metadata.__type
  end
  return #value > 0 and "seq" or "map"
end

function data.is_scalar(value)
  local kind = data.kind(value)
  return kind == "string" or kind == "number" or kind == "boolean"
end

-- CFF gives a person one affiliation. cffLaTeX accepts a semicolon-separated
-- string; a single trailing semicolon is allowed, but not blanks or repeats.
local function split_affiliations(value, path)
  if data.kind(value) ~= "string" then
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

local function select_citation(citation, source)
  if data.kind(citation) ~= "map" then
    error("the CFF file must contain a mapping", 0)
  end
  if source == "" then
    return citation, ""
  end
  local selected = citation[source]
  if selected == nil then
    error("the CFF file has no '" .. source .. "'", 0)
  end
  if data.kind(selected) ~= "map" then
    error("'" .. source .. "' must be a mapping", 0)
  end
  return selected, source .. "/"
end

local function check_cycles(value, active)
  local kind = data.kind(value)
  if kind == "map" or kind == "seq" then
    if active[value] then
      error("cyclic YAML aliases are not supported", 0)
    end
    active[value] = true
    for _, item in pairs(value) do
      check_cycles(item, active)
    end
    active[value] = nil
  end
end

-- Returns data, not TeX commands. Both callers use the same validation and
-- numbering, and decide independently how to present the result or errors.
function data.load(filename, source)
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
  local selected, prefix = select_citation(
    yaml.parse(contents, {timestamps = false}), source or "")
  check_cycles(selected, {})
  if not data.is_scalar(selected.title) then
    error("'" .. prefix .. "title' must be a string", 0)
  end
  if selected.abstract ~= nil and not data.is_scalar(selected.abstract) then
    error("'" .. prefix .. "abstract' must be a string", 0)
  end
  if data.kind(selected.authors) ~= "seq" or #selected.authors == 0 then
    error("'" .. prefix .. "authors' must be a nonempty sequence", 0)
  end

  local model = {
    citation = selected,
    affiliations = {},
    author_affiliations = {},
    contact_count = 0,
  }
  local numbers = {}
  for index, author in ipairs(selected.authors) do
    if data.kind(author) ~= "map" then
      error("'" .. prefix .. "authors/" .. index .. "' must be a mapping", 0)
    end
    if author.affiliation ~= nil then
      local names = split_affiliations(author.affiliation,
        prefix .. "authors/" .. index .. "/affiliation")
      local indices = {}
      for position, name in ipairs(names) do
        if numbers[name] == nil then
          model.affiliations[#model.affiliations + 1] = name
          numbers[name] = #model.affiliations
        end
        indices[position] = numbers[name]
      end
      model.author_affiliations[index] = {names = names, indices = indices}
    end
  end
  if selected.contact ~= nil then
    if data.kind(selected.contact) ~= "seq" or #selected.contact == 0 then
      error("'" .. prefix .. "contact' must be a nonempty sequence", 0)
    end
    for index, contact in ipairs(selected.contact) do
      if data.kind(contact) ~= "map" then
        error("'" .. prefix .. "contact/" .. index .. "' must be a mapping", 0)
      end
    end
    model.contact_count = #selected.contact
  end
  return model
end

return data

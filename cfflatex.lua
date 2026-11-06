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

local function select_citation(data, source)
  if kind(data) ~= "map" then
    error("the CFF file must contain a mapping", 0)
  end
  if source == "root" then
    return data, "root"
  elseif source == "preferred-citation" then
    local selected = data["preferred-citation"]
    if selected == nil then
      error("the CFF file has no 'preferred-citation'", 0)
    end
    return selected, "preferred-citation"
  end
  error("unknown source '" .. tostring(source) .. "'", 0)
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
  if kind(selected) ~= "map" then
    error("'" .. prefix .. "' must be a mapping", 0)
  end

  local output = {}
  if not is_scalar(selected.title) then
    error("'" .. prefix .. "/title' must be a string", 0)
  end
  output[#output + 1] = store("title", selected.title)

  -- The abstract is optional; when absent, \cffabstract expands to nothing.
  if selected.abstract ~= nil then
    if not is_scalar(selected.abstract) then
      error("'" .. prefix .. "/abstract' must be a string", 0)
    end
    output[#output + 1] = store("abstract", selected.abstract)
  end

  local authors = selected.authors
  if kind(authors) ~= "seq" or #authors == 0 then
    error("'" .. prefix .. "/authors' must be a nonempty sequence", 0)
  end
  for index, author in ipairs(authors) do
    if kind(author) ~= "map" then
      error("'" .. prefix .. "/authors/" .. index .. "' must be a mapping", 0)
    end
    for key, value in pairs(author) do
      if type(key) == "string" and is_scalar(value) then
        output[#output + 1] = store("authors/" .. index .. "/" .. tex_text(key), value)
      end
    end
  end

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

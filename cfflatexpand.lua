-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 cffLaTeX contributors
-- A source-preserving scanner for the first, title-only export contract.

local data = require("cfflatex-data")
local expand = {}
local Scanner = {}
Scanner.__index = Scanner

local opaque_environments = {
  verbatim = true, ["verbatim*"] = true,
  Verbatim = true, ["Verbatim*"] = true,
  lstlisting = true, minted = true, comment = true,
  filecontents = true, ["filecontents*"] = true,
  luacode = true, ["luacode*"] = true,
}

-- These constructs can change tokenization, hide commands, select another
-- execution order, or read unseen TeX. They need a later export contract.
local unsupported = {}
for name in ([[
  input include includeonly InputIfFileExists IfFileExists subfile import
  subimport includefrom subincludefrom def gdef edef xdef let futurelet
  newcommand renewcommand providecommand DeclareRobustCommand
  newenvironment renewenvironment NewDocumentEnvironment
  RenewDocumentEnvironment ProvideDocumentEnvironment DeclareDocumentEnvironment
  NewDocumentCommand RenewDocumentCommand ProvideDocumentCommand
  DeclareDocumentCommand NewExpandableDocumentCommand RenewExpandableDocumentCommand
  ProvideExpandableDocumentCommand DeclareExpandableDocumentCommand
  newif else fi unless csname endcsname catcode makeatletter makeatother
  ExplSyntaxOn ExplSyntaxOff begingroup endgroup bgroup egroup
  expandafter noexpand unexpanded detokenize string meaning scantokens expanded
  afterassignment aftergroup directlua endinput
  Verb lstinline mintinline url path
]]):gmatch("%S+") do
  unsupported[name] = true
end

function Scanner:fail(position, message)
  local before = self.text:sub(1, position - 1):gsub("\r\n", "\n"):gsub("\r", "\n")
  local _, lines = before:gsub("\n", "")
  local last = before:match("[^\n]*$")
  local column = (utf8.len(last) or #last) + 1
  error(self.filename .. ":" .. (lines + 1) .. ":" .. column .. ": " .. message, 0)
end

function Scanner:comment(position)
  local ending = self.text:find("[\r\n]", position + 1)
  if not ending then
    return #self.text + 1
  end
  if self.text:sub(ending, ending + 1) == "\r\n" then
    return ending + 2
  end
  return ending + 1
end

function Scanner:skip(position)
  while position <= #self.text do
    local char = self.text:sub(position, position)
    if char == "%" then
      position = self:comment(position)
    elseif char:match("%s") then
      position = position + 1
    else
      break
    end
  end
  return position
end

function Scanner:command(position)
  local name = self.text:match("^\\([A-Za-z]+)", position)
  if name then
    return name, position + #name + 1
  end
  return self.text:sub(position + 1, position + 1), position + 2
end

-- Arguments retain their source offsets. Braces protect optional-argument
-- delimiters; escaped braces and delimiters inside comments do not balance.
function Scanner:argument(position, opening, closing)
  position = self:skip(position)
  if self.text:sub(position, position) ~= opening then
    self:fail(position, "expected '" .. opening .. "'")
  end
  local start, braces, brackets = position, 0, 1
  position = position + 1
  while position <= #self.text do
    local char = self.text:sub(position, position)
    if char == "%" then
      position = self:comment(position)
    elseif char == "\\" then
      local _
      _, position = self:command(position)
    elseif char == "}" and braces == 0 and closing == "}" then
      return {first = start + 1, last = position - 1}, position + 1
    elseif char == "{" then
      braces, position = braces + 1, position + 1
    elseif char == "}" then
      if braces == 0 then
        self:fail(position, "unmatched '}' in argument")
      end
      braces, position = braces - 1, position + 1
    elseif braces == 0 and opening == "[" and char == "[" then
      brackets, position = brackets + 1, position + 1
    elseif braces == 0 and closing == "]" and char == "]" then
      brackets = brackets - 1
      if brackets == 0 then
        return {first = start + 1, last = position - 1}, position + 1
      end
      position = position + 1
    else
      position = position + 1
    end
  end
  self:fail(start, "unclosed '" .. opening .. "' argument")
end

function Scanner:optional(position)
  local next_position = self:skip(position)
  if self.text:sub(next_position, next_position) == "[" then
    return self:argument(next_position, "[", "]")
  end
  return nil, position
end

-- TeX discards a comment's line ending and the indentation on the next line.
-- Otherwise whitespace runs become a space. This is also used for literal
-- paths; paths with macros or TeX special characters are deliberately refused.
function Scanner:literal(argument, allow_braces)
  local pieces, position = {}, argument.first
  while position <= argument.last do
    local char = self.text:sub(position, position)
    if char == "%" then
      position = self:comment(position)
      while self.text:sub(position, position):match("[ \t]") do
        position = position + 1
      end
    else
      if char:match("[\\#$&~^]") or (not allow_braces and char:match("[{}]")) then
        self:fail(position, "expected a literal argument without TeX commands")
      end
      pieces[#pieces + 1] = char
      position = position + 1
    end
  end
  return (table.concat(pieces):gsub("%s+", " "))
end

function Scanner:edit(first, last, replacement)
  self.edits[#self.edits + 1] = {first = first, last = last, text = replacement or ""}
end

function Scanner:package(position, after)
  local options, next_position = self:optional(after)
  local argument, ending = self:argument(next_position, "{", "}")
  local entries, cursor = {}, argument.first
  while cursor <= argument.last do
    cursor = self:skip(cursor)
    if cursor > argument.last then
      break
    end
    local name = self.text:match("^([A-Za-z0-9_.-]+)", cursor)
    if not name then
      self:fail(cursor, "expected a literal package name")
    end
    local entry = {name = name, first = cursor, last = cursor + #name - 1}
    entries[#entries + 1] = entry
    cursor = self:skip(entry.last + 1)
    if cursor <= argument.last then
      if self.text:sub(cursor, cursor) ~= "," then
        self:fail(cursor, "expected ',' between package names")
      end
      entry.comma = cursor
      cursor = cursor + 1
    end
  end
  local count = 0
  for _, entry in ipairs(entries) do
    if entry.name == "cfflatex" then
      count = count + 1
    end
  end
  if count > 1 then
    self:fail(position, "cfflatex must be loaded only once")
  end
  for index, entry in ipairs(entries) do
    if entry.name == "cfflatex" then
      if self.package_loaded or self.depth > 0 or self.body then
        self:fail(position, "cfflatex must be loaded once at the top level of the preamble")
      end
      if options then
        local value = self:literal(options):match("^%s*(.-)%s*$")
        if value ~= "" and value ~= "check" and value ~= "check=true"
          and value ~= "check=false" then
          self:fail(options.first, "only literal check, check=true or check=false options are supported")
        end
      end
      self.package_loaded = true
      if #entries == 1 then
        local _
        _, ending = self:optional(ending) -- optional package release date
        self:edit(position, ending - 1)
      else
        self:edit(entry.first, entry.last)
        local comma = entry.comma or entries[index - 1].comma
        self:edit(comma, comma)
      end
      return ending
    end
  end
  -- Walk unaffected package arguments normally, so metadata there is not
  -- silently skipped. The command and every original byte remain unchanged.
  return after
end

function Scanner:include(position, after)
  if not self.package_loaded then
    self:fail(position, "load cfflatex before \\includecff")
  end
  if self.model then
    self:fail(position, "only one \\includecff is supported; reloading can change delayed expansion")
  end
  if self.depth > 0 or self.body then
    self:fail(position, "\\includecff must be at the top level of the preamble")
  end
  local options, next_position = self:optional(after)
  local source = ""
  if options then
    local text = self:literal(options, true):match("^%s*(.-)%s*$")
    if text ~= "" then
      source = text:match("^source%s*=%s*(.-)%s*,?$")
      if not source then
        self:fail(options.first, "expected source=<literal key>")
      end
      if source:sub(1, 1) == "{" and source:sub(-1) == "}" then
        source = source:sub(2, -2)
      end
      if source:find("[{},=]") then
        self:fail(options.first, "expected one literal source key")
      end
    end
  end
  local argument, ending = self:argument(next_position, "{", "}")
  local filename = self:literal(argument):match("^%s*(.-)%s*$")
  if filename == "" then
    self:fail(argument.first, "the CFF filename must not be empty")
  end
  if not filename:match("^[/\\]") and not filename:match("^%a:[/\\]") then
    filename = self.directory .. filename
  end
  local success, model = pcall(data.load, filename, source)
  if not success then
    self:fail(position, "cannot read CFF file: " .. tostring(model))
  end
  self.model = model
  self:edit(position, ending - 1)
  return ending
end

function Scanner:field(position, after)
  if not self.model then
    self:fail(position, "call \\includecff before \\cff")
  end
  local argument, ending = self:argument(after, "{", "}")
  if self:literal(argument) ~= "title" then
    self:fail(position, "only \\cff{title} is supported in this version")
  end
  self:edit(position, ending - 1, data.tex_text(self.model.citation.title))
  return ending
end

function Scanner:verb(position, after)
  if self.text:sub(after, after) == "*" then
    after = after + 1
  end
  local delimiter = self.text:sub(after, after)
  if delimiter == "" or delimiter:match("%s") then
    self:fail(position, "expected a delimiter after \\verb")
  end
  local ending = self.text:find(delimiter, after + 1, true)
  local newline = self.text:find("[\r\n]", after + 1)
  if not ending or (newline and newline < ending) then
    self:fail(position, "unclosed \\verb")
  end
  return ending + 1
end

function Scanner:environment(position, after, begin)
  local argument, ending = self:argument(after, "{", "}")
  local name = self:literal(argument)
  if begin and opaque_environments[name] then
    local marker = "\\end{" .. name .. "}"
    local terminator = self.text:find(marker, ending, true)
    if not terminator then
      self:fail(position, "unclosed " .. name .. " environment")
    end
    return terminator + #marker
  end
  if name == "document" then
    if begin then
      self.body = true
    else
      return #self.text + 1 -- TeX does not read beyond \end{document}.
    end
  end
  return ending
end

-- Re-tokenizing an edited source must not merge an existing control word
-- with a newly adjacent letter. Spaces here delimit control words in TeX.
local function control_word_at_end(text)
  local start = text:match("()\\[A-Za-z]+$")
  if not start then
    return false
  end
  local slashes = 1
  while start > 1 and text:sub(start - 1, start - 1) == "\\" do
    slashes, start = slashes + 1, start - 1
  end
  return slashes % 2 == 1
end

function Scanner:result()
  table.sort(self.edits, function(a, b) return a.first < b.first end)
  local pieces, tail, cursor = {}, "", 1
  local function append(text)
    if text == "" then
      return
    end
    if control_word_at_end(tail) and text:match("^[A-Za-z]") then
      pieces[#pieces + 1] = " "
      tail = tail .. " "
    end
    pieces[#pieces + 1] = text
    tail = tail .. text
    -- Keep only a suffix capable of forming a control word at the next seam.
    tail = tail:match("(\\*[A-Za-z]*)$") or ""
  end
  for _, edit in ipairs(self.edits) do
    append(self.text:sub(cursor, edit.first - 1))
    append(edit.text)
    cursor = edit.last + 1
  end
  append(self.text:sub(cursor))
  return table.concat(pieces)
end

function expand.transform(text, filename)
  local scanner = setmetatable({
    text = text, filename = filename, edits = {}, depth = 0,
    directory = filename:match("^(.*[/\\])") or "./",
  }, Scanner)
  local position, groups = 1, {}
  while position <= #text do
    local char = text:sub(position, position)
    if char == "%" then
      position = scanner:comment(position)
    elseif char == "{" then
      groups[#groups + 1] = position
      scanner.depth, position = scanner.depth + 1, position + 1
    elseif char == "}" then
      if scanner.depth == 0 then
        scanner:fail(position, "unmatched '}'")
      end
      groups[#groups] = nil
      scanner.depth, position = scanner.depth - 1, position + 1
    elseif char == "\\" then
      local name, after = scanner:command(position)
      if name == "verb" then
        position = scanner:verb(position, after)
      elseif name == "begin" or name == "end" then
        position = scanner:environment(position, after, name == "begin")
      elseif name == "usepackage" or name == "RequirePackage" then
        position = scanner:package(position, after)
      elseif name == "includecff" then
        position = scanner:include(position, after)
      elseif name == "cff" then
        position = scanner:field(position, after)
      elseif name:match("^cff") then
        scanner:fail(position, "unsupported cfflatex command: \\" .. name)
      elseif unsupported[name] or name:match("^[iI]f") then
        scanner:fail(position, "unsupported TeX construct: \\" .. name)
      else
        position = after
      end
    elseif char == "^" and text:sub(position, position + 1) == "^^" then
      scanner:fail(position, "TeX ^^ character notation is not supported")
    else
      position = position + 1
    end
  end
  if scanner.depth ~= 0 then
    scanner:fail(groups[#groups], "unclosed '{'")
  end
  return scanner:result()
end

return expand

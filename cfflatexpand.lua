-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 cffLaTeX contributors
-- Source-preserving expansion of CFF accessors and metadata loops.

local data = require("cfflatex-data")
local expand = {}
local Scanner = {}
Scanner.__index = Scanner
local join

local accessors = {
  cff = 1, cffcount = 1, cffauthor = 2, cffcontact = 2,
  cffauthoraffiliationcount = 1, cffauthoraffiliation = 2,
  cffconvertaffiliationindex = 2, cffaffiliationcount = 0, cffaffiliation = 1,
  cffauthorindex = 0, cffaffiliationindex = 0,
  cffauthoraffiliationindex = 0, cffcontactindex = 0,
  cffauthornames = 0,
}
local loops = {
  cffforeachauthor = "author", cffforeachaffiliation = "affiliation",
  cffforeachauthoraffiliation = "authoraffiliation", cffforeachcontact = "contact",
}
local indices = {
  cffauthorindex = "cffforeachauthor", cffaffiliationindex = "cffforeachaffiliation",
  cffauthoraffiliationindex = "cffforeachauthoraffiliation",
  cffcontactindex = "cffforeachcontact",
}

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
  newif unless csname endcsname catcode makeatletter makeatother
  ExplSyntaxOn ExplSyntaxOff begingroup endgroup bgroup egroup
  expandafter noexpand unexpanded detokenize string meaning scantokens expanded
  uppercase lowercase
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
  while position <= self.limit do
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
  local pattern = self.author_render and "^\\([A-Za-z@_:]+)" or "^\\([A-Za-z]+)"
  local name = self.text:match(pattern, position)
  if name then
    return name, position + #name + 1
  end
  return self.text:sub(position + 1, position + 1), position + 2
end

-- Arguments retain their source offsets. Braces protect optional-argument
-- delimiters; escaped braces and delimiters inside comments do not balance.
function Scanner:argument(position, opening, closing)
  position = self:skip(position)
  if position > self.limit or self.text:sub(position, position) ~= opening then
    self:fail(position, "expected '" .. opening .. "'")
  end
  local start, braces, brackets = position, 0, 1
  position = position + 1
  while position <= self.limit do
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
      if self.package_loaded or self.depth > 0 or self.body
        or self.loop_depth > 0 or #self.conditions > 0 then
        self:fail(position, "cfflatex must be loaded once at the top level of the preamble")
      end
      if options then
        -- The check does not affect the output; the style is the default of
        -- \cffsetauthors, which the author renderer must receive.
        for option in (self:literal(options) .. ","):gmatch("([^,]*),") do
          local value = option:match("^%s*(.-)%s*$")
          local style = value:match("^style%s*=%s*(.-)$")
          if style then
            if not style:match("^[A-Za-z0-9][-A-Za-z0-9_]*$") then
              self:fail(options.first, "invalid author style name '" .. style .. "'")
            end
            self.document_style = style
          elseif value ~= "" and value ~= "check" and value ~= "check=true"
            and value ~= "check=false" then
            self:fail(options.first,
              "only literal check, check=true, check=false and style=NAME options are supported")
          end
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
  if self.depth > 0 or self.body or self.loop_depth > 0 or #self.conditions > 0 then
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

-- A zero-argument control word discards its following whitespace in TeX.
-- Preserve a second line ending: an empty line is a paragraph, not a space.
function Scanner:word_end(position)
  local newline
  while position <= self.limit do
    local char = self.text:sub(position, position)
    if char == " " or char == "\t" then
      position = position + 1
    elseif char == "\r" or char == "\n" then
      if newline then
        return newline, true
      end
      newline = position
      position = position + (self.text:sub(position, position + 1) == "\r\n" and 2 or 1)
    else
      break
    end
  end
  return position
end

function Scanner:word_value(value, after)
  local ending, paragraph = self:word_end(after)
  -- A literal digit would turn the first newline into a space. Comment out
  -- that ignored newline while retaining the blank line's paragraph token.
  return value .. (paragraph and "%" or ""), ending
end

-- Expand only known accessors inside paths and integer expressions. A
-- named author/contact field is literal, as \tl_to_str:n makes it in TeX.
function Scanner:operand(argument)
  local raw = self.text:sub(argument.first, argument.last):gsub("\r\n", "\n"):gsub("\r", "\n")
  if raw:find("\n[ \t]*\n") then
    self:fail(argument.first, "paragraph breaks are not supported inside paths and indices")
  end
  local limit = self.limit
  self.limit = argument.last
  local pieces, position = {}, argument.first
  while position <= argument.last do
    local char = self.text:sub(position, position)
    if char == "%" then
      position = self:comment(position)
      while self.text:sub(position, position):match("[ \t]") do
        position = position + 1
      end
    elseif char == "\\" then
      local name, after = self:command(position)
      if not accessors[name] then
        self:fail(position, "only CFF accessors are supported inside paths and indices")
      end
      local value
      value, position = self:access(name, position, after)
      pieces[#pieces + 1] = value
    elseif char:match("[{}#$&~^]") then
      self:fail(position, "expected a literal path or decimal integer expression")
    else
      pieces[#pieces + 1] = char
      position = position + 1
    end
  end
  self.limit = limit
  return (table.concat(pieces):gsub("%s+", " "))
end

-- A bounded decimal subset of \int_eval:n, with TeX's nearest-integer
-- division (ties away from zero). Never evaluate user text as Lua code.
function Scanner:integer(text, position)
  local cursor = 1
  local function skip()
    cursor = text:find("%S", cursor) or #text + 1
  end
  local function checked(value)
    if math.abs(value) > 2147483647 then
      self:fail(position, "integer expression is outside TeX's range")
    end
    return value
  end
  local expression, primary, term
  function primary()
    skip()
    local char = text:sub(cursor, cursor)
    if char == "+" or char == "-" then
      cursor = cursor + 1
      return checked((char == "-" and -1 or 1) * primary())
    elseif char == "(" then
      cursor = cursor + 1
      local value = expression()
      skip()
      if text:sub(cursor, cursor) ~= ")" then
        self:fail(position, "unclosed '(' in integer expression")
      end
      cursor = cursor + 1
      return value
    end
    local number = text:match("^(%d+)", cursor)
    if not number then
      self:fail(position, "expected a decimal integer expression")
    end
    cursor = cursor + #number
    return checked(tonumber(number))
  end
  function term()
    local value = primary()
    while true do
      skip()
      local operator = text:sub(cursor, cursor)
      if operator ~= "*" and operator ~= "/" then
        return value
      end
      cursor = cursor + 1
      local right = primary()
      if operator == "*" then
        value = checked(value * right)
      else
        if right == 0 then
          self:fail(position, "division by zero in integer expression")
        end
        local numerator, denominator = math.abs(value), math.abs(right)
        local quotient, remainder = numerator // denominator, numerator % denominator
        if remainder >= denominator - remainder then
          quotient = quotient + 1
        end
        value = checked((value < 0) ~= (right < 0) and -quotient or quotient)
      end
    end
  end
  function expression()
    local value = term()
    while true do
      skip()
      local operator = text:sub(cursor, cursor)
      if operator ~= "+" and operator ~= "-" then
        return value
      end
      cursor = cursor + 1
      local right = term()
      value = checked(operator == "+" and value + right or value - right)
    end
  end
  local value = expression()
  skip()
  if cursor <= #text then
    self:fail(position, "expected a decimal integer expression")
  end
  return value
end

function Scanner:index(argument, maximum, label, position)
  local index = self:integer(self:operand(argument), position)
  if index < 1 or index > maximum then
    self:fail(position, label .. " index '" .. index .. "' is out of range")
  end
  return index
end

function Scanner:access(name, position, after)
  if name == "cffauthornames" then
    if self.author_names == nil then
      self:fail(position, "call \\cffsetauthors before \\cffauthornames")
    end
    return self:word_value(self.author_names, after)
  end
  if indices[name] then
    local value = self.indices[name]
    if not value then
      self:fail(position, "\\" .. name .. " is only valid inside \\" .. indices[name])
    end
    return self:word_value(tostring(value), after)
  end
  if not self.model then
    self:fail(position, "call \\includecff before \\" .. name)
  end
  local arguments, ending = {}, after
  for index = 1, accessors[name] do
    arguments[index], ending = self:argument(ending, "{", "}")
  end
  local model = self.model
  local value
  if name == "cff" or name == "cffcount" then
    local path = self:operand(arguments[1])
    if name == "cff" then
      if model.fields[path] == nil and model.kinds[path] ~= nil then
        self:fail(position, "not a value: " .. path)
      end
      value = model.fields[path] or ""
    else
      if model.kinds[path] == "map"
        or (model.kinds[path] == nil and model.fields[path] ~= nil) then
        self:fail(position, "not a list: " .. path)
      end
      value = tostring(model.kinds[path] or 0)
    end
  elseif name == "cffaffiliationcount" then
    value = model.values["affiliation-count"]
  elseif name == "cffaffiliation" then
    local index = self:index(arguments[1], #model.affiliations, "affiliation", position)
    value = model.values["affiliations/" .. index]
  else
    local contact = name == "cffcontact"
    local index = self:index(arguments[1], contact and model.contact_count
      or #model.citation.authors, contact and "contact" or "author", position)
    local prefix = (contact and "contact/" or "authors/") .. index .. "/"
    if name == "cffauthor" or contact then
      value = model.values[prefix .. self:literal(arguments[2])] or ""
    elseif name == "cffauthoraffiliationcount" then
      value = model.values[prefix .. "affiliation-count"] or "0"
    else
      local count = self:integer(model.values[prefix .. "affiliation-count"] or "0", position)
      local affiliation = self:index(arguments[2], count, "affiliation", position)
      local field = name == "cffconvertaffiliationindex" and "indices/" or "names/"
      value = model.values[prefix .. "affiliation-" .. field .. affiliation] or ""
    end
  end
  if accessors[name] == 0 then
    return self:word_value(value, ending)
  end
  return value, ending
end

-- Keep the protected footnote operation used by both native author styles.
-- Inlining its body would expand it too early in authblk's author collection.
local thanks_definition = [[\protected\long\def\@cfflatexpand@thanks#1{%
\stepcounter{footnote}%
\protected@xdef\@thefnmark{\thefootnote}%
\@thefnmark
\protected@xdef\@thanks{%
\@thanks\protect\footnotetext[\number\value{footnote}]{#1}}}
]]

function Scanner:author_fragment(text, names)
  local child = setmetatable({
    text = text, filename = "[author template]", depth = 0, loop_depth = 0,
    indices = {}, model = self.model, author_render = true, author_names = names,
  }, Scanner)
  local result = child:scan(1, #text)
  return result, child.needs_thanks
end

-- Templates are TeX, not Lua expressions. Check the same lexical restrictions
-- before passing them to the existing renderer; getters may be partial (#1).
function Scanner:author_options(argument)
  local position = argument.first
  while position <= argument.last do
    local char = self.text:sub(position, position)
    if char == "%" then
      position = self:comment(position)
    elseif char == "\\" then
      local name, after = self:command(position)
      if unsupported[name] or (name:match("^[iI]f") and name ~= "ifnum" and name ~= "ifodd")
        or name == "cffsetauthors" or name == "includecff"
        or name == "usepackage" or name == "RequirePackage"
        or name == "begin" or name == "end"
        or (name:match("^cff") and not accessors[name] and not loops[name]) then
        self:fail(position, "unsupported TeX construct in author options: \\" .. name)
      end
      position = after
    elseif self.text:sub(position, position + 1) == "^^" then
      self:fail(position, "TeX ^^ character notation is not supported")
    else
      position = position + 1
    end
  end
  return self.text:sub(argument.first, argument.last)
end

function Scanner:set_authors(position, after)
  if not self.model then
    self:fail(position, "call \\includecff before \\cffsetauthors")
  end
  if self.author_render or self.depth > 0 or self.body
    or self.loop_depth > 0 or #self.conditions > 0 then
    self:fail(position, "\\cffsetauthors must be at the top level of the preamble")
  end
  if self.author_names ~= nil then
    self:fail(position, "only one \\cffsetauthors is supported")
  end
  local argument, ending = self:optional(after)
  local options = argument and self:author_options(argument) or ""
  if self.document_style then
    -- A style= in the options of \cffsetauthors comes later and wins.
    options = "style=" .. self.document_style .. "," .. options
  end
  if not argument then
    ending = self:word_end(after)
  end
  local ok, declarations = pcall(function()
    if not self.render_authors then
      error("a TeX author renderer is required for \\cffsetauthors", 0)
    end
    local rendered = self.render_authors(self.model, options)
    self.author_names = self:author_fragment(rendered.names, "")
    local result, needs_thanks = self:author_fragment(rendered.declarations, self.author_names)
    if needs_thanks or result:find("\\[A-Za-z]*@") then
      result = "\\makeatletter\n" .. (needs_thanks and thanks_definition or "")
        .. result .. "\\makeatother\n"
    end
    return result
  end)
  if not ok then
    self:fail(position, tostring(declarations))
  end
  self:edit(position, ending - 1, declarations)
  return ending
end

function Scanner:author_thanks(position, after)
  local argument, ending = self:argument(after, "{", "}")
  local contents = self:scan(argument.first, argument.last)
  self.needs_thanks = true
  self:edit(position, ending - 1, "\\@cfflatexpand@thanks{" .. contents .. "}")
  return ending
end

function Scanner:loop(name, position, after)
  if not self.model then
    self:fail(position, "call \\includecff before \\" .. name)
  end
  local count, ending
  ending = after
  if name == "cffforeachauthoraffiliation" then
    local argument
    argument, ending = self:argument(ending, "{", "}")
    local index = self:index(argument, #self.model.citation.authors, "author", position)
    count = self:integer(self.model.values["authors/" .. index .. "/affiliation-count"]
      or "0", position)
  elseif name == "cffforeachauthor" then
    count = #self.model.citation.authors
  elseif name == "cffforeachaffiliation" then
    count = #self.model.affiliations
  else
    count = self.model.contact_count
  end
  local body
  body, ending = self:argument(ending, "{", "}")
  local key = "cff" .. loops[name] .. "index"
  local previous, parts = self.indices[key], {}
  self.loop_depth = self.loop_depth + 1
  for index = 1, count do
    self.indices[key] = index
    parts[#parts + 1] = self:scan(body.first, body.last)
  end
  self.indices[key] = previous
  self.loop_depth = self.loop_depth - 1
  self:edit(position, ending - 1, join(parts))
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
  if not ending or ending > self.limit or (newline and newline < ending) then
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
    if not terminator or terminator + #marker - 1 > self.limit then
      self:fail(position, "unclosed " .. name .. " environment")
    end
    return terminator + #marker
  end
  if name == "document" then
    if self.loop_depth > 0 or self.depth > 0 or #self.conditions > 0 then
      self:fail(position, "document boundaries must be outside groups, loops, and conditionals")
    end
    if begin then
      self.body = true
    else
      return self.limit + 1 -- TeX does not read beyond \end{document}.
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

function join(parts)
  local pieces, tail = {}, ""
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
  for _, part in ipairs(parts) do
    append(part)
  end
  return table.concat(pieces)
end

function Scanner:result(first, last)
  table.sort(self.edits, function(a, b) return a.first < b.first end)
  local parts, cursor = {}, first
  for _, edit in ipairs(self.edits) do
    parts[#parts + 1] = self.text:sub(cursor, edit.first - 1)
    parts[#parts + 1] = edit.text
    cursor = edit.last + 1
  end
  parts[#parts + 1] = self.text:sub(cursor, last)
  return join(parts)
end

function Scanner:condition(name, position)
  if name == "ifnum" or name == "ifodd" then
    self.conditions[#self.conditions + 1] = {position = position}
  elseif #self.conditions == 0 then
    self:fail(position, "unmatched \\" .. name)
  elseif name == "else" then
    local current = self.conditions[#self.conditions]
    if current.has_else then
      self:fail(position, "duplicate \\else")
    end
    current.has_else = true
  else
    self.conditions[#self.conditions] = nil
  end
end

-- Each loop body is scanned in its original source range. Local edit and
-- conditional stacks keep nested loops independent and errors at their
-- original location, without constructing a second source with fake offsets.
function Scanner:scan(first, last)
  local saved_edits, saved_limit, saved_conditions = self.edits, self.limit, self.conditions
  self.edits, self.limit, self.conditions = {}, last, {}
  local position, groups, text = first, {}, self.text
  while position <= last do
    local char = text:sub(position, position)
    if char == "%" then
      position = self:comment(position)
    elseif char == "{" then
      groups[#groups + 1] = position
      self.depth, position = self.depth + 1, position + 1
    elseif char == "}" then
      if #groups == 0 then
        self:fail(position, "unmatched '}'")
      end
      groups[#groups] = nil
      self.depth, position = self.depth - 1, position + 1
    elseif char == "\\" then
      local name, after = self:command(position)
      if name == "verb" then
        position = self:verb(position, after)
      elseif name == "begin" or name == "end" then
        position = self:environment(position, after, name == "begin")
      elseif name == "usepackage" or name == "RequirePackage" then
        position = self:package(position, after)
      elseif name == "includecff" then
        position = self:include(position, after)
      elseif name == "cffsetauthors" then
        position = self:set_authors(position, after)
      elseif name == "cffdeclareauthorstyle" then
        self:fail(position, "inline author styles are not supported; "
          .. "put the definition in cfflatex-style-NAME.def")
      elseif self.author_render and name == "__cfflatex_thanks:n" then
        position = self:author_thanks(position, after)
      elseif self.author_render and name == "protect" then
        local following = self:skip(after)
        local next_name = self:command(following)
        if accessors[next_name] or loops[next_name] then
          self:edit(position, following - 1)
        end
        position = after
      elseif accessors[name] then
        local value, ending = self:access(name, position, after)
        self:edit(position, ending - 1, value)
        position = ending
      elseif loops[name] then
        position = self:loop(name, position, after)
      elseif name:match("^cff") or (self.author_render and name:match("^__cfflatex")) then
        self:fail(position, "unsupported cfflatex command: \\" .. name)
      elseif name == "ifnum" or name == "ifodd" or name == "else" or name == "fi" then
        self:condition(name, position)
        position = after
      elseif name == "input" or name == "include" or name == "includeonly" then
        self:fail(position, "external TeX inputs are not supported; first flatten the document with latexpand")
      elseif unsupported[name] or name:match("^[iI]f") then
        self:fail(position, "unsupported TeX construct: \\" .. name)
      else
        position = after
      end
    elseif char == "^" and text:sub(position, position + 1) == "^^" then
      self:fail(position, "TeX ^^ character notation is not supported")
    else
      position = position + 1
    end
  end
  if #groups ~= 0 then
    self:fail(groups[#groups], "unclosed '{'")
  end
  if #self.conditions ~= 0 then
    self:fail(self.conditions[#self.conditions].position, "unclosed numeric conditional")
  end
  local result = self:result(first, last)
  self.edits, self.limit, self.conditions = saved_edits, saved_limit, saved_conditions
  return result
end

function expand.transform(text, filename, render_authors)
  local scanner = setmetatable({
    text = text, filename = filename, depth = 0, loop_depth = 0, indices = {},
    directory = filename:match("^(.*[/\\])") or "./",
    render_authors = render_authors,
  }, Scanner)
  return scanner:scan(1, #text)
end

return expand

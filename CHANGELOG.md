# Changelog

All notable changes to import-citation-cff are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.0] - 2026-11-08

The package is renamed from cffLaTeX to import-citation-cff.

### Changed

- `cfflatex.sty` is renamed to `import-citation-cff.sty`. Load the package
  with `\usepackage{import-citation-cff}`. Messages, the key and hook labels,
  and the manual (`import-citation-cff.pdf`) use the new name.
- The CTAN and TDS archives install into `import-citation-cff` directories.
- Support files keep the prefix `cfflatex`: `cfflatex.lua`, `cfflatex-data.lua`,
  and `cfflatex-style-NAME.def`. The `cfflatexpand` command is unchanged.

## [0.2.0] - 2026-11-07

### Added

- Author styles can be registered with `\cffdeclareauthorstyle` and loaded
  automatically from `cfflatex-style-NAME.def`. Standard and authblk are
  built-in plugins using the same API. Plugins support declaration templates,
  lifecycle hooks, package requirements, executable templates, and custom
  renderers. File-based plugins also work with `cfflatexpand`.
- The Lua `cfflatexpand` CLI expands CFF fields, counts, author, affiliation,
  and contact accessors, and metadata loops, and removes CFF loading commands.
  It supports stdout and `--output`/`-o` output, source-location diagnostics,
  decimal integer expressions, nested loop indices, and preservation of
  ordinary source, numeric conditionals, comments, and verbatim.
- A shared CFF data module supplies the same validation, affiliation
  normalization, and TeX character escaping to the package and export tool.
- The exporter converts `\cffsetauthors` and `\cffauthornames` using the
  package's author renderer, including standard and authblk styles, custom
  templates, affiliation marks, contact footnotes, and repeated notes.
  Author conversion runs LuaLaTeX with shell escape disabled. The exported
  declarations compile without cfflatex or the CFF file.
- CTAN and TDS archives include the executable `cfflatexpand` command and all
  required Lua modules. `l3build install` installs them into a local TeX tree.
  CI tests the installed command, and CD tests the built TDS archive before release.
- The `style` package option sets the author style of the document, which
  `\cffsetauthors` selects by default and the title page check follows. Author
  styles can choose the checked fields with `check-fields`, such as `abstract`,
  and the checked regions with `check-region`: `\maketitle`, the code between
  two LaTeX hooks, or the whole document as a fallback. This checks title
  blocks typeset without `\maketitle`. `cfflatexpand` accepts the option.
- The built-in `rsc` author style supports the article template of the Royal
  Society of Chemistry. It defines `\rscauthors`, the author line with the
  marks of contacts, affiliations, and notes, and `\rscfootnotes`, their
  footnotes, and checks the title, the authors, and the abstract in the title
  block of the template. Declarations of author styles may define commands
  with `\newcommand`, which `cfflatexpand` exports.

### Changed

- The check checks only the first `\maketitle`, or the first region of the
  author style that closes, instead of every `\maketitle`.

### Fixed

- User options to `\cffsetauthors` override style defaults regardless of the
  position of `style=` in the option list.
- With authblk, authors with footnotes and no affiliations no longer execute
  their first footnote while the author list is being declared.

## [0.1.0] - 2026-11-06

First release.

### Added

- `\includecff[source=key]{file}` reads the top level of a CFF file, or the
  mapping under its top-level `key`, such as `preferred-citation`.
- `\cff{path}` expands to any value of the citation by its path, such as
  `title` or `authors/1/family-names`, and `\cffcount{path}` to the length of
  a list, such as `\cffcount{authors}`.
- `\cffauthor{index}{field}` expands to the author fields of the selected citation.
- `\cffforeachauthor{code}` runs `code` for each author, with `\cffauthorindex` expanding to the index of the current author.
- `\cffauthoraffiliationcount` and `\cffauthoraffiliation` read author affiliations separated by semicolons.
- `\cffconvertaffiliationindex{index}{k}` converts the index of an author's affiliation to its number among the distinct affiliations of the citation.
- `\cffaffiliationcount` and `\cffaffiliation` parse all distinct affiliations of all authors in the order they first appear.
- `\cffforeachauthoraffiliation{index}{code}` runs `code` for each affiliation of an author, with `\cffauthoraffiliationindex` expanding to its index among those of the author.
- `\cffforeachaffiliation{code}` for each distinct affiliation, with `\cffaffiliationindex` expanding to its number.
- `\cffcontact{index}{field}` reads the contacts of the citation, and
  `\cffforeachcontact{code}` runs `code` for each of them, with
  `\cffcontactindex` expanding to the index of the current contact.
- `\cffsetauthors[keys]` declares the authors for `\maketitle`, marked with their affiliations and with email footnotes for the contacts among them, for the standard classes or, with `style=authblk`, for the authblk package.
- `\cffauthornames` expands to the names `\cffsetauthors` makes.
- The `check` package option, on by default, warns after `\maketitle` unless
  `\title` uses `\cff{title}` and `\author` uses every author of the citation.

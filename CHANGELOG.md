# Changelog

All notable changes to cffLaTeX are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- The initial Lua `cfflatexpand` CLI replaces `\cff{title}` and removes CFF
  loading commands, with stdout and `--output`/`-o` output, source-location
  diagnostics, and preservation of ordinary source, comments, and verbatim.
- A shared CFF data module supplies the same validation, affiliation
  normalization, and TeX character escaping to the package and export tool.

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

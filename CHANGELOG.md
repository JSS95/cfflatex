# Changelog

All notable changes to cffLaTeX are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased

First release.

### Added

- `\includecff[source=key]{file}` reads the top level of a CFF file, or the
  mapping under its top-level `key`, such as `preferred-citation`.
- `\cfftitle` and `\cffabstract` expand to the title and abstract of the selected citation.
- `\cffauthor{index}{field}` expands to the author fields of the selected citation.
- `\cffauthorcount` expands to the number of authors of the selected citation.
- `\cffforeachauthor{code}` runs `code` for each author, with `\cffauthorindex` expanding to the index of the current author.
- `\cffauthoraffiliationcount` and `\cffauthoraffiliation` read author affiliations separated by semicolons.
- `\cffaffiliationcount` and `\cffaffiliation` parse all distinct affiliations of all authors in the order they first appear.
- `\cffforeachauthoraffiliation{index}{code}` runs `code` for each affiliation of an author, with `\cffauthoraffiliationindex` expanding to its index among those of the author.
- `\cffforeachaffiliation{code}` for each distinct affiliation, with `\cffaffiliationindex` expanding to its number.
- The `check` package option, on by default, warns after `\maketitle` unless
  `\title` uses `\cfftitle` and `\author` uses every author of the citation.

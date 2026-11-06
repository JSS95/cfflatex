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
- `\cffforeachauthor{code}` runs `code` for each author, with `\cffauthorindex`
  expanding to the index of the current author.

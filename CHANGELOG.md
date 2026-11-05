# Changelog

All notable changes to cffLaTeX are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased

First release.

### Added

- `\includecff[source=root|preferred-citation]{file}` reads a CFF file.
- `\cfftitle` and `\cffauthor{index}{field}` expand to the title and author
  fields of the selected citation.

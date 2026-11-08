# import-citation-cff: Import CFF metadata into LaTeX

With `import-citation-cff`, you don't need to write your metadata twice!

This package imports metadata from `CITATION.cff` into your document, with customizable author list typesetting.

## Requirements

- LuaLaTeX, or pdfLaTeX with `--shell-escape`
- The `lt3luabridge` and `lua-tinyyaml` packages
- TeX Live 2025 or later

## Installation

import-citation-cff is available on [CTAN](https://ctan.org/pkg/import-citation-cff).
In TeX Live, install it with:

```sh
tlmgr install import-citation-cff
```

For manual installation, see the Installation section of the [manual](https://jss95.github.io/cfflatex/import-citation-cff.pdf).

## Quick start

Given a `CITATION.cff` containing:

```yaml
cff-version: 1.2.0
message: Please cite the paper in preferred-citation.
type: software
title: My Paper Code
authors:
    - family-names: Doe
      given-names: John
preferred-citation:
  type: article
  title: My Paper
  abstract: My paper abstract.
  authors:
    - family-names: Doe
      given-names: Jane
    - family-names: Doe
      given-names: John
```

Write:

```latex
\documentclass{article}
\usepackage[T1]{fontenc}
\usepackage{import-citation-cff}

%\includecff{CITATION.cff}  % reads fields in top level
\includecff[source=preferred-citation]{CITATION.cff}  % reads fields in preferred-citation
\title{\cff{title}}
\author{
  \cffauthor{1}{given-names}~\cffauthor{1}{family-names}
  \and
  \cffauthor{2}{given-names}~\cffauthor{2}{family-names}
}
\date{}

\begin{document}
\maketitle
\begin{abstract}
  \cff{abstract}
\end{abstract}
\end{document}
```

Compile with either:

```sh
pdflatex --shell-escape manuscript.tex
lualatex manuscript.tex
```

To expand CFF variables:

```sh
cfflatexpand manuscript.tex > submission.tex
```

## Documentation

The latest document can be found at:

> https://jss95.github.io/cfflatex/import-citation-cff.pdf

### Building the document

Run:

```sh
l3build doc
```

The manual is `import-citation-cff.pdf`.

## Development

### Lint

Requires:

* [badness](https://pypi.org/project/badness/)
* [expltools](https://ctan.org/pkg/expltools)
* [lua-check](https://github.com/lunarmodules/luacheck)
* [Ruff](https://docs.astral.sh/ruff/)

```sh
badness format .
badness lint .
explcheck --warnings-are-errors import-citation-cff.sty cfflatex-style-*.def
luacheck . cfflatexpand
ruff format .
ruff check .
python3 .ci/check_versions.py
```

### Test

Run the LaTeX regression tests and the standalone export CLI tests.

```sh
l3build check
texlua tests/test_cfflatexpand.lua --installed  # installs the package into a temporary TeX tree and tests the command there
texlua tests/test_expand_manual.lua
```

### Build

[l3build](https://ctan.org/pkg/l3build) builds the manual and the CTAN archive:

```sh
l3build doc     # import-citation-cff.pdf
l3build ctan    # import-citation-cff-<version>.zip
```

`l3build ctan` also writes the ready-to-install TDS archive, which is not packed into the CTAN archive.
Test that archive with:

```sh
texlua tests/test_cfflatexpand.lua --tds build/distrib/tds/import-citation-cff.tds.zip
```

## License

import-citation-cff is distributed under the MIT License.
Report bugs at <https://github.com/JSS95/cfflatex/issues>.

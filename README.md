# import-citation-cff: Import CFF metadata into LaTeX

With `import-citation-cff`, you don't need to write your metadata twice.
This package imports metadata from `CITATION.cff` into your document, with customizable author list typesetting.

## Requirements

- LuaLaTeX, or pdfLaTeX with `--shell-escape`
- The `lt3luabridge` and `lua-tinyyaml` packages
- TeX Live 2025 or later

## Installation

Install `import-citation-cff.sty`, `cfflatex-style-*.def`, `cfflatex.lua`, and `cfflatex-data.lua`
in a local TeX tree such as `~/texmf/tex/latex/import-citation-cff/`.
The support files use the short prefix `cfflatex`.
Alternatively, you can put them next to your document.

To install both the package and the `cfflatexpand` command from a source checkout:

```sh
l3build install --texmfhome "$HOME/texmf"
```

Each [GitHub release](https://github.com/JSS95/cfflatex/releases) also attaches `import-citation-cff.tds.zip`.
As an alternative to installing from source, extract that archive into your local TeX tree.
The archive of a particular release installs that version, which takes precedence over the one in your TeX distribution:

```sh
mkdir -p "$HOME/texmf"
unzip import-citation-cff.tds.zip -d "$HOME/texmf"
```

Both methods place the package and Lua modules in `tex/latex/import-citation-cff/` and the command in `scripts/import-citation-cff/`.
To make the command available in a POSIX shell:

```sh
export PATH="$HOME/texmf/scripts/import-citation-cff:$PATH"
cfflatexpand --help
```

Add the `export` line to your shell configuration to keep it for future sessions.
You can also run the script with `texlua` and its full path, without changing `PATH`.

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

Run the LaTeX regression tests and the standalone export CLI tests:

```sh
l3build check   # tests with pdfLaTeX and LuaLaTeX
texlua tests/test_cfflatexpand.lua  # export CLI tests
texlua tests/test_cfflatexpand.lua --installed  # temporary TeX-tree installation
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

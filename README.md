# cffLaTeX: Import your CFF file into your LaTeX document

With cffLaTeX, you don't need to write your paper metadata twice.

## Requirements

- LuaLaTeX, or pdfLaTeX with `--shell-escape`
- The `lt3luabridge` and `lua-tinyyaml` packages
- TeX Live 2025 or later

## Installation

Install `cfflatex.sty`, `cfflatex.lua`, and `cfflatex-data.lua` in a local TeX tree such as `~/texmf/tex/latex/cfflatex/`.
Alternatively, you can put them next to your document.

To install both the package and the `cfflatexpand` command from a source checkout:

```sh
l3build install --texmfhome "$HOME/texmf"
```

The CTAN archive also includes `cfflatex.tds.zip`.
As an alternative to installing from source, extract that archive into your local TeX tree:

```sh
mkdir -p "$HOME/texmf"
unzip cfflatex.tds.zip -d "$HOME/texmf"
```

Both methods place the package and Lua modules in `tex/latex/cfflatex/` and the command in `scripts/cfflatex/`.
To make the command available in a POSIX shell:

```sh
export PATH="$HOME/texmf/scripts/cfflatex:$PATH"
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
\usepackage{cfflatex}

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

> https://jss95.github.io/cfflatex/cfflatex.pdf

### Building the document

Run:

```sh
l3build doc
```

The manual is `cfflatex.pdf`.

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
explcheck --warnings-are-errors cfflatex.sty
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
l3build doc     # cfflatex.pdf
l3build ctan    # cfflatex-<version>.zip
```

The CTAN archive includes the ready-to-install `cfflatex.tds.zip`, which is also
written beside it. Test that archive with:

```sh
texlua tests/test_cfflatexpand.lua --tds cfflatex.tds.zip
```

## License

cffLaTeX is distributed under the MIT License.
Report bugs at <https://github.com/JSS95/cfflatex/issues>.

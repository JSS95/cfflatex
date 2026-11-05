# cffLaTeX: Import CFF file into your LaTeX document

With cffLaTeX, you don't need to write your paper metadata twice.

## Requirements

- LuaLaTeX, or pdfLaTeX with `--shell-escape`
- The `lt3luabridge` and `lua-tinyyaml` packages
- TeX Live 2025 or later

## Installation

Install `cfflatex.sty` and `cfflatex.lua` in a local TeX tree such as
`~/texmf/tex/latex/cfflatex/`, or put them next to your document.

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

%\includecff[source=root]{CITATION.cff}  % reads fields in top level
\includecff{CITATION.cff}  % reads fields in preferred-citation
\title{\cfftitle}
\author{
  \cffauthor{1}{given-names}~\cffauthor{1}{family-names}
  \and
  \cffauthor{2}{given-names}~\cffauthor{2}{family-names}
}
\date{}

\begin{document}
\maketitle
\end{document}
```

Compile with either:

```sh
pdflatex --shell-escape manuscript.tex
lualatex manuscript.tex
```

## Documentation

The manual, `cfflatex.pdf`, describes every command, the errors, and the
limitations. Open it with `texdoc cfflatex` when the package is installed from
CTAN, or build it with `l3build doc`.

## Development

[l3build](https://ctan.org/pkg/l3build) runs the tests and builds the manual
and the CTAN archive:

```sh
l3build check   # tests with pdfLaTeX and LuaLaTeX
l3build doc     # cfflatex.pdf
l3build ctan    # cfflatex-ctan.zip
```

## License

cffLaTeX is distributed under the MIT License; see `LICENSE`. Report bugs at
<https://github.com/JSS95/cfflatex/issues>.

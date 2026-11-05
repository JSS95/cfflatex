# cffLaTeX: Import CFF file into your LaTeX document

With cffLaTeX, you don't need to write your paper metadata twice.

## Requirements

- `lt3luabridge`
- `lua-tinyyaml`
- pdfLaTeX with `--shell-escape` or LuaLaTeX.

## Installation

Install `cfflatex.sty` and `cfflatex.lua` in a local TeX tree such as `~/texmf/tex/latex/cfflatex/`.

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

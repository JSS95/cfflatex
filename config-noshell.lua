-- Tests that pdfLaTeX without shell escape fails with a clear message.
testfiledir = "./testfiles-noshell"
checkengines = {"pdftex"}
checkopts = "-interaction=nonstopmode --no-shell-escape"
supportdir = testfiledir .. "/support"

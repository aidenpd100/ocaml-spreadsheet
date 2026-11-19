Menhir’s calc demo
copied from the Menhir source via opam source menhir.

Runing it
    => dune exec demo/menhir/calc.exe.

    you can type math expressions like:
    1 + 2
    2 * 4 * 1 + 7
    and then hit enter to get the result printer

The following was the original README.md
---------------------------------------------------------------------------

This tiny program reads arithmetic expressions from the standard input
channel. Each expression is expected to be complete when the current line
ends. Its value is then displayed on the standard output channel. This
code is adapted from ocamlyacc's documentation.

We compile the parser using Menhir's code back-end. (The compilation
process is described in the `dune` file.)

For an example of using Menhir's table back-end, see the demos
`calc-incremental` and `calc-inspection`.

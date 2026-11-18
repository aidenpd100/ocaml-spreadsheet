(lang dune 3.24)
(using menhir 3.0)

(generate_opam_files true)

(package
 (name ocaml_spreadsheet)
 (allow_empty)
 (synopsis "A web spreadsheet with a dependency-graph recalculation engine")
 (description "Cells hold numbers, text, or formulas. Formulas are parsed with Menhir, and a dependency graph decides what to recalculate when a cell changes.")
 (depends
  (ocaml (>= 5.5.0))
  core
  ppx_jane
  menhir
  ounit2
  ))
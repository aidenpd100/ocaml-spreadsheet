(lang dune 3.0)
(using menhir 2.1)

(name camlsheet)
(generate_opam_files true)

(package
 (name camlsheet)
 (synopsis "A web spreadsheet with incremental recalculation, written in OCaml")
 (depends
  (ocaml (>= 5.0))
  dune
  core
  ppx_jane
  yojson
  ppx_yojson_conv
  menhir
  dream
  lwt
  (ounit2 :with-test)
  (qcheck-core :with-test)
  (qcheck-ounit :with-test)
  (bisect_ppx :with-test)))

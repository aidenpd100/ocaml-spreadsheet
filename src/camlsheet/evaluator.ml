open Core

type error = Div_zero | Parse | Name | Value | Cycle
[@@deriving equal, sexp]

type value =
  | VNum of float
  | VText of string
  | VEmpty
  | VError of error
[@@deriving equal, sexp]

let eval _lookup _e = failwith "TODO"

let value_to_grid_display _v = failwith "TODO"
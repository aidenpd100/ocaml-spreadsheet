(** Errors a cell can show. *)
type error =
  | Div_zero  (** [#DIV/0]: 0 in the denominator or [AVG] of no numbers *)
  | Parse     (** [#PARSE]: cell text can't be parsed *)
  | Name      (** [#NAME]: unknown function name *)
  | Value     (** [#VALUE]: like doing a math operation with a reference to a text cell *)
  | Cycle     (** [#CYCLE]: cells that depend on each other in a loop *)
[@@deriving equal, sexp]

(** The value of a cell. *)
type value =
  | VNum of float
  | VText of string
  | VEmpty          (** a cell with nothing in it *)
  | VError of error
[@@deriving equal, sexp]

(** [eval lookup e] evaluates [e] to a value.
    [lookup] takes a coord & returns already-computed cell value
    Rules:
    - [VEmpty] is considered 0 for math operations.
    - math operations on [VText] gives [VError Value].
    - valid functions: [SUM] [AVG] [MIN] [MAX] [COUNT].
      range is evaluated as a list - empty & text cells skipped.
      unrecognized function gives [VError Name].
*)
val eval : (Coord.t -> value) -> Ast.expr -> value

(** [value_to_grid_display v] is the format the frontend shows for value [v]:
    [""] for empty
    ["#DIV/0"] for errors
*)
val value_to_grid_display : value -> string
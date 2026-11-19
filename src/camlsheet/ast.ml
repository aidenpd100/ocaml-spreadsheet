open Core

(** basic math operators *)
type binop = Add | Sub | Mul | Div
[@@deriving equal, sexp]              (** getting an equal function for binop
                                          the sexp is gonna make the AST easier to read during debugging *)

(** the cells get parsed into an [expr] which is its own AST *)
type expr =
  | Num of float                      (** Numbers:    1    1.    1.1    .1    *)
  | Str of string                     (** cell text not recognized as a number or formula *)
  | Ref of Coord.t                    (** a reference to another cell by coordinates *)
  | Neg of expr                       (** unary minus *)
  | Binop of binop * expr * expr      (** operator on 2 expressions *)
  | Call of string * arg list         (** function names (stored in uppercase): SUM, AVG, MIN, MAX  args defined below *)

and arg =                             (** arguments for calls; ex: SUM(1, A1:A10, -(MIN(10, -3))) *)
  | Expr of expr                      (** any of the expressions above are valid in a function call *)
  | Range of Coord.t * Coord.t        (** a 2D range of cells where both Coords are opposite corners - ranges are only valid as args *)
[@@deriving equal, sexp]              (** getting an equal function for [expr & arg]
                                          the sexp is gonna make the AST easier to read during debugging *)

let refs _ = failwith "TODO"
let to_string _ = failwith "TODO"
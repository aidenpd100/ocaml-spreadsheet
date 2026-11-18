(** [parse formula] parses a formula w/o leading '='
     uses ocamllex lexer & menhir parser

     errors from the lexer and parser propagate as error messages
     w/ 0-index positions for the position of the error
     [parse "8*9+10"] = [Ok (Binop (Mul, Num 10.0, Binop (Add, Num 20.0, Num 3.0)))]
     [parse "1#2"] = [Error "At offset 1: unexpected character"]
*)
val parse : string -> (Ast.expr, string) result

(** [parse_cell raw_cell_text] converts the cell text into AST's
    leading = -> formula
    just digits + - . -> number
    anything else -> text cell *)
val parse_cell : string -> (Ast.expr, string) result
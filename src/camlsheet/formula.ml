open Core

let parse (formula : string) : (Ast.expr, string) result =
  (* lex buffer - sequence of raw characters w/ a cursor starting from the front *)
  let lexbuf = Lexing.from_string formula in
  (* parsing formula w/ rules from lexer *)
  match Parser.main Lexer.token lexbuf with
  | e -> Ok e                               (* able to parse the formula into tokens & grammar followed *)
  | exception Lexer.Error msg -> Error msg  (* characters don't form a valid token *)
  | exception Parser.Error ->               (* valid tokens but grammar rules violated *)
    Error (sprintf "At offset %d: syntax error" (Lexing.lexeme_start lexbuf))

(* a number has only: digits + - .*)
let looks_like_number (raw_cell_text : string) =
  String.for_all raw_cell_text ~f:(fun c -> Char.is_digit c || String.mem ".+-" c)

let parse_cell raw_cell_text : (Ast.expr, string) result =
  (* stripping whitespace *)
  let cell_text = String.strip raw_cell_text in
  (* seeing if cell has a formula or is just an expression *)
  match String.chop_prefix cell_text ~prefix:"=" with
  | Some formula -> parse formula (* = -> formula *)
  | None -> (* no = -> see if its a number or a string *)
    (match if looks_like_number raw_cell_text then Float.of_string_opt raw_cell_text else None with
     | Some n -> Ok (Ast.Num n)             (* number -> create Num AST singleton *)
     | None -> Ok (Ast.Str raw_cell_text))  (* not a number means its a string -> create Str AST singleton *)
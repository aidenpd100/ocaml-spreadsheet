{
  open Parser

  exception Error of string
}

let digit = ['0'-'9']          (* digit chars 0 - 9 *)
let letter = ['A'-'Z' 'a'-'z'] (* upper and lowercase chars *)
(*
acceptable number formats
1        1.        1.1      .1
*)
let number = digit+ ('.' digit*)? | '.' digit+

(* This rule turns a formula (without its leading '=') into a stream
   of tokens. *)

rule token = parse
| [' ' '\t']
    (* valid whitespace: space & tab *)
    { token lexbuf }

| number as n
    (* number *)
    { NUMBER (float_of_string n) }

| (letter+ digit+) as r
    (* cell reference ex: B1 *)
    { match Coord.is_valid_cell_ref r with
      | Some c -> REF c
      | None ->
        raise (Error (Printf.sprintf "At offset %d: invalid cell reference %s\n"
                        (Lexing.lexeme_start lexbuf) r)) }
| letter+ as function_name
    (* only consecutive letter(s)
       will be tested for being function names *)
    { FUNCTION_NAME function_name }
| '+'
    { PLUS }
| '-'
    { MINUS }
| '*'
    { STAR }
| '/'
    { SLASH }
| '('
    { LPAREN }
| ')'
    { RPAREN }
| ','
    { COMMA }
| ':'
    { COLON }
| eof
    (* unlike the demo, end of file is the normal way a formula ends *)
    { EOF }
| _
    { raise (Error (Printf.sprintf "At offset %d: unexpected character\n"
                      (Lexing.lexeme_start lexbuf))) }
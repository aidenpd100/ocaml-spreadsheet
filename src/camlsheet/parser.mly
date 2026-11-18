%{
  open Ast
%}

(* tokens *)
%token <float> NUMBER
%token <Coord.t> REF
%token <string> FUNCTION_NAME
%token PLUS MINUS STAR SLASH
%token LPAREN RPAREN COMMA COLON
%token EOF

/* Precedents in ascedning order (going down) & directional associations */
%left PLUS MINUS
%left STAR SLASH
%nonassoc UMINUS

%start <Ast.expr> main

%%

main:
  | e = expr; EOF { e }

expr:
  | n = NUMBER                    { Num n }
  | c = REF                       { Ref c }
  | LPAREN; e = expr; RPAREN      { e }
  | MINUS; e = expr %prec UMINUS  { Neg e }
  | l = expr; PLUS;  r = expr     { Binop (Add, l, r) }
  | l = expr; MINUS; r = expr     { Binop (Sub, l, r) }
  | l = expr; STAR;  r = expr     { Binop (Mul, l, r) }
  | l = expr; SLASH; r = expr     { Binop (Div, l, r) }
  | f = FUNCTION_NAME; LPAREN; args = separated_list(COMMA, arg); RPAREN
                                  { Call (String.uppercase_ascii f, args) }

/* Ranges are only allowed here, so "=A1:A3" alone is a syntax error. */
arg:
  | a = REF; COLON; b = REF       { Range (a, b) }
  | e = expr                      { Expr e }
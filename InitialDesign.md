# Camlsheet — Design Proposal

**Group members:** Aidan, Nikay Jones, Max Voeltner
**Project name:** Camlsheet

---

## 1. Overview

Camlsheet is a web-based spreadsheet. Users type numbers, text, or formulas
(`=B1*2`, `=SUM(A1:A10)`) into a grid in the browser, and the sheet keeps every
formula's value up to date as the cells it depends on change.

All of the spreadsheet logic lives in OCaml on a Dream server. The React
frontend only displays cells and sends edits; it does no parsing or calculation.

The interesting parts of the project are:

1. **Sparse storage.** The sheet is a persistent map from coordinates to cells,
   not a 2D array. Only cells that contain something are stored, so the sheet is
   effectively unbounded and memory use depends on how many cells are filled,
   not on the grid size.
2. **A formula language.** An ocamllex lexer and a Menhir parser turn formula
   text into an AST, which a pure evaluator computes.
3. **A dependency graph.** When a cell changes, we work out exactly which cells
   depend on it (directly or indirectly), recalculate only those, in an order
   that guarantees every cell's inputs are computed first, and detect circular
   references instead of looping forever.
4. **A general library.** The dependency graph is written as a functor,
   `Depgraph.Make (Key)`, that knows nothing about spreadsheets. The spreadsheet
   uses it with `Coord` as the key, but it could equally drive a build system or
   task scheduler.
5. **Cheap undo.** Because sheets are persistent values, undo/redo is a history
   of old sheets that share all their unchanged cells.
---

## 2. Mock use

### 2.1 The page

There is a single page. It has a formula bar on top and a grid underneath.
The grid shows columns and rows. See attached for mock.

**Controls**
| Click a cell / arrow keys | Select it. The formula bar shows its **raw input** (e.g. `=B1*2`), the grid shows its **value** (e.g. `10`). |
| Start typing / double-click / Enter | Start editing the selected cell. |
| Enter (while editing) | Commit the edit, then move selection down one row. |
| Tab (while editing) | Commit the edit, then move selection right one column. |
| Esc (while editing) | Cancel the edit; the cell is unchanged. |
| Delete / Backspace (not editing) | Clear the cell. |

Every commit sends one request to the server. The server replies with **every
cell whose value changed**, and the UI updates exactly those cells.

| Undo / Redo buttons, Ctrl+Z / Ctrl+Y | Undo or redo the last edit (greyed out when there is nothing to undo/redo). |
| Save / Load buttons | Download the sheet as a JSON file / upload one to replace the sheet. |

### 2.2 Entering numbers and text

The user selects B1, types `5`, presses Enter, then types `Price` into A1.

```
│  A1  │ Price                                             │
├──────┴──┬─────────┬─────────┬─────────┬
│         │    A    │    B    │    C    │
├─────────┼─────────┼─────────┼─────────┼
│    1    │[Price  ]│       5 │         │   numbers right-aligned, text left-aligned
│    2    │         │         │         │
```

How a cell's text is interpreted (done in OCaml by `Formula.parse_cell`, after
removing surrounding whitespace):
- Empty → the cell is removed from the sheet.
- Starts with `=` → formula.
- A valid number (`5`, `-3.2`, `1.`, `.5`) → number.
- Anything else → text (e.g. `Price`, `----10`).

### 2.3 Entering a formula

The user selects C1 and types `=B1*2`.

```
│  C1  │ =B1*2                                             │  ← formula bar shows the formula
├──────┴──┬─────────┬─────────┬─────────┬
│         │    A    │    B    │    C    │
├─────────┼─────────┼─────────┼─────────┼
│    1    │ Price   │       5 │[     10]│  ← grid shows the value
```

The HTTP exchange behind this:

```
PUT /api/cells/C1        {"raw": "=B1*2"}

200 OK
{"changed": [
  {"coord": "C1", "raw": "=B1*2", "display": "10", "kind": "number"}
]}
```

### 2.4 Changes propagate through chains

D1 contains `=C1+1` (shows `11`). The user changes B1 from `5` to `7`.
C1 depends on B1, and D1 depends on C1, so both update.

```
├─────────┼─────────┼─────────┼─────────┼─────────┼
│    1    │ Price   │[      7]│      14 │      15 │
```

```
PUT /api/cells/B1        {"raw": "7"}

200 OK
{"changed": [
  {"coord": "B1", "raw": "7",     "display": "7",  "kind": "number"},
  {"coord": "C1", "raw": "=B1*2", "display": "14", "kind": "number"},
  {"coord": "D1", "raw": "=C1+1", "display": "15", "kind": "number"}
]}
```

Only B1, C1 and D1 are recalculated. Cells that don't depend on B1 are not touched.

### 2.5 Ranges and functions

```
│  B5  │ =SUM(B1:B4)                                       │
├──────┴──┬─────────┬─────────┬
│         │    A    │    B    │
├─────────┼─────────┼─────────┼
│    1    │ Price   │       7 │
│    2    │         │       3 │
│    3    │         │  (empty)│
│    4    │         │ hello   │
│    5    │ Total   │[     10]│   empty and text cells inside a range are skipped
```

Supported functions: `SUM`, `AVG`, `MIN`, `MAX`, `COUNT`. Each takes any number
of arguments, mixing ranges, cells and numbers: `=SUM(A1:A3, C1:C3, 10)`.
Ranges are rectangles given by two opposite corners (`A1:C3`, or `C3:A1`).
Function names and cell references are case-insensitive (`=sum(b1:b4)` works).

### 2.6 Errors

Errors are values, not crashes. A cell with an error shows the error code in red.

| Input | Shows | Why |
|---|---|---|
| `=1/0` | `#DIV/0` | Division by zero |
| `=B1+` | `#PARSE` | The formula doesn't parse |
| `=A1:A3` | `#PARSE` | A range is only allowed inside a function call |
| `=A0` | `#PARSE` | Not a valid cell reference (rows start at 1) |
| `=FOO(1)` | `#NAME` | Unknown function |
| `=A1+1` where A1 is `Price` | `#VALUE` | Arithmetic on text |
| `=AVG(E1:E5)` where E1:E5 are empty | `#DIV/0` | Average of nothing |
| `=C9*2` where C9 is `#DIV/0` | `#DIV/0` | Errors propagate to dependents |

```
├─────────┼─────────┼─────────┼
│    7    │  #DIV/0 │  #PARSE │   (shown in red)
```

### 2.7 Circular references

The user enters `=E2` in E1, then `=E1` in E2. Neither can be computed.

```
├─────────┼─────────┼
│         │    E    │
├─────────┼─────────┼
│    1    │  #CYCLE │
│    2    │[#CYCLE ]│
│    3    │  #CYCLE │   E3 = E1+1 also shows #CYCLE, because it depends on the cycle
```

The server never loops. Any cell that is part of a cycle, or depends on one,
shows `#CYCLE`. When the user breaks the cycle by changing E2 to `3`, E1 shows
`3` and E3 shows `4`.

### 2.8 Clearing a cell

The user selects B2 and presses Delete. B2 is removed from the sheet. Cells that
referred to it treat it as empty: `0` in arithmetic, skipped in ranges. B5
(`=SUM(B1:B4)`) updates to `7`.

### 2.9 Undo and redo

After clearing B2, the user clicks **Undo**. B2 shows `3` again and B5 goes
back to `10`. **Redo** clears B2 again.

```
POST /api/undo

200 OK
{"changed": [
  {"coord": "B2", "raw": "3",           "display": "3",  "kind": "number"},
  {"coord": "B5", "raw": "=SUM(B1:B4)", "display": "10", "kind": "number"}
]}
```

The UI asks `GET /api/history` after each edit to know whether the Undo and Redo
buttons should be enabled. Undoing with nothing to undo returns an error and the
sheet is unchanged.

### 2.10 Saving and loading

**Save** downloads the sheet as a JSON file containing every cell's raw input.
**Load** uploads such a file and replaces the current sheet; every value is
recalculated from the raw inputs. An invalid file is rejected with an error
message and the current sheet is kept.

### 2.11 Loading the page

When the page loads, the frontend asks for all cells in the visible window:

```
GET /api/cells?from=A1&to=Z100

200 OK
{"cells": [ {"coord": "A1", "raw": "Price", "display": "Price", "kind": "text"}, … ]}
```

---

## 3. Architecture

```
┌──────────────┐   JSON over HTTP   ┌─────────────────────────────────────────┐
│ React (Vite) │ ─────────────────► │ server/  (Dream)                        │
│  grid,       │ ◄───────────────── │   holds one `Sheet.t History.t ref`     │
│  formula bar,│                    │   routes requests, encodes responses    │
│  toolbar     │                    └──────────────────┬──────────────────────┘
└──────────────┘                                       │ calls (pure)
                                    ┌──────────────────▼──────────────────────┐
                                    │ src/json, src/persistence               │
                                    │   wire format, save/load files          │
                                    └──────────────────┬──────────────────────┘
                                    ┌──────────────────▼──────────────────────┐
                                    │ src/camlsheet  (spreadsheet library)    │
                                    │   Lexer · Parser · Ast · Formula ·      │
                                    │   Evaluator · Sheet · History           │
                                    └─────────┬──────────────────┬────────────┘
                                              │                  │ instantiates
                                    ┌─────────▼──────┐  ┌────────▼────────────┐
                                    │ src/coord      │  │ src/depgraph        │
                                    │  coordinates,  │  │  Depgraph.Make(Key) │
                                    │  A1 notation   │  │  general library    │
                                    └────────────────┘  └─────────────────────┘
```

**Rule:** everything under `src/` is pure — no IO, no mutation. The only
mutable state in the project is the single history reference in the server.

### Repository layout

```
Design.md
dune-project            (with opam package stanza; generates camlsheet.opam)
src/
  dune                  libraries `coord`, `json`, `persistence`
  coord.mli/.ml
  json.mli
  persistence.mli
  depgraph/             dune library `depgraph` — the general library
    depgraph.mli
  camlsheet/            dune library `camlsheet` — depends on coord, depgraph
    lexer.mll           ocamllex lexer
    parser.mly          Menhir grammar
    ast.mli/.ml         the AST, refs, to_string
    formula.mli/.ml     parse, parse_cell
    evaluator.mli/.ml   values and evaluation
    sheet.mli
    history.mli
server/                 dune executable — depends on camlsheet, json, persistence, dream
  main.ml  routes.mli  state.mli
test/                   OUnit2 + QCheck tests, one file per module
demo/                   one working demo per non-standard library
  menhir/  dream/  yojson/  qcheck/
frontend/               React + Vite (not counted as project code)
```

(The library is named `camlsheet`, not `sheet`: a dune library with the same
name as one of its modules would hide all its other modules.)
---

## 4. Modules

Full commented signatures are in the `.mli` files in `src/`. This section
describes what each module does and the key types.

### 4.1 `Coord` — cell coordinates

```ocaml
type t [@@deriving sexp]                (* abstract; 0-indexed: A1 is row 0, col 0 *)
include Comparable.S with type t := t   (* compare, equal, Coord.Map, Coord.Set *)

val create_coord : int -> int -> t option   (* None if either index is negative *)
val get_row : t -> int
val get_col : t -> int
val of_a1 : string -> t option      (* "B12" -> row 11, col 1; "A0", "1B", "A" -> None *)
val to_a1 : t -> string             (* row 11, col 1 -> "B12" *)
val range : t -> t -> t list        (* all coords in the rectangle, either corner order *)
```

Column letters use bijective base 26: A–Z, then AA, AB, … AZ, BA, … .
`of_a1` is case-insensitive and rejects anything that isn't letters followed by
a row number ≥ 1. `Coord` is its own library because `camlsheet`, `json` and
`persistence` all use it, and they must share one `Coord.t`.

### 4.2 Formulas — `Lexer`, `Parser`, `Ast`, `Formula`

A cell's text goes through four modules:

| Module | Written as | Job |
|---|---|---|
| `Lexer` | `lexer.mll` (ocamllex) | text → tokens |
| `Parser` | `parser.mly` (Menhir) | tokens → AST |
| `Ast` | OCaml | the AST types, `refs`, `to_string` |
| `Formula` | OCaml | runs lexer + parser, turns their exceptions into `result` |

**`Ast`**

```ocaml
type binop = Add | Sub | Mul | Div [@@deriving equal, sexp]

type expr =
  | Num of float                  (* 1, 1., 1.1, .5 *)
  | Str of string                 (* text cell, e.g. Price; only parse_cell creates these *)
  | Ref of Coord.t                (* B1 *)
  | Neg of expr                   (* unary minus: -A1 *)
  | Binop of binop * expr * expr
  | Call of string * arg list     (* SUM(A1:A3, 5); name stored uppercase *)
and arg =
  | Expr of expr
  | Range of Coord.t * Coord.t    (* A1:B3; only valid as a function argument *)
[@@deriving equal, sexp]

val refs : expr -> Coord.t list   (* every cell e reads, ranges expanded, no duplicates *)
val to_string : expr -> string    (* AST back to formula text, minimal parentheses *)
```

Every non-empty cell is an `expr`: plain numbers are `Num` and plain text is
`Str`, so the sheet and evaluator handle all cells the same way. `expr` and
`arg` are mutually recursive, matching the grammar: a call contains arguments,
and an argument contains an expression. Making ranges a separate `arg` type
means a range outside a function call can't even be represented.

`refs` is what connects formulas to the dependency graph: `Sheet` calls it to
find which cells a formula reads. `to_string` is used for a round-trip property
test of the parser.

**`Lexer`** (ocamllex). Tokens:

| Token | Matches | Example |
|---|---|---|
| `NUMBER of float` | `digit+ ('.' digit*)? \| '.' digit+` | `1`, `1.`, `1.1`, `.5` |
| `REF of Coord.t` | letters followed by digits, checked by `Coord.of_a1` | `B12`, `aa3` |
| `FUN_NAME of string` | letters only | `SUM` |
| `PLUS MINUS STAR SLASH LPAREN RPAREN COMMA COLON` | `+ - * / ( ) , :` | |
| `EOF` | end of the formula | |

Spaces and tabs are skipped. ocamllex always takes the longest match, so `B12`
is a reference and `SUM` is a function name. Numbers have no sign; `-5` is
`MINUS` followed by `NUMBER 5.`. An unexpected character or an invalid
reference such as `A0` raises `Lexer.Error "At offset N: ..."`.

**`Parser`** (Menhir). The grammar:

```
main   ::= expr EOF
expr   ::= NUMBER
         | REF
         | "(" expr ")"
         | "-" expr                       (%prec UMINUS)
         | expr ("+" | "-" | "*" | "/") expr
         | FUN_NAME "(" [ arg ("," arg)* ] ")"
arg    ::= REF ":" REF
         | expr

%left PLUS MINUS        (lowest)
%left STAR SLASH
%nonassoc UMINUS        (highest)
```

The precedence declarations resolve the grammar's ambiguity: `*` and `/` bind
tighter than `+` and `-`, all four are left-associative (`8-2-1` is
`(8-2)-1`), and unary minus binds tightest (`-A1*2` is `(-A1)*2`). The rule
actions build `Ast` nodes, so the tree is built bottom-up as rules match.

**`Formula`**

```ocaml
val parse : string -> (Ast.expr, string) result        (* formula without the '=' *)
val parse_cell : string -> (Ast.expr, string) result   (* anything typed into a cell *)
```

`parse` runs `Parser.main Lexer.token` on the text. Menhir and ocamllex report
errors by raising exceptions; `parse` catches them and returns
`Error "At offset N: ..."` instead, so nothing outside this module ever sees an
exception. `parse_cell` handles a cell's full text as in §2.2: `=...` goes to
`parse`, valid numbers become `Num`, anything else becomes `Str`.

### 4.3 `Evaluator` — values and evaluation

```ocaml
type error =
  | Div_zero   (* #DIV/0: 0 in the denominator, or AVG of no numbers *)
  | Parse      (* #PARSE: cell text can't be parsed; set by Sheet *)
  | Name       (* #NAME: unknown function name *)
  | Value      (* #VALUE: wrong kind of value, e.g. arithmetic on text *)
  | Cycle      (* #CYCLE: part of or depends on a cycle; set by Sheet *)

type value =
  | VNum of float
  | VText of string
  | VEmpty
  | VError of error

val eval : (Coord.t -> value) -> Ast.expr -> value
val value_to_grid_display : value -> string   (* "10", "2.5", "Price", "", "#DIV/0" *)
```

`eval lookup e` is pure. It doesn't know about the sheet: it reads other cells
only by calling the `lookup` function it is given, which returns a cell's
**already computed** value. `Sheet` passes a function that reads its cell map;
tests can pass a tiny made-up one. This makes the evaluator testable on its own
and independent of `Sheet`.

**Rules**
- `VEmpty` counts as `0` in arithmetic.
- Arithmetic on `VText` gives `VError Value`.
- If any operand is an error, the result is that error (first one, left to right).
- Functions are stored in a registry, a `Map` from name to
  `value list -> value`. Each argument becomes a list of values (a range gives
  the values of all its cells, skipping empty and text cells), the lists are
  joined, and the function folds over the result. Adding a function is one new
  entry in the map.
- Unknown function name → `VError Name`.

`value_to_grid_display` formats values for the frontend (whole numbers without
a trailing `.`), so the frontend never formats anything itself.

### 4.4 `Depgraph` — the general library

```ocaml
module type S = sig
  type key
  type t

  val empty : t

  (* [set_deps g k ds]: k now depends on exactly the keys ds,
     replacing whatever k depended on before. *)
  val set_deps : t -> key -> key list -> t

  (* Remove k's own dependencies. Other keys that depend on k keep their edges. *)
  val remove : t -> key -> t

  val deps       : t -> key -> key list   (* what k depends on *)
  val dependents : t -> key -> key list   (* what depends on k (direct only) *)

  type plan = {
    order    : key list;   (* k and everything that transitively depends on it,
                              sorted so each key comes after all of its deps *)
    in_cycle : key list;   (* keys in, or depending on, a cycle; can't be ordered *)
  }

  (* What to recompute, and in what order, after k changes. *)
  val recalc_plan : t -> key -> plan
end

module Make (Key : sig type t [@@deriving compare, sexp] end) : S with type key = Key.t
```

See `src/depgraph/depgraph.mli` for the full signature, including
`recalc_plan_many` for changing several keys at once.

**Representation.** Two maps, kept in sync:
- `forward : KeySet.t KeyMap.t` — key → the keys it depends on
- `reverse : KeySet.t KeyMap.t` — key → the keys that depend on it

Invariant: `b ∈ forward[a]` if and only if `a ∈ reverse[b]`. `set_deps` removes
`k` from the reverse sets of its old dependencies and adds it to the reverse
sets of its new ones. We keep the reverse map so `dependents` is a lookup
instead of a scan over the whole graph.

**`recalc_plan` algorithm** (in two steps):

1. **Find affected keys.** Depth-first search from `k` along `reverse` edges,
   collecting every reachable key into a set `R`. These are the only keys that
   can change.
2. **Order them (Kahn's algorithm).** For each key in `R`, count how many of its
   dependencies are also in `R` (its in-degree within `R`). Start a queue with
   the in-degree-0 keys. Repeatedly take a key from the queue, append it to
   `order`, and decrement the count of each of its dependents in `R`; when a
   count reaches 0, add that key to the queue.

   Any keys left over with a non-zero count are in a cycle or downstream of one,
   because they were waiting on something that never finished. They go in
   `in_cycle`.

This touches only the affected part of the graph, not the whole sheet.

### 4.5 `Sheet` — ties everything together

```ocaml
type cell = {
  raw    : string;                        (* exactly what the user typed *)
  parsed : (Ast.expr, string) Result.t;   (* Error means the cell shows #PARSE *)
  value  : Evaluator.value;               (* current computed value *)
}

module Graph : Depgraph.S with type key = Coord.t

type t   (* a cell Coord.Map.t plus a Graph.t *)

val empty    : t
val get      : t -> Coord.t -> cell option
val value    : t -> Coord.t -> Evaluator.value      (* VEmpty if empty; the lookup for eval *)
val in_range : t -> Coord.t -> Coord.t -> (Coord.t * cell) list   (* for page load *)
val to_list  : t -> (Coord.t * cell) list
val graph    : t -> Graph.t

val set      : t -> Coord.t -> string -> t * Coord.t list
val set_many : t -> (Coord.t * string) list -> t * Coord.t list   (* load *)
val of_raw   : (Coord.t * string) list -> t
val to_raw   : t -> (Coord.t * string) list
val diff     : t -> t -> Coord.t list    (* cells that differ; used after undo/redo *)
```

**What `set sheet c raw` does:**

1. `Formula.parse_cell raw` → the AST, or an error. Empty input removes `c`
   from the cell map (it stays in the graph so its dependents see `VEmpty`).
2. `Ast.refs` → the list of cells `c` reads (none for numbers, text, or a
   parse error).
3. `Graph.set_deps graph c refs`.
4. `Graph.recalc_plan graph c` → `{order; in_cycle}`.
5. Fold over `order`: evaluate each cell with `Evaluator.eval`, using a
   `lookup` that reads from the cells map **as updated so far**. Because `order`
   is topological, every dependency has already been recomputed when we reach it.
   A cell whose parse failed gets `VError Parse`.
6. Set every cell in `in_cycle` to `VError Cycle`.
7. Return the new sheet and the coords in `order @ in_cycle`.

The old sheet is unchanged (persistent maps), which is what makes undo cheap.

### 4.6 `History` — undo and redo

A history of `Sheet.t` values: the current sheet, the sheets before it (for
undo) and after it (for redo). Making an edit pushes the old sheet onto the undo
stack and clears the redo stack. Old sheets share every unchanged cell with the
current one, so keeping them costs little memory. After an undo or redo,
`Sheet.diff` tells the server which cells to send back.
See `src/camlsheet/history.mli`.

### 4.7 `Json` and `Persistence`

`Json` converts cells to and from the JSON shown in §2, using `ppx_yojson_conv`.
The server never builds JSON by hand. `display` and `kind` are computed in OCaml
so the frontend never formats numbers or decides what is an error.

`Persistence` saves a sheet as JSON (every cell's raw input, via `Sheet.to_raw`)
and loads it back (via `Sheet.of_raw`), rejecting invalid files.

See `src/json.mli` and `src/persistence.mli`.

### 4.8 Server endpoints

| Method | Path | Body | Response |
|---|---|---|---|
| GET | `/api/cells?from=A1&to=Z100` | — | `{"cells": [...]}` all non-empty cells in the rectangle |
| GET | `/api/cells/:coord` | — | One cell, or 404 if empty |
| PUT | `/api/cells/:coord` | `{"raw": "..."}` | `{"changed": [...]}`; `"raw": ""` clears the cell |
| POST | `/api/undo` | — | `{"changed": [...]}`, or an error if there is nothing to undo |
| POST | `/api/redo` | — | `{"changed": [...]}`, or an error if there is nothing to redo |
| GET | `/api/history` | — | Whether undo and redo are currently possible |
| GET | `/api/save` | — | The sheet as a downloadable JSON file |
| POST | `/api/load` | a saved JSON file | Replaces the sheet; an error if the file is invalid |

Bad coordinates or bad JSON → 400 with `{"error": "..."}`.
---

## 5. Libraries

| Library | Use | Demo |
|---|---|---|
| `core`, `ppx_jane` | Course standard library; `[@@deriving equal, compare, sexp]` | (course standard) |
| `ounit2` | Unit tests | (course standard) |
| `menhir` | Parser generator for the formula grammar (with ocamllex, part of OCaml) | `demo/menhir/` — Menhir's own `calc` demo; `dune test` checks its output |
| `dream`, `lwt` | Web server | `demo/dream/` — a route returning JSON |
| `yojson`, `ppx_yojson_conv` | JSON encoding/decoding | `demo/yojson/` — round-trip a record |
| `qcheck-core`, `qcheck-ounit` | Property-based tests | `demo/qcheck/` — one property run under OUnit |

**Coverage:** we planned to use `bisect_ppx`, but no released version installs
on OCaml 5.5 (its dependencies require OCaml < 5.4). We are asking the course
staff which coverage tool to use instead.

**Frontend (not counted as project code):** React + Vite, using `fetch` to call
the API. It contains no spreadsheet logic.

Each demo has been built and run on all three team members' machines.

---

## 6. Testing plan

- **OUnit2 unit tests** for every module in `src/`:
  - `Coord`: A1 conversion edge cases (`Z1`, `AA1`, `AZ1`, `BA1`, `ZZ99`,
    lowercase, `A0`, `1B`, `A`, `""`, `A+5`).
  - `Lexer`/`Formula`: precedence (`1+2*3`), associativity (`8-2-1`), unary
    minus, ranges, nested calls, number formats (`1`, `1.`, `.5`), plain text
    vs numbers in `parse_cell` (`Price`, `----10`), and every kind of malformed
    input with its error offset.
  - `Ast`: `refs` with ranges (either corner order) and repeated references.
  - `Evaluator`: each operator and function, empty and text handling, every
    error code, error propagation. Uses a small hand-written `lookup`.
  - `Depgraph`: `set_deps` replacing edges, `dependents`, chains, diamonds
    (A→B, A→C, B→D, C→D), self-loops, longer cycles, keys downstream of cycles.
  - `Sheet` and `History`: the scenarios from §2, run as tests.
- **QCheck properties:**
  - `Coord.of_a1 (Coord.to_a1 c) = Some c`
  - `Formula.parse (Ast.to_string e) = Ok e` for generated ASTs
  - After any sequence of `set_deps`, the forward and reverse maps agree.
  - In `recalc_plan`, every key appears after all of its dependencies that are in the plan.
  - Undo after any edit gives back a sheet equal to the one before it.

---

## 7. Implementation plan

**Roles**

| Person | Owns |
|---|---|
| Max — Formulas and frontend | `Lexer`, `Parser`, `Ast`, `Formula`, `Evaluator`; React frontend |
| Aidan — Graph | `Depgraph` library and all its tests |
| Nikay — Sheet and server | `Coord`, `Sheet`, `History`, `Json`, `Persistence`, Dream server, repo and test setup |

Everyone writes tests for their own modules.

**Schedule**

| Dates | Formulas and frontend | Graph | Sheet and server |
|---|---|---|---|
| **Nov 7–18** | Lexer, Menhir grammar, `Formula` working; `ast.mli`, `evaluator.mli`; Menhir demo | `depgraph.mli` | Repo, `dune-project`, Dream demo, `coord.mli`, `sheet.mli`, `history.mli`, `json.mli`, `persistence.mli` |
| **Nov 18** | **Design proposal submitted** | | |
| Nov 19–25 | Parser tests; `Ast.refs`; `Evaluator` for numbers, refs, arithmetic and errors | `set_deps`, `remove`, `deps`, `dependents`; invariant tests | `Coord` (rest of it) + tests; Dream server returning a hard-coded sheet as JSON |
| Nov 26–Dec 2 | Function registry and ranges in `Evaluator`; React grid displaying cells, editing with PUT requests | `recalc_plan` (DFS + Kahn); cycle tests | `Json`; `Sheet.set` (initially recalculating everything) |
| Dec 3–7 | `Ast.to_string` + round-trip property test; error styling in the UI | Property tests; help with integration | `Sheet.set` using `recalc_plan`; end-to-end testing; coverage report; `Readme.md` |
| **~Dec 7** | **Code checkpoint** (date to confirm): every §2.1–2.8 and §2.11 scenario works end to end | | |
| Dec 8–17 | Undo/redo and save/load buttons in the UI; `IF` (§8) | Help with testing | `History`, `Persistence`, undo/redo and save/load endpoints |
| **Dec 18–20** | **Demo** | | |
---

## 8. Planned extensions

**Planned: adding arrow visuals to show cycles in real time

## 9. Known limitations

- Numbers are floats only, with no exponent notation (`1e3` is text).
- Formulas can't contain text literals (no `="hello"`).
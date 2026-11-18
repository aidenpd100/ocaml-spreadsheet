# Camlsheet — Design Proposal

**Group members:** _Name 1_, _Name 2_, _Name 3_
**Project name:** Camlsheet (working title)

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
2. **A formula language.** A lexer and recursive-descent parser turn formula
   strings into an AST, which a pure evaluator computes.
3. **A dependency graph.** When a cell changes, we work out exactly which cells
   depend on it (directly or indirectly), recalculate only those, in an order
   that guarantees every cell's inputs are computed first, and detect circular
   references instead of looping forever.
4. **A general library.** The dependency graph is written as a functor,
   `Depgraph.Make (Key)`, that knows nothing about spreadsheets. The spreadsheet
   uses it with `Coord` as the key, but it could equally drive a build system or
   task scheduler.

---

## 2. Mock use

### 2.1 The page

There is a single page. It has a formula bar on top and a grid underneath.
The grid shows columns A–Z and rows 1–100. (The backend has no size limit; the
UI just shows a fixed window to start.)

```
┌──────────────────────────────────────────────────────────┐
│ Camlsheet                                                │
├──────┬───────────────────────────────────────────────────┤
│  A1  │                                                   │  ← formula bar: selected cell + raw input
├──────┴──┬─────────┬─────────┬─────────┬─────────┬────────┤
│         │    A    │    B    │    C    │    D    │   …    │
├─────────┼─────────┼─────────┼─────────┼─────────┼────────┤
│    1    │[       ]│         │         │         │        │  ← [ ] = selected cell
│    2    │         │         │         │         │        │
│    3    │         │         │         │         │        │
│    …    │         │         │         │         │        │
└─────────┴─────────┴─────────┴─────────┴─────────┴────────┘
```

**Controls**

| Action | Effect |
|---|---|
| Click a cell / arrow keys | Select it. The formula bar shows its **raw input** (e.g. `=B1*2`), the grid shows its **value** (e.g. `10`). |
| Start typing / double-click / Enter | Start editing the selected cell. |
| Enter (while editing) | Commit the edit, then move selection down one row. |
| Tab (while editing) | Commit the edit, then move selection right one column. |
| Esc (while editing) | Cancel the edit; the cell is unchanged. |
| Delete / Backspace (not editing) | Clear the cell. |

Every commit sends one request to the server. The server replies with **every
cell whose value changed**, and the UI updates exactly those cells.

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

Input classification (done in OCaml):
- Empty or whitespace only → the cell is removed from the sheet.
- Starts with `=` → formula.
- Parses as a number (`5`, `-3.2`, `1e3`) → number.
- Anything else → text.

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

Supported functions: `SUM`, `AVG`, `MIN`, `MAX`, `COUNT`. Function names and
cell references are case-insensitive (`=sum(b1:b4)` works).

### 2.6 Errors

Errors are values, not crashes. A cell with an error shows the error code in red.

| Input | Shows | Why |
|---|---|---|
| `=1/0` | `#DIV/0` | Division by zero |
| `=B1+` | `#PARSE` | The formula doesn't parse |
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

### 2.9 Loading the page

When the page loads, the frontend asks for all cells in the visible window:

```
GET /api/cells?from=A1&to=Z100

200 OK
{"cells": [ {"coord": "A1", "raw": "Price", "display": "Price", "kind": "text"}, … ]}
```

The sheet lives in server memory for the session. (Saving to a file is a
possible extension; see §8.)

---

## 3. Architecture

```
┌──────────────┐   JSON over HTTP   ┌─────────────────────────────────────────┐
│ React (Vite) │ ─────────────────► │ server/  (Dream)                        │
│  grid,       │ ◄───────────────── │   holds one `Sheet.t ref`               │
│  formula bar │                    │   decodes requests, encodes responses   │
└──────────────┘                    └──────────────────┬──────────────────────┘
                                                       │ calls (pure)
                                    ┌──────────────────▼──────────────────────┐
                                    │ src/sheet  (spreadsheet library)        │
                                    │   Coord · Formula · Eval · Sheet · Json │
                                    └──────────────────┬──────────────────────┘
                                                       │ instantiates
                                    ┌──────────────────▼──────────────────────┐
                                    │ src/depgraph  (general library)         │
                                    │   Depgraph.Make (Key) — no spreadsheet  │
                                    │   knowledge at all                      │
                                    └─────────────────────────────────────────┘
```

**Rule:** everything under `src/` is pure — no IO, no mutation. The only
mutable state in the project is the single `Sheet.t ref` in the server.

### Repository layout

```
Design.md
dune-project            (with opam package stanza; generates camlsheet.opam)
src/
  depgraph/             dune library `depgraph`  — the general library
    depgraph.mli
  sheet/                dune library `sheet`     — depends on depgraph
    coord.mli
    formula.mli
    eval.mli
    sheet.mli
    json.mli
server/                 dune executable          — depends on sheet, dream
  main.ml
test/                   OUnit2 + QCheck tests, one file per module
demo/                   one working demo per non-standard library
  dream/  yojson/  qcheck/  bisect_ppx/
frontend/               React + Vite (not counted as project code)
```

---

## 4. Modules

Full commented signatures are in the `.mli` files in `src/`. This section
describes what each module does and the key types.

### 4.1 `Coord` — cell coordinates

```ocaml
type t = { row : int; col : int }   (* 0-indexed: A1 = {row=0; col=0} *)
[@@deriving compare, sexp, yojson]

val of_a1 : string -> t option      (* "B12" -> Some {row=11; col=1}; "1B" -> None *)
val to_a1 : t -> string             (* {row=11; col=1} -> "B12" *)
val range : t -> t -> t list        (* all coords in the rectangle, either corner order *)
```

Column letters use bijective base 26: A–Z, then AA, AB, … AZ, BA, … .
`of_a1` is case-insensitive. `Coord` also provides `Map` and `Set` modules.

### 4.2 `Formula` — lexer, parser, AST

```ocaml
type binop = Add | Sub | Mul | Div

type expr =
  | Num of float
  | Ref of Coord.t
  | Neg of expr
  | Binop of binop * expr * expr
  | Call of string * arg list         (* function name stored uppercase *)
and arg =
  | Expr of expr
  | Range of Coord.t * Coord.t        (* ranges only appear as function arguments *)

type content =
  | Number of float
  | Text of string
  | Formula of expr
  | Bad_formula of string             (* raw text that failed to parse → #PARSE *)

val classify : string -> content option   (* None for empty input *)
val parse    : string -> (expr, string) result   (* input without the leading '=' *)
val refs     : expr -> Coord.t list   (* every cell this formula reads, ranges expanded *)
val to_string : expr -> string        (* AST back to formula text *)
```

**Grammar** (hand-written recursive descent over a token list):

```
expr   ::= term   (("+" | "-") term)*
term   ::= factor (("*" | "/") factor)*
factor ::= NUMBER
         | REF
         | "-" factor
         | "(" expr ")"
         | NAME "(" [ arg ("," arg)* ] ")"
arg    ::= REF ":" REF
         | expr
```

`*` and `/` bind tighter than `+` and `-`; all four are left-associative. We
chose a hand-written parser over Menhir so the parser is plain OCaml we can
test and explain line by line.

### 4.3 `Eval` — values and evaluation

```ocaml
type error = Div_zero | Parse | Name | Value | Cycle
type value =
  | VNum of float
  | VText of string
  | VEmpty
  | VError of error

val eval : lookup:(Coord.t -> value) -> Formula.expr -> value
val eval_content : lookup:(Coord.t -> value) -> Formula.content -> value
val display : value -> string        (* "10", "3.5", "Price", "#DIV/0", "" *)
```

`eval` is pure. It doesn't know about the sheet; it reads other cells only
through the `lookup` function it is given. This makes it easy to test on its own.

**Rules**
- `VEmpty` counts as `0` in arithmetic.
- Arithmetic on `VText` gives `VError Value`.
- If any operand is an error, the result is that error (first one, left to right).
- Functions are stored in a registry, a `Map` from name to
  `value list -> value`. A range argument is expanded into its cells' values;
  inside a range, empty and text cells are skipped. Adding a new function is
  one new entry in the map.
- Unknown function name → `VError Name`.

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
  raw     : string;            (* exactly what the user typed *)
  content : Formula.content;
  value   : Eval.value;
}

module Graph = Depgraph.Make (Coord)

type t = { cells : cell Coord.Map.t; graph : Graph.t }

val empty    : t
val get      : t -> Coord.t -> cell option
val in_range : t -> Coord.t -> Coord.t -> (Coord.t * cell) list   (* for page load *)

(* Set a cell's raw input. Returns the new sheet and the coords whose value changed. *)
val set : t -> Coord.t -> string -> t * Coord.t list
```

**What `set sheet c raw` does:**

1. `Formula.classify raw` → content. If `None` (empty input), remove `c` from `cells`.
2. `Formula.refs` → the list of cells `c` reads (empty for numbers and text).
3. `Graph.set_deps graph c refs`.
4. `Graph.recalc_plan graph c` → `{order; in_cycle}`.
5. Fold over `order`: evaluate each cell with `Eval.eval_content`, using a
   `lookup` that reads from the cells map **as updated so far**. Because `order`
   is topological, every dependency has already been recomputed when we reach it.
6. Set every cell in `in_cycle` to `VError Cycle`.
7. Return the new sheet and the coords in `order @ in_cycle`.

The old sheet is unchanged (persistent maps), which is what makes undo an easy
future extension.

### 4.6 `Json` — wire format

Converts cells to and from the JSON shown in §2, using `ppx_yojson_conv`. The
server never builds JSON by hand. `display` and `kind` are computed in OCaml so
the frontend never formats numbers or decides what is an error.

```ocaml
val cell_to_json   : Coord.t -> Sheet.cell -> Yojson.Safe.t
val changed_to_json : Sheet.t -> Coord.t list -> Yojson.Safe.t
val raw_of_json    : Yojson.Safe.t -> (string, string) result   (* {"raw": "..."} *)
```

### 4.7 Server endpoints

| Method | Path | Body | Response |
|---|---|---|---|
| GET | `/api/cells?from=A1&to=Z100` | — | `{"cells": [...]}` all non-empty cells in the rectangle |
| GET | `/api/cells/:coord` | — | One cell, or 404 if empty |
| PUT | `/api/cells/:coord` | `{"raw": "..."}` | `{"changed": [...]}`; `"raw": ""` clears the cell |

Bad coordinates or bad JSON → 400 with `{"error": "..."}`.

---

## 5. Libraries

| Library | Use | Demo |
|---|---|---|
| `core` | Course standard library: `Map`, `Set`, `List`, deriving | (course standard) |
| `ounit2` | Unit tests | (course standard) |
| `dream`, `lwt` | Web server | `demo/dream/` — a route returning JSON |
| `yojson`, `ppx_yojson_conv` | JSON encoding/decoding | `demo/yojson/` — round-trip a record |
| `qcheck-core`, `qcheck-ounit` | Property-based tests | `demo/qcheck/` — one property run under OUnit |
| `bisect_ppx` | Coverage reports | `demo/bisect_ppx/` — coverage report on a toy module |

**Frontend (not counted as project code):** React + Vite, using `fetch` to call
the API. It contains no spreadsheet logic.

Each demo has been built and run on all three team members' machines.

---

## 6. Testing plan

- **OUnit2 unit tests** for every module in `src/`:
  - `Coord`: A1 conversion edge cases (`Z1`, `AA1`, `ZZ99`, lowercase, invalid input).
  - `Formula`: precedence (`1+2*3`), associativity (`8-2-1`), unary minus,
    ranges, nested calls, every kind of malformed input.
  - `Eval`: each operator and function, empty and text handling, every error
    code, error propagation.
  - `Depgraph`: `set_deps` replacing edges, `dependents`, chains, diamonds
    (A→B, A→C, B→D, C→D), self-loops, longer cycles, keys downstream of cycles.
  - `Sheet`: the scenarios from §2, run as tests.
- **QCheck properties:**
  - `Coord.of_a1 (Coord.to_a1 c) = Some c`
  - `Formula.parse (Formula.to_string e) = Ok e`
  - After any sequence of `set_deps`, the forward and reverse maps agree.
  - In `recalc_plan`, every key appears after all of its dependencies that are in the plan.
  - Evaluating a sheet with no formulas gives back the literal values.
- **Coverage:** `bisect_ppx`, run with `dune test --instrument-with bisect_ppx`.

---

## 7. Implementation plan

**Roles**

| Person | Owns |
|---|---|
| _Name 1_ — Formulas | `Formula` (lexer, parser, `refs`, `to_string`), `Eval` (values, functions) |
| _Name 2_ — Graph | `Depgraph` library and all its tests |
| _Name 3_ — Sheet and app | `Coord`, `Sheet`, `Json`, Dream server, React frontend, repo and test setup |

Everyone writes tests for their own modules.

**Schedule**

| Dates | Formulas | Graph | Sheet and app |
|---|---|---|---|
| **Nov 7–16** | `formula.mli`, `eval.mli` | `depgraph.mli` | Repo, `dune-project`, demos, `coord.mli`, `sheet.mli`, `json.mli`, mockups |
| **Nov 16** | **Design proposal submitted** | | |
| Nov 17–23 | Lexer; parser for numbers, refs, arithmetic | `set_deps`, `remove`, `deps`, `dependents`; invariant tests | `Coord` + tests; Dream server returning a hard-coded sheet as JSON; React grid that displays it |
| Nov 24–30 | Ranges and function calls in the parser; `Eval` with errors and the function registry | `recalc_plan` (DFS + Kahn); cycle tests | `Json`; `Sheet.set` (initially recalculating everything); React editing and PUT requests |
| Dec 1–6 | `to_string` + round-trip property test | Property tests; help with integration | `Sheet.set` using `recalc_plan`; end-to-end testing; coverage report; `Readme.md` |
| **~Dec 7** | **Code checkpoint** (date to confirm): every §2 scenario works end to end | | |
| Dec 8–17 | Fix advisor feedback, more edge-case tests, UI polish, an extension from §8 if time allows | | |
| **Dec 18–20** | **Demo** | | |

---

## 8. Possible extensions

Not part of the core plan. We'll pick from these with our advisor once the core works.

- **Undo/redo.** Keep a list of previous `Sheet.t` values. Persistent maps share
  structure, so each saved version is cheap.
- **Save/load.** Write the sheet's raw inputs to a JSON file and rebuild it on load.
- **More functions.** `IF`, comparisons, `ROUND`, string concatenation.
- **Copy/paste with relative references.** Pasting `=A1` one row down gives `=A2`.
- **Scrolling past row 100.** Fetch cells for whatever window is visible.

## 9. Known limitations

- Numbers are floats only.
- A large range like `=SUM(A1:A100000)` adds one graph edge per cell in the range.
  This is fine at the sizes we expect; storing ranges as single edges would be
  an optimization for later.
- One shared sheet per server; no multiple users or multiple sheets.
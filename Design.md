# Camlsheet — Design Proposal

**Group members:** Aiden Deffner, Max Voeltner, Nikay Jones
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
   not on the grid size. Every edit produces a new sheet that shares almost all 
   of its structure with the old one, which makes undo/redo cheap.
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
| Ctrl/Cmd+Z, Ctrl/Cmd+Shift+Z | Undo / redo (§2.10). |

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

### 2.10 Undo and redo
 
Continuing from §2.8, the user presses Ctrl+Z. B2 comes back as `3` and B5 goes
back to `10`. Pressing Ctrl+Shift+Z clears B2 again.
 
```
POST /api/undo
 
200 OK
{"changed": [
  {"coord": "B2", "raw": "3",           "display": "3",  "kind": "number"},
  {"coord": "B5", "raw": "=SUM(B1:B4)", "display": "10", "kind": "number"}
]}
```
 
Undo does not replay an inverse edit. The server keeps the previous sheets
themselves and switches back to one. Because sheets are persistent maps, each
stored version costs only the cells that changed. Making a new edit after
undoing clears the redo history, as in any editor. Undo with nothing to undo
returns `{"changed": []}`.

---

## 3. Architecture

```
┌──────────────┐   JSON over HTTP   ┌─────────────────────────────────────────┐
│ React (Vite) │ ─────────────────► │ server/  (Dream)                        │
│  grid,       │ ◄───────────────── │   holds one `Sheet.t History.t ref`     │
│  formula bar │                    │   decodes requests, encodes responses   │
└──────────────┘                    └──────────────────┬──────────────────────┘
                                                       │ calls (pure)
                                    ┌──────────────────▼────────────────────────────────┐
                                    │ src/camlsheet  (spreadsheet library)              │
                                    │   Coord · Formula · Eval · Sheet · History · Json │
                                    └──────────────────┬────────────────────────────────┘
                                                       │ instantiates
                                    ┌──────────────────▼──────────────────────┐
                                    │ src/depgraph  (general library)         │
                                    │   Depgraph.Make (Key) — no spreadsheet  │
                                    │   knowledge at all                      │
                                    └─────────────────────────────────────────┘
```

**Rule:** everything under `src/` is pure — no IO, no mutation. The only 
mutable state in the project is the single Sheet.t History.t ref in the 
server (the current sheet plus its undo history).

### Repository layout

```
Design.md
dune-project            (with opam package stanza; generates camlsheet.opam)
src/
  depgraph/             dune library `depgraph`   — the general library
    depgraph.mli
  camlsheet/            dune library `camlsheet`  — depends on depgraph
    coord.mli
    formula.mli
    eval.mli
    sheet.mli
    history.mli
    json.mli
server/                 dune executable           — depends on camlsheet, dream
  main.ml
test/                   OUnit2 + QCheck tests, one file per module
demo/                   one working demo per non-standard library
  dream/  yojson/  qcheck/  bisect_ppx/
frontend/               React + Vite (not counted as project code)
```

(The library is named camlsheet rather than sheet because dune does not allow a library to contain a module with the library’s own name.)

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
val content_refs : content -> Coord.t list   (* refs of a formula; [] for anything else *)
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
 
Full signature: `src/depgraph/depgraph.mli`.
 
`Depgraph.Make (Key)` builds a persistent dependency graph over any key type
that can be compared and printed. It knows nothing about spreadsheets: the
sheet uses it with `Coord` as the key, but the same module could drive a build
system (files as keys) or a task scheduler (tasks as keys). Every operation
returns a new graph and leaves the old one unchanged.
 
**Terminology.** If `a` reads `b`, then `a` *depends on* `b`, `b` is a
*dependency* of `a`, and `a` is a *dependent* of `b`.
 
**Operations**
- `set_deps g k ds` makes `k` depend on exactly `ds`, replacing its old
  dependencies. `remove g k` is `set_deps g k []`.
- `deps g k` and `dependents g k` look up direct edges in each direction.
- `recalc_plan g k` says what to recompute after `k` changes, and in what
  order. `recalc_plan_many g ks` does the same for several changed keys at once
  (used when loading a sheet).
```ocaml
type plan = {
  order    : key list;  (* affected keys, each after all of its dependencies *)
  in_cycle : key list;  (* keys in, or downstream of, a cycle *)
}
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

Every key in `R` ends up in exactly one of `order` or `in_cycle`.
`recalc_plan_many` is the same algorithm with the DFS started from several keys.
 
**Performance.** `set_deps` costs O(d log n) for a key with d dependencies in a
graph of n keys. `recalc_plan` costs O((|R| + E_R) log n), where E_R is the
number of edges inside `R`: it touches only the affected part of the graph, not
the whole sheet.

### 4.5 `Sheet` — ties everything together
 
Full signature: `src/camlsheet/sheet.mli`.
 
A sheet is a persistent value: a map from coordinates to the non-empty cells,
plus the dependency graph (`Depgraph.Make (Coord)`) recording which cells read
which. `type t` is abstract, so nothing outside `Sheet` can let the two get out
of sync.
 
```ocaml
type cell = {
  raw     : string;           (* exactly what the user typed *)
  content : Formula.content;  (* raw, classified and parsed *)
  value   : Eval.value;       (* current computed value *)
}
```
 
**Operations**
- Reading: `get`, `value` (the `lookup` function given to `Eval`), and
  `in_range` for page load.
- Editing: `set` for one cell, and `set_many` for several at once, which
  recalculates each affected cell only once.
- Saving and loading: `to_raw` lists every cell's raw input, and `of_raw`
  rebuilds a sheet from that list (values are recomputed, never stored).
- `diff` lists the cells that differ between two sheets. After undo/redo, it
  tells the frontend what to repaint.

**What `set sheet c raw` does:**
 
1. `Formula.classify raw` → content. If `None` (empty input), remove `c` from
   `cells`. `c` stays in the graph as a key, so the steps below still run and
   its dependents recalculate, now seeing it as empty.
2. `Formula.content_refs` → the list of cells `c` reads (empty for numbers,
   text, bad formulas, and a cleared cell).
3. `Graph.set_deps graph c refs`.
4. `Graph.recalc_plan graph c` → `{order; in_cycle}`.
5. Fold over `order`: evaluate each cell with `Eval.eval_content`, using a
   `lookup` that reads from the cells map **as updated so far**. Because `order`
   is topological, every dependency has already been recomputed when we reach it.
6. Set every cell in `in_cycle` to `VError Cycle`.
7. Return the new sheet and the coords in `order @ in_cycle`.

The old sheet is unchanged and shares all untouched cells with the new one,
which is what makes undo cheap (§4.6).
 
### 4.6 `History` — undo/redo
 
Full signature: `src/camlsheet/history.mli`.
 
`'a History.t` is a zipper: the current value, a stack of past values, and a
stack of undone values. `push` adds a new current value and clears the redo
stack; `undo` and `redo` move between the stacks and return `None` when there is
nothing to move. A limit (default 100) drops the oldest past values.
 
It is polymorphic and knows nothing about sheets. The server keeps a
`Sheet.t History.t` instead of a single `Sheet.t`. Since each past sheet shares
structure with the next one, 100 stored versions cost about 100 edits' worth of
memory, not 100 copies of the sheet.

### 4.7 `Json` — wire format

Converts cells to and from the JSON shown in §2, using `ppx_yojson_conv`. The
server never builds JSON by hand. `display` and `kind` are computed in OCaml so
the frontend never formats numbers or decides what is an error.

```ocaml
val cell_to_json   : Coord.t -> Sheet.cell -> Yojson.Safe.t
val changed_to_json : Sheet.t -> Coord.t list -> Yojson.Safe.t
val raw_of_json    : Yojson.Safe.t -> (string, string) result   (* {"raw": "..."} *)
```

### 4.8 Server endpoints

| Method | Path | Body | Response |
|---|---|---|---|
| GET | `/api/cells?from=A1&to=Z100` | — | `{"cells": [...]}` all non-empty cells in the rectangle |
| GET | `/api/cells/:coord` | — | One cell, or 404 if empty |
| PUT | `/api/cells/:coord` | `{"raw": "..."}` | `{"changed": [...]}`; `"raw": ""` clears the cell |
| POST | `/api/undo` | — | `{"changed": [...]}`; empty list if there is nothing to undo |
| POST | `/api/redo` | — | `{"changed": [...]}`; empty list if there is nothing to redo |

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
    (A→B, A→C, B→D, C→D), self-loops, longer cycles, keys downstream of cycles,
    `recalc_plan_many`.
  - `Sheet`: the scenarios from §2, run as tests; clearing a cell that others
    refer to; `set_many`; `of_raw`/`to_raw`; `diff`.
  - `History`: undo/redo order, redo cleared by a new push, the limit, undo and
    redo on an empty history.
- **QCheck properties:**
  - `Coord.of_a1 (Coord.to_a1 c) = Some c`
  - `Formula.parse (Formula.to_string e) = Ok e`
  - After any sequence of `set_deps`, the forward and reverse maps agree.
  - In `recalc_plan`, every key appears after all of its dependencies that are
    in the plan, and every affected key is in exactly one of `order`/`in_cycle`.
  - Incremental recalculation (`set`) gives the same values as rebuilding the
    whole sheet from scratch with `of_raw`.
  - `Sheet.of_raw (Sheet.to_raw s)` has the same values as `s`.
  - `undo (push h x)` gives back `h`'s current state.
  - Evaluating a sheet with no formulas gives back the literal values.
- **Coverage:** `bisect_ppx`, run with `dune test --instrument-with bisect_ppx`.

---

## 7. Implementation plan

**Roles**

| Person | Owns |
|---|---|
| Max — Formulas | `Formula` (lexer, parser, `refs`, `to_string`), `Eval` (values, functions) |
| Aiden — Engine | `Depgraph` library, `Sheet` (`set`, `set_many`, recalculation, `diff`), `History`, and their tests |
| Nikay — Server and app | `Coord`, `Json`, Dream server (including undo/redo endpoints), React frontend, repo and test setup |

Everyone writes tests for their own modules.

**Schedule**

| Dates | Formulas | Engine | Server and app |
|---|---|---|---|
| **Nov 7–18** | `formula.mli`, `eval.mli` | `depgraph.mli`, `sheet.mli`, `history.mli` | Repo, `dune-project`, demos, `coord.mli`, `json.mli`, mockups |
| **Nov 18** | **Design proposal submitted** | | |
| Nov 19–23 | Lexer; parser for numbers, refs, arithmetic | `Depgraph`: `set_deps`, `remove`, `deps`, `dependents`; forward/reverse invariant property test | `Coord` + tests; Dream server returning a hard-coded sheet as JSON; React grid that displays it |
| Nov 24–30 | Ranges and function calls in the parser; `Eval` with errors and the function registry | `recalc_plan` (DFS + Kahn) and `recalc_plan_many`; cycle tests; `History` | `Json`; GET and PUT endpoints; React editing and PUT requests |
| Dec 1–6 | `to_string` + round-trip property test | `Sheet.set` / `set_many` (against stubs, then the real `Formula`/`Eval`); `of_raw`/`to_raw`; incremental-vs-full property test | Wire `Sheet` into the server; undo/redo endpoints and buttons; coverage report; `Readme.md` |
| **~Dec 7** | **Code checkpoint** (date to confirm): every §2 scenario works end to end | | |
| Dec 8–17 | Advisor feedback; edge-case tests; an extension from §8 if time allows | `diff`; edge-case tests; integration help | Advisor feedback; UI polish; an extension from §8 if time allows |
| **Dec 18–20** | **Demo** | | |

---

## 8. Possible extensions

Not part of the core plan. We'll pick from these with our advisor once the core works.

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
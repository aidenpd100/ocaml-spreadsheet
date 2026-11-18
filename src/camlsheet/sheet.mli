(** A spreadsheet: sparse cell storage with incremental recalculation.

    A sheet is a persistent value. [set] returns a new sheet and never changes
    the old one, so keeping old sheets around (for undo) is cheap: the two
    versions share every unchanged cell.

    Internally a sheet is a [cell Coord.Map.t] (only non-empty cells are
    stored) together with a [Graph.t] recording which cells read which. *)

(** One stored cell *)
type cell = {
  raw : string;              (** exactly what the user typed *)
  content : Formula.content; (** [raw], classified and parsed *)
  value : Eval.value;        (** current computed value *)
}
[@@deriving compare, sexp]

(** The dependency graph used by sheets: [Depgraph] instantiated with
    coordinates as keys. *)
module Graph : Depgraph.S with type key = Coord.t

type t

val empty : t

(** The cell at a coordinate, or [None] if it is empty. *)
val get : t -> Coord.t -> cell option

(** The value at a coordinate ([VEmpty] if the cell is empty). This is the
    [lookup] function handed to [Eval]. *)
val value : t -> Coord.t -> Eval.value

(** All non-empty cells in the rectangle with the given corners, in row-major
    order. Used to load the visible part of the grid. *)
val in_range : t -> Coord.t -> Coord.t -> (Coord.t * cell) list

(** Every non-empty cell, in row-major order. *)
val to_list : t -> (Coord.t * cell) list

(** The dependency graph (read-only; for tests and debugging). *)
val graph : t -> Graph.t

(** [set sheet c raw] sets [c]'s input and recalculates.
    Returns the new sheet and every coordinate whose displayed cell may have
    changed (always including [c]).

    Steps:
    1. Classify [raw]. Empty input removes [c] from the cell map, but [c]
       stays in the graph as a key, so its dependents still recalculate and
       see [VEmpty].
    2. Record [c]'s new dependencies with [Graph.set_deps] (none for numbers/text, 
       bad formulas, or an empty cell).
    3. Get [Graph.recalc_plan] for [c].
    4. Evaluate cells in [plan.order], each one reading the values already
       updated earlier in this same pass.
    5. Set every cell in [plan.in_cycle] to [VError Cycle].
    6. Return the new sheet and [plan.order @ plan.in_cycle]. *)
val set : t -> Coord.t -> string -> t * Coord.t list

(** Set many cells at once and recalculate each affected cell only once (via
    [Graph.recalc_plan_many]). Used for load and paste. If a coordinate
    appears twice, the last input wins. *)
val set_many : t -> (Coord.t * string) list -> t * Coord.t list

(** Build a sheet from saved raw inputs. Same as [set_many empty]. *)
val of_raw : (Coord.t * string) list -> t

(** Raw input of every non-empty cell; the inverse of [of_raw] for saving. *)
val to_raw : t -> (Coord.t * string) list

(** Coordinates whose cell differs between two sheets (in raw input or value),
    ascending. Used after undo/redo to tell the frontend what to repaint.
    Fast when the sheets share structure. *)
val diff : t -> t -> Coord.t list

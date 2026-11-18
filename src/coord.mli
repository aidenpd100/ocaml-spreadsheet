
(** Represents a cell's location in the spreadsheet using zero-based
    row and column indices. A1 corresponds to (0, 0). *)
type t

(** Creates a coordinate from a row and column.
    Returns [None] if either index is negative. *)
val create_coord : int -> int -> t option

(** Returns the zero-based row index of a coordinate. *)
val get_row : t -> int

(** Returns the zero-based column index of a coordinate. *)
val get_col : t -> int

(** Converts an A1-style cell reference into a coordinate.
    Case-insensitive. Returns [None] for invalid references. *)
val of_a1 : string -> t option

(** Converts a coordinate into an A1-style cell reference. *)
val to_a1 : t -> string

(** Returns all coordinates within the rectangle defined by two
    corners, including both endpoints, regardless of their order. *)
val range : t -> t -> t list

(** Compares two coordinates by row first, then column.
    Returns a negative integer, zero, or a positive integer. *)
val compare : t -> t -> int

(** Maps that use coordinates as keys. *)
module Map : Map.S with type key = t

(** Sets containing unique coordinates. *)
module Set : Set.S with type elt = t

(*POTENTIALLY NEED THE THE FUNCTIONS SET FOR COL AND ROW. WILL CHECK LATER*)
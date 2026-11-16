(*The purpose of this module is to define the coordinate system for the spreadsheet.
- It needs to represent a cells locations
- It needs to convert between spreadsheet references (i.e. A1 or B3) to internal coordinates (x,y). This will most likley be a tuple
- It needs to provide functions for creating and manipulating coordinates
- Generate ranges of cells. For exampleif they are using the SUM formula
- Needs to support Coord.Map and Coord.Set
- val compare : t -> t -> int
*)

type t

val create_coord : int -> int -> t option

val get_row : t -> int

val get_col : t -> int

val of_a1 : string -> t option

val to_a1 : t -> string 

val range : t -> t -> t list

val compare : t -> t -> int

module Map : Map.S with type key = t (*the map uses keys but its values can be any type*)

module Set : Set.S with type elt = t (*The set contains unique coordinates*)
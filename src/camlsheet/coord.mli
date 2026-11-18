(** 0-indexed row/col values *)
type t = { row : int; col : int } [@@deriving equal, sexp]

(** [is_valid_cell_ref cell_ref_str] returns Some t if the
    cell reference string is a valid and [None] o/w
    where letters are the column and number is the row (both 1-indexed)
    valid : case-insensitive letter(s) followed by whole number > 0
    Examples
    [is_valid_cell_ref "A1"]  = [Some { row = 0; col = 0 }]
    [is_valid_cell_ref "a1"]  = [Some { row = 0; col = 0 }]
    [is_valid_cell_ref "AA1"] = [Some { row = 0; col = 26 }]
    [is_valid_cell_ref "A0"]  = [None] b/c 0 isnt > 0
*)
val is_valid_cell_ref : string -> t option
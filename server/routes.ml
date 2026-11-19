
(** Temporary route implementations for the design phase.
    TODO: Replace these with the actual API logic. *)

let not_implemented _request =
  Dream.respond ~status:(`Status 501) "Not implemented yet"

let get_cells = not_implemented

let get_cell = not_implemented

let update_cell = not_implemented

let save_sheet = not_implemented

let load_sheet = not_implemented

let undo = not_implemented

let redo = not_implemented

let get_history = not_implemented

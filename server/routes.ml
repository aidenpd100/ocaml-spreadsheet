
(** Temporary route implementations for the design phase.
    TODO: Replace these with the actual API logic. *)

let not_implemented _request =
  Dream.respond ~status:(`Status 501) "Not implemented yet"

(* TODO *)
let get_cells = not_implemented

(* TODO *)
let get_cell = not_implemented

(* TODO *)
let update_cell = not_implemented

(* TODO *)
let save_sheet = not_implemented

(* TODO *)
let load_sheet = not_implemented

(* TODO *)
let undo = not_implemented

(* TODO *)
let redo = not_implemented

(* TODO *)
let get_history = not_implemented

(** Handles HTTP requests for the Camlsheet API. *)

(** Retrieves all non-empty cells within a specified range. *)
val get_cells : Dream.handler

(** Retrieves a single cell by its coordinate. *)
val get_cell : Dream.handler

(** Updates or clears a cell and returns the affected cells. *)
val update_cell : Dream.handler

(** Returns the current spreadsheet as downloadable JSON. *)
val save_sheet : Dream.handler

(** Loads an uploaded JSON spreadsheet, replacing the current sheet.
    Returns an error if the uploaded data is invalid. *)
val load_sheet : Dream.handler

(** Undoes the most recent spreadsheet edit.
    Returns an error if there is nothing to undo. *)
val undo : Dream.handler

(** Redoes the most recently undone spreadsheet edit.
    Returns an error if there is nothing to redo. *)
val redo : Dream.handler

(** Returns whether undo and redo operations are available. *)
val get_history : Dream.handler
(** Manages the current spreadsheet and its history
    within the Dream server. *)

(** Returns the current spreadsheet. *)
val get_sheet : unit -> Sheet.t

(** Records an updated spreadsheet in the history,
    allowing the previous version to be restored. *)
val push_sheet : Sheet.t -> unit

(** Replaces the current spreadsheet with a new one
    and resets the undo/redo history. *)
val replace_sheet : Sheet.t -> unit

(** Undoes the most recent spreadsheet edit.
    Returns [Ok ()] if successful, or [Error message]
    if there is nothing to undo. *)
val undo : unit -> (unit, string) result

(** Redoes the most recently undone spreadsheet edit.
    Returns [Ok ()] if successful, or [Error message]
    if there is nothing to redo. *)
val redo : unit -> (unit, string) result

(** Returns [true] if there is a previous spreadsheet
    version available to undo. *)
val can_undo : unit -> bool

(** Returns [true] if there is an undone spreadsheet
    version available to redo. *)
val can_redo : unit -> bool
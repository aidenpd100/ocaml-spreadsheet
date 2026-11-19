(** Handles JSON conversion between the OCaml backend and frontend.
    Converts spreadsheet cells into JSON and extracts user input
    from incoming JSON requests. *)

(** Converts a single cell into JSON containing its coordinate,
    raw input, displayed value, and value type. *)
val cell_to_json : Coord.t -> Camlsheet.Sheet.cell -> Yojson.Safe.t

(** Converts all affected cells into JSON after a spreadsheet update.
    Uses the updated sheet and a list of affected coordinates to
    retrieve their current values. Includes cleared cells so the
    frontend knows which cells to remove. *)
val changed_to_json : Camlsheet.Sheet.t -> Coord.t list -> Yojson.Safe.t

(** Extracts the raw input from a JSON object.
    Returns [Ok raw] if the input is valid, or [Error message]
    if the raw field is missing or is not a string. *)
val raw_of_json : Yojson.Safe.t -> (string, string) result

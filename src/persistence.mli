(** Handles saving and loading spreadsheets across sessions.
    Converts spreadsheet data to and from JSON and manages
    reading and writing spreadsheet files. *)

(** Converts a spreadsheet into JSON for saving.
    Stores cell coordinates and raw inputs rather than
    calculated values, which can be recomputed when loading. *)
val sheet_to_json : Camlsheet.Sheet.t -> Yojson.Safe.t

(** Reconstructs a spreadsheet from saved JSON.
    Returns [Ok sheet] if the JSON is valid, or [Error message]
    if the data is missing, malformed, or invalid. *)
val json_to_sheet : Yojson.Safe.t -> (Camlsheet.Sheet.t, string) result

(** Saves a spreadsheet as JSON to the specified file path.
    Returns [Ok ()] if the file is saved successfully, or
    [Error message] if the file cannot be written. *)
val save_sheet : string -> Camlsheet.Sheet.t -> (unit, string) result

(** Loads a spreadsheet from the specified file path.
    Returns [Ok sheet] if the file is successfully read and
    reconstructed, or [Error message] if loading fails. *)
val load_sheet : string -> (Camlsheet.Sheet.t, string) result
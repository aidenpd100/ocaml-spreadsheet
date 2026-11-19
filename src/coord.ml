open Core

module T = struct
  type t = { row : int; col : int } [@@deriving compare, sexp]
end

include T
include Comparable.Make (T)

let letters_to_col_num (letters : string) : int =
  (* function that adds the letter value to the running column total*)
  let fold_fun (acc : int * int) (letter : char) : int * int =
    let running_col_num, index = acc in
    let letter_value = Char.to_int (Char.uppercase letter) - Char.to_int 'A' + 1 in
    (running_col_num + (letter_value * (Int.pow 26 index)), index + 1)
  in
  (* fold across the letters and accumulate a column position *)
  let col_num, _ = String.fold (String.rev letters) ~init:(0, 0) ~f:fold_fun in
  col_num

let of_a1 (cell_ref_str : string) =
  (* the leading letters are the column *)
  let letters = String.take_while cell_ref_str ~f:Char.is_alpha in
  (* everything after the letters should be the row number *)
  let digits = String.drop_prefix cell_ref_str (String.length letters) in
  (* converting column label to 1 based column index *)
  let col = letters_to_col_num letters in
  (* convert (digits, col) -> (row, col) 0 based *)
  match Int.of_string_opt digits with
  | Some row
    (* must be > 0 to be a valid row *)
    when Int.(row > 0)
         && (not (String.is_empty letters))             (* calling from lexer guarantees this is true *)
         && String.for_all digits ~f:Char.is_digit ->   (* calling from lexer guarantees this is true *)
    Some { row = row - 1; col = col - 1 }
  | _ -> None (* will only return None on invalid row numbers
                 when calling from lexer *)

let create_coord _ _ = failwith "TODO"
let get_row _ = failwith "TODO"
let get_col _ = failwith "TODO"
let to_a1 _ = failwith "TODO"
let range _ _ = failwith "TODO"
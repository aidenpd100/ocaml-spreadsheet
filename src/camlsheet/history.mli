(** Undo/redo over any persistent value.

    Polymorphic, so it works for any immutable state, not just sheets. Since [Sheet.t] is persistent storing a past version costs only the cells that changed, not a copy of the whole sheet.

    Representation: a zipper — the current value plus a stack of past values and a stack of undone ("future") values. *)

type 'a t

(** A history whose only state is the given value. *)
val create : 'a -> 'a t

(** The current state. *)
val current : 'a t -> 'a

(** [push h x] makes [x] the new current state. The old current goes onto the
    undo stack and the redo stack is cleared, as in any editor. If [limit] was
    reached, the oldest state is dropped. *)
val push : 'a t -> 'a -> 'a t

(** Step back one state; [None] if there is nothing to undo. *)
val undo : 'a t -> 'a t option

(** Step forward one undone state; [None] if there is nothing to redo. *)
val redo : 'a t -> 'a t option

val can_undo : 'a t -> bool
val can_redo : 'a t -> bool

(** [with_limit n h] keeps at most [n] past states (default: 100). *)
val with_limit : int -> 'a t -> 'a t

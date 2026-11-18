(** Depgraph: a general, persistent dependency graph.

    This library knows nothing about spreadsheets. A key is anything that can
    depend on other keys (could be a spreadsheet cell, a file in a build system, a task
    in a scheduler). The graph answers this question: "Key [k] just changed. Which keys must be recomputed, and in what order, so that every key is recomputed only after everything it depends on?"

    Everything is purely functional, and every operation that "changes" a graph returns a new graph and leaves the old one untouched (so old graphs can be saved at no extra cost)

    Terminology: [a] reads [b] --> [a] depends on [b], [b] is a dependency of [a], and [a] is a dependent of [b]. 

*)

(** What the functor needs to know about a key: how to compare two keys (to store them in maps and sets) and how to print them (for errors and tests) *)
module type Key = sig
  type t [@@deriving compare, sexp]
end

module type S = sig
  type key

  (** A dependency graph. Consists of two maps kept in sync:
      - [forward]: key -> set of keys it depends on
      - [reverse]: key -> set of keys that depend on it

      Invariant: [b] is in [forward a] if and only if [a] is in [reverse b].
      The reverse map makes [dependents] a lookup instead of a full scan. *)
  type t

  (** The graph with no keys and no edges. *)
  val empty : t

  (** [set_deps g k ds] makes [k] depend on exactly the keys in [ds],
      replacing whatever [k] depended on before. Duplicates in [ds] are
      ignored. [k] may list itself, which creates a one-key cycle.

      Ex: after [set_deps g "C1" ["B1"]], [deps g "C1"] is [["B1"]] and
      ["C1"] is among [dependents g "B1"]. *)
  val set_deps : t -> key -> key list -> t

  (** [remove g k] removes [k]'s own outgoing edges (what [k] depends on).
      Keys that depend on [k] keep their edges, since they still refer to [k]
      even though it is now empty. Same as [set_deps g k . *)
  val remove : t -> key -> t

  (** Keys that [k] depends on directly, in ascending order. [[]] if [k] is unknown. *)
  val deps : t -> key -> key list

  (** Keys that depend on [k] directly, in ascending order. [[]] if [k] is unknown. *)
  val dependents : t -> key -> key list

  (** Every key that has at least one edge in or out, in ascending order. *)
  val keys : t -> key list

  (** The result of planning a recalculation. *)
  type plan = {
    order : key list;
        (** The changed keys and everything that transitively depends on them,
            in topological order: each key appears after all of its
            dependencies that are also in the plan. *)
    in_cycle : key list;
        (** Keys that are part of a cycle, or depend (directly or indirectly)
            on one. These cannot be ordered and should be marked as errors
            rather than computed. Ascending order. *)
  }

  (** [recalc_plan g k] is the plan for recomputing after [k] changed.

      Algorithm:
      1. Depth-first search from [k] along reverse edges to collect the set
         [R] of every key that can be affected.
      2. Kahn's algorithm restricted to [R]: count each key's dependencies
         inside [R], repeatedly output a key whose count is 0 and decrement
         its dependents' counts. Keys whose count never reaches 0 are waiting
         on a cycle and go in [in_cycle].

      Cost is proportional to the size of the affected subgraph, not the whole
      graph. Every key in [R] appears in exactly one of [order] or [in_cycle]. *)
  val recalc_plan : t -> key -> plan

  (** Same as [recalc_plan], starting from several changed keys at once (for
      loading a saved sheet or pasting many cells). Each affected key appears
      once *)
  val recalc_plan_many : t -> key list -> plan

  (** Debugging and testing: every edge as [(k, dependency)] pairs *)
  val to_sexp : t -> Core.Sexp.t
end

(** Build a dependency graph over any key type *)
module Make (Key : Key) : S with type key = Key.t

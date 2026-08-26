defmodule Kumi.Schema.Column do
  @moduledoc """
  A single table column, described identically whether it came from
  `Kumi.Actual` (pg_catalog introspection) or `Kumi.Desired` (Ash resource
  extraction) so the two sides diff cleanly.

  `default` is normalized rather than kept as raw SQL/Ash terms:

    * `nil` — no default
    * `{:literal, string}` — a fixed value (e.g. `'lead'::text` or an Ash
      literal default like `:lead`)
    * `:generated` — a function/DB-expression default (e.g.
      `&Ash.UUID.generate/0` on the code side, `gen_random_uuid()` on the DB
      side). We don't compare the exact expression text — see
      `Kumi.Schema.Default` and the Spike 1 friction log.

  `datetime_precision` is compared by plain equality like every other field
  (`Kumi.Diff` does not special-case it) — it is `nil` for any non-datetime
  column on both sides (so it never diffs in practice) and an integer (0-6)
  for a `timestamp`-family column: fractional-second digits stored.
  `:utc_datetime` / `:naive_datetime` are always precision 0;
  `:utc_datetime_usec` / `:naive_datetime_usec` default to precision 6 in
  Postgres. A `nil` vs. integer mismatch can only arise alongside a `:type`
  change (a column becoming/stopping being a timestamp type) — see the
  defensive fallback clause in `Kumi.Plan.Safety.classify_change/2`, which
  lets that accompanying type change's DANGEROUS classification dominate.
  See `Kumi.Desired.PgType.precision_from_ash/2` and v0.1.5 friction log
  (F18, F33-35).
  """

  @enforce_keys [:name, :type, :nullable]
  defstruct [:name, :type, :nullable, default: nil, datetime_precision: nil]

  @type default :: nil | {:literal, String.t()} | :generated

  @type t :: %__MODULE__{
          name: String.t(),
          type: String.t(),
          nullable: boolean(),
          default: default(),
          datetime_precision: non_neg_integer() | nil
        }
end

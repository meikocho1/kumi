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
  (`Kumi.Diff` does not special-case it). It is NOT nil-for-every-non-
  timestamp-column: Postgres reports a real integer for `date` (`0`) and
  `interval` (`6`) columns too, not just `timestamp`/`time` — confirmed
  empirically against a real Postgres 17. It is `nil` only for types
  Postgres genuinely reports no precision for at all
  (`uuid`, `text`, `numeric`, `bool`, `jsonb`, arrays, ...). For the
  precision-bearing types: `:date` is always `0`; `:time` / `:utc_datetime`
  / `:naive_datetime` are always `0`; `:time_usec` / `:utc_datetime_usec` /
  `:naive_datetime_usec` / `:duration` default to `6` in Postgres. A `nil`
  vs. integer mismatch usually arrives alongside a `:type` change (a column
  becoming/stopping being a precision-bearing type), but `Kumi.Plan.Safety`
  does NOT assume that — a change list can, in principle, carry a
  `:datetime_precision` change with no `:type` entry (e.g. an unmapped or
  future `PgType` gap), so `classify_change/2`'s catch-all classifies that
  case REVIEW on its own merits rather than trusting a sibling change to
  dominate it.
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

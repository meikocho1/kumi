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
  """

  @enforce_keys [:name, :type, :nullable]
  defstruct [:name, :type, :nullable, default: nil]

  @type default :: nil | {:literal, String.t()} | :generated

  @type t :: %__MODULE__{
          name: String.t(),
          type: String.t(),
          nullable: boolean(),
          default: default()
        }
end

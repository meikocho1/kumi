defmodule Kumi.Plan.Finding do
  @moduledoc """
  One data-aware probe result, produced by `Kumi.Probe` and attached to a
  `Kumi.Plan`'s `:findings` list.

  A finding ANNOTATES an already-classified operation with a live-data fact
  (a row count) — it never changes that operation's `Kumi.Plan.Safety`
  level. Classification must stay deterministic from schema alone
  (reproducible without ever touching the database, and without which
  `--check`'s exit code would depend on what happens to be in the tables
  right now); a finding is evidence for the human reviewer sitting on top
  of that classification, not an input to it. A `count` of 0 still produces
  a finding ("0 rows affected") at the SAME safety level — the finding
  reports data, it doesn't downgrade risk.

  `op` matches the exact `Kumi.Diff`/`Kumi.Plan.Rename` operation tuple it
  was probed for, so `Kumi.Plan.Format` can render findings indented under
  their operation.
  """

  @enforce_keys [:op, :query_description, :count, :note]
  defstruct [:op, :query_description, :count, :note]

  @type t :: %__MODULE__{
          op: Kumi.Diff.op(),
          query_description: String.t(),
          count: non_neg_integer(),
          note: String.t()
        }
end

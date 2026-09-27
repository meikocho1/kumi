defmodule Kumi.Schema.Index do
  @moduledoc """
  A secondary index. Primary key indexes are represented on
  `Kumi.Schema.Table.primary_key` instead, not here — Postgres and Ash agree
  on primary keys structurally, so there is no need to diff them as generic
  indexes too.

  `exact?` is false for a custom index that carries something this struct
  has no field for (`where`, `using`, `include`, an expression or ordered
  field, ...): `CREATE INDEX name ON table (columns)` would build a
  different index. `Kumi.Desired` sets it; `Kumi.Diff` never reads it, and
  only `Kumi.Apply` acts on it.
  """

  @enforce_keys [:name, :columns, :unique]
  defstruct [:name, :columns, :unique, exact?: true]

  @type t :: %__MODULE__{
          name: String.t(),
          columns: [String.t()],
          unique: boolean(),
          exact?: boolean()
        }
end

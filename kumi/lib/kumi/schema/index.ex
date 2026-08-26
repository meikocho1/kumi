defmodule Kumi.Schema.Index do
  @moduledoc """
  A secondary index. Primary key indexes are represented on
  `Kumi.Schema.Table.primary_key` instead, not here — Postgres and Ash agree
  on primary keys structurally, so there is no need to diff them as generic
  indexes too.
  """

  @enforce_keys [:name, :columns, :unique]
  defstruct [:name, :columns, :unique]

  @type t :: %__MODULE__{
          name: String.t(),
          columns: [String.t()],
          unique: boolean()
        }
end

defmodule Kumi.Schema.Table do
  @moduledoc "A table: its columns, primary key, foreign keys and secondary indexes."

  alias Kumi.Schema.{Column, ForeignKey, Index}

  @enforce_keys [:name]
  defstruct [:name, columns: [], primary_key: [], foreign_keys: [], indexes: []]

  @type t :: %__MODULE__{
          name: String.t(),
          columns: [Column.t()],
          primary_key: [String.t()],
          foreign_keys: [ForeignKey.t()],
          indexes: [Index.t()]
        }
end

defmodule Kumi.Schema.ForeignKey do
  @moduledoc "A foreign key constraint on one column of a table."

  @enforce_keys [:name, :column, :references_table, :references_column]
  defstruct [:name, :column, :references_table, :references_column]

  @type t :: %__MODULE__{
          name: String.t(),
          column: String.t(),
          references_table: String.t(),
          references_column: String.t()
        }
end

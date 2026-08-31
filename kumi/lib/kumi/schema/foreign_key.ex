defmodule Kumi.Schema.ForeignKey do
  @moduledoc "A foreign key constraint on one column of a table."

  @enforce_keys [:name, :column, :references_table, :references_column]
  # `on_delete` is deliberately not in `@enforce_keys`: Postgres's own
  # default is NO ACTION, so an omitted delete rule reads correctly as
  # `:nothing`, and every existing construction site keeps compiling.
  defstruct [:name, :column, :references_table, :references_column, on_delete: :nothing]

  @typedoc "A delete rule in Ash's vocabulary, mapping to Postgres's CASCADE / SET NULL / RESTRICT / NO ACTION."
  @type on_delete :: :delete | :nilify | :nothing | :restrict

  @type t :: %__MODULE__{
          name: String.t(),
          column: String.t(),
          references_table: String.t(),
          references_column: String.t(),
          on_delete: on_delete()
        }
end

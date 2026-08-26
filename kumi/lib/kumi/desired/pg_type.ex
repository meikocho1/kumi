defmodule Kumi.Desired.PgType do
  @moduledoc """
  Maps an Ash attribute type + constraints to the postgres type name that
  `Kumi.Actual` would report for the same column (i.e. `udt_name`).

  This reuses `AshPostgres.MigrationGenerator.get_migration_type/2` — the
  exact function AshPostgres itself uses to decide migration column types —
  rather than re-deriving the Ash-type-to-postgres-type mapping by hand.
  That call returns an Ecto migration type (`:uuid`, `:text`, `{:decimal, _,
  _}`, ...); the second step below mirrors Ecto's own
  `Ecto.Adapters.Postgres.Connection.ecto_to_db/1`, which is what turns that
  migration type into the literal SQL type Postgres stores (and therefore
  what pg_catalog reports back).
  """

  @spec from_ash(module(), keyword()) :: String.t()
  def from_ash(type, constraints) do
    type
    |> AshPostgres.MigrationGenerator.get_migration_type(constraints)
    |> to_pg_name()
  end

  defp to_pg_name({:decimal, _precision, _scale}), do: "numeric"
  defp to_pg_name({:decimal, _size, _precision, _scale}), do: "numeric"
  defp to_pg_name({:array, inner}), do: "_#{to_pg_name(inner)}"
  defp to_pg_name(:utc_datetime), do: "timestamp"
  defp to_pg_name(:utc_datetime_usec), do: "timestamp"
  defp to_pg_name(:naive_datetime), do: "timestamp"
  defp to_pg_name(:naive_datetime_usec), do: "timestamp"
  defp to_pg_name(:map), do: "jsonb"
  defp to_pg_name(:boolean), do: "bool"
  defp to_pg_name(:bigint), do: "int8"
  defp to_pg_name(:integer), do: "int4"
  defp to_pg_name(atom) when is_atom(atom), do: Atom.to_string(atom)
end

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

  @doc """
  Expected `information_schema.columns.datetime_precision` for an Ash
  attribute, or `nil` for a non-datetime type.

  Empirically verified against `Ecto.Adapters.Postgres.Connection` (the
  module that actually emits the `CREATE TABLE`/`ALTER TABLE` column type
  SQL): `:utc_datetime`/`:naive_datetime`/`:time` are hardcoded to
  `timestamp(0)` — no precision option exists for them. The `_usec` variants
  get no explicit `(N)` at all unless a `:precision` migration option is
  passed (AshPostgres does not pass one for these types), so Postgres
  applies its own default, which is 6. Confirmed against the real spike DB:
  `tokens.expires_at` (`:utc_datetime`) is precision 0, `users.confirmed_at`
  (`:utc_datetime_usec`) and every `timestamps()`-generated column (which
  default to `:utc_datetime_usec`) are precision 6.
  """
  @spec precision_from_ash(module(), keyword()) :: 0 | 6 | nil
  def precision_from_ash(type, constraints) do
    case AshPostgres.MigrationGenerator.get_migration_type(type, constraints) do
      migration_type when migration_type in [:utc_datetime, :naive_datetime, :time] ->
        0

      migration_type
      when migration_type in [:utc_datetime_usec, :naive_datetime_usec, :time_usec] ->
        6

      _other ->
        nil
    end
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

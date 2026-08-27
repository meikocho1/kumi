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

  # Parameterized types we don't map explicitly: AshPostgres returns them as
  # `{name, arg, ...}` (e.g. `{:vector, 1536}` for `Ash.Type.Vector` with
  # `dimensions:`). Postgres reports only the bare type name in
  # `information_schema.columns.udt_name` ("vector"), so the first element is
  # the right desired-side value. Without this clause an unmapped shape raised
  # a FunctionClauseError, which broke `mix kumi.plan` outright instead of
  # failing closed — pgvector columns made the whole plan unusable.
  defp to_pg_name(tuple) when is_tuple(tuple) and tuple_size(tuple) > 0,
    do: tuple |> elem(0) |> to_pg_name()

  # Last resort: never crash the plan on an unrecognized type. An inspected
  # value will not match any real `udt_name`, so it surfaces as a change and
  # `Kumi.Plan.Safety` classifies the unknown pair DANGEROUS — fail closed.
  defp to_pg_name(other), do: inspect(other)
end

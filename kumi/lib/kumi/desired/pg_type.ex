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
  attribute, or `nil` for a type Postgres reports no precision for at all.

  Empirically verified against a real Postgres 17 (`kumi_test`, see
  `pg_type_test.exs` and the H4 fix report for the full comparison table):
  `information_schema.columns.datetime_precision` is not exclusive to
  `timestamp`/`time` columns — `date` and `interval` report a value too.

    * `:date` — always `0` (a date has no sub-day component to have a
      precision at all; Postgres still reports `0`, not `nil`).
    * `:time`/`:utc_datetime`/`:naive_datetime` — hardcoded by
      `Ecto.Adapters.Postgres.Connection` to `time(0)`/`timestamp(0)` — no
      precision option exists for them, so `0`.
    * `:time_usec`/`:utc_datetime_usec`/`:naive_datetime_usec` — get no
      explicit `(N)` at all unless a `:precision` migration option is passed
      (AshPostgres does not pass one for these types), so Postgres applies
      its own default, which is `6`. Confirmed against the real spike DB:
      `tokens.expires_at` (`:utc_datetime`) is precision 0,
      `users.confirmed_at` (`:utc_datetime_usec`) and every
      `timestamps()`-generated column (which default to
      `:utc_datetime_usec`) are precision 6.
    * `:duration` — `Ash.Type.Duration` carries no precision/fields
      constraints, so AshPostgres never passes migration options for it
      either; Ecto emits a bare `interval` column, and Postgres defaults
      that to precision `6`, same reasoning as the `_usec` types above.

  Every other type (`uuid`, `text`, `numeric`, `bool`, `jsonb`, arrays, ...)
  reports `NULL` for `datetime_precision` — confirmed empirically — so `nil`
  remains correct there.
  """
  @spec precision_from_ash(module(), keyword()) :: 0 | 6 | nil
  def precision_from_ash(type, constraints) do
    case AshPostgres.MigrationGenerator.get_migration_type(type, constraints) do
      migration_type when migration_type in [:date, :utc_datetime, :naive_datetime, :time] ->
        0

      migration_type
      when migration_type in [
             :utc_datetime_usec,
             :naive_datetime_usec,
             :time_usec,
             :duration
           ] ->
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

  # Empirically verified (see precision_from_ash/2 moduledoc): Ecto's
  # ecto_to_db/1 maps the :duration migration type to "interval", not the
  # atom's own name. Without this clause the generic atom fallback below
  # returned "duration", which never equals the real udt_name ("interval")
  # — a permanent phantom type-change diff on every Ash.Type.Duration
  # column. That bug at least failed closed (mismatched string ->
  # classified DANGEROUS), unlike the :date precision bug this module also
  # fixes — but it is still wrong, and worth fixing outright.
  defp to_pg_name(:duration), do: "interval"
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
  #
  # Known blind spot (L1): this clause discards the arguments after the
  # first element, so `dimensions` is compared to nothing. A pgvector
  # column changing `dimensions: 768` -> `dimensions: 1536` produces
  # `"vector"` on both sides of the diff — no `:type` change, no diff at
  # all. Kumi is structurally blind to vector dimension drift; out of
  # scope to fix here (see `pg_type_test.exs`, "dimension drift is
  # invisible").
  defp to_pg_name(tuple) when is_tuple(tuple) and tuple_size(tuple) > 0,
    do: tuple |> elem(0) |> to_pg_name()

  # Last resort: never crash the plan on an unrecognized type. An inspected
  # value will not match any real `udt_name`, so it surfaces as a change and
  # `Kumi.Plan.Safety` classifies the unknown pair DANGEROUS — fail closed.
  #
  # Reachable, not hypothetical (L1): every Ash builtin type's migration
  # type is an atom or a tuple (see `AshPostgres.MigrationGenerator.
  # migration_type/2`), so no shipped Ash type reaches this clause. A
  # custom Ash type CAN: `migration_type/1` is an ad hoc AshPostgres
  # extension point (`function_exported?/3`-checked, not part of
  # `Ash.Type`'s own behaviour) that user code can implement to return
  # anything — a map, a list, whatever. `pg_type_test.exs` proves this end
  # to end with a minimal fabricated type.
  defp to_pg_name(other), do: inspect(other)
end

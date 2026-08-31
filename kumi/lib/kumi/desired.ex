defmodule Kumi.Desired do
  @moduledoc """
  Extracts the DESIRED schema from Ash domains/resources — i.e. what the
  database SHOULD look like according to the application's source code.

  Reuses Ash/AshPostgres introspection wholesale (`Ash.Domain.Info`,
  `Ash.Resource.Info`, `AshPostgres.DataLayer.Info`) instead of parsing DSL
  or attribute options by hand. The one piece of hand-built logic is
  `Kumi.Desired.PgType`, which still delegates the hard part (Ash type ->
  Ecto migration type) to `AshPostgres.MigrationGenerator`.
  """

  require Logger

  alias Ash.Resource.Relationships.BelongsTo
  alias AshPostgres.CustomIndex
  alias Kumi.Desired.PgType
  alias Kumi.Schema.{Column, Default, ForeignKey, Index, Table}

  @spec extract([module()]) :: [Table.t()]
  def extract(domains) do
    domains
    |> Enum.flat_map(&Ash.Domain.Info.resources/1)
    |> Enum.uniq()
    |> Enum.filter(&ash_postgres_resource?/1)
    |> Enum.map(&build_table/1)
  end

  defp ash_postgres_resource?(resource) do
    if Ash.Resource.Info.data_layer(resource) == AshPostgres.DataLayer do
      true
    else
      Logger.debug("Kumi.Desired: skipping #{inspect(resource)} — not backed by AshPostgres")
      false
    end
  end

  defp build_table(resource) do
    table = AshPostgres.DataLayer.Info.table(resource)

    %Table{
      name: table,
      columns: columns(resource),
      primary_key: resource |> Ash.Resource.Info.primary_key() |> Enum.map(&to_string/1),
      foreign_keys: foreign_keys(resource, table),
      indexes: indexes(resource, table)
    }
  end

  defp columns(resource) do
    resource
    |> Ash.Resource.Info.attributes()
    |> Enum.map(fn attr ->
      %Column{
        name: to_string(attr.name),
        type: PgType.from_ash(attr.type, attr.constraints),
        nullable: attr.allow_nil?,
        default: Default.from_ash(attr.default),
        datetime_precision: PgType.precision_from_ash(attr.type, attr.constraints)
      }
    end)
  end

  # Only `belongs_to` relationships own a foreign key column on this
  # resource's table (has_many/has_one point the other way).
  defp foreign_keys(resource, table) do
    resource
    |> Ash.Resource.Info.relationships()
    |> Enum.filter(&match?(%BelongsTo{}, &1))
    |> Enum.map(fn rel ->
      references_table = AshPostgres.DataLayer.Info.table(rel.destination)

      %ForeignKey{
        name: "#{table}_#{rel.source_attribute}_fkey",
        column: to_string(rel.source_attribute),
        references_table: references_table,
        references_column: to_string(rel.destination_attribute),
        on_delete: on_delete(resource, rel)
      }
    end)
  end

  # Without a `postgres do references do reference :x, on_delete: ... end end`
  # block AshPostgres emits no delete rule at all, so the column gets
  # Postgres's default (NO ACTION) — read here as `:nothing`, the same value
  # the actual side produces for it.
  defp on_delete(resource, rel) do
    case AshPostgres.DataLayer.Info.reference(resource, rel.name) do
      %{on_delete: value} when not is_nil(value) -> value
      _ -> :nothing
    end
  end

  # Two sources of secondary indexes, unioned: Ash `identities` (unique
  # constraints) and AshPostgres's own `postgres do custom_indexes do ...
  # end end` section (M2) — `Kumi.Actual` introspects EVERY non-PK index
  # from pg_index, so a host that declares a custom_indexes entry, runs
  # `mix ash.codegen` and migrates ends up with a DB matching its code
  # exactly; without this union, Kumi would report that index as a
  # `remove_index` (:review) forever, failing `mix kumi.plan --check` on
  # correct code with no way to silence it.
  defp indexes(resource, table),
    do: identity_indexes(resource, table) ++ custom_indexes(resource, table)

  # AshPostgres names the underlying index "<table>_<identity name>_index"
  # by default.
  defp identity_indexes(resource, table) do
    resource
    |> Ash.Resource.Info.identities()
    |> Enum.map(fn identity ->
      %Index{
        name: "#{table}_#{identity.name}_index",
        columns: Enum.map(identity.keys, &to_string/1),
        unique: true
      }
    end)
  end

  # Mirrors AshPostgres's own migration generator (deps/ash_postgres/lib/
  # migration_generator/migration_generator.ex, `add_custom_index_name/2`):
  # when a custom index has no explicit `name:`, the DDL name is computed
  # as `AshPostgres.CustomIndex.name(table, index)` — an undocumented
  # AshPostgres internal with no compatibility promise (this repo already
  # treats such names as canaries, see the FK/identity naming above and the
  # snapshot-format gotchas in CLAUDE.md). Calling the same function keeps
  # Kumi's desired-side name identical to what actually got created.
  #
  # Only columns/uniqueness/name are represented on `Kumi.Schema.Index` —
  # `where`, `using`, `include`, `nulls_distinct`, `concurrently` etc. (see
  # `AshPostgres.CustomIndex`'s schema) have no field here and are
  # INVISIBLE to the diff: a drift in one of those options alone would not
  # be detected. Deliberately not expanding `%Index{}` to carry them in
  # this pass — see the task notes / friction log for the tradeoff.
  defp custom_indexes(resource, table) do
    resource
    |> AshPostgres.DataLayer.Info.custom_indexes()
    |> Enum.map(fn index ->
      %Index{
        name: to_string(index.name || CustomIndex.name(table, index)),
        columns: Enum.map(index.fields, &to_string(CustomIndex.column_name(&1))),
        unique: index.unique
      }
    end)
  end
end

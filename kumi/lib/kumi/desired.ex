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
        default: Default.from_ash(attr.default)
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
        references_column: to_string(rel.destination_attribute)
      }
    end)
  end

  # Ash `identities` are the source of secondary unique indexes; AshPostgres
  # names the underlying index "<table>_<identity name>_index" by default.
  defp indexes(resource, table) do
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
end

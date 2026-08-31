defmodule Kumi.Actual do
  @moduledoc """
  Introspects the ACTUAL schema live from PostgreSQL's pg_catalog /
  information_schema — never from Ash, never from migration snapshots.
  This is Kumi's wedge: `mix ash.codegen` compares code to its own snapshot
  history, so it cannot see a manually-run `ALTER TABLE`. `Kumi.Actual` asks
  the database itself.

  Only the `public` schema is inspected; `schema_migrations` is excluded
  (it's Ecto's own bookkeeping table, not part of the application schema).
  """

  alias Kumi.Schema.{Column, ForeignKey, Index, Table}
  alias Kumi.Schema.Default

  @excluded_table "schema_migrations"

  @spec introspect(module()) :: [Table.t()]
  def introspect(repo) do
    columns_by_table = columns_by_table(repo)
    pks_by_table = primary_keys_by_table(repo)
    fks_by_table = foreign_keys_by_table(repo)
    indexes_by_table = indexes_by_table(repo)

    columns_by_table
    |> Map.keys()
    |> Enum.sort()
    |> Enum.map(fn name ->
      %Table{
        name: name,
        columns: Map.fetch!(columns_by_table, name),
        primary_key: Map.get(pks_by_table, name, []),
        foreign_keys: Map.get(fks_by_table, name, []),
        indexes: Map.get(indexes_by_table, name, [])
      }
    end)
  end

  # `udt_name` (rather than `data_type`) is used as the canonical postgres
  # type name: for ordinary types it already matches (uuid, text, numeric,
  # timestamp, jsonb...); for `USER-DEFINED` types like citext it resolves to
  # the real name instead of the useless "USER-DEFINED" label.
  defp columns_by_table(repo) do
    sql = """
    SELECT table_name, column_name, is_nullable, column_default, udt_name, datetime_precision
    FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name <> $1
    ORDER BY table_name, ordinal_position
    """

    repo
    |> query!(sql, [@excluded_table])
    |> Enum.group_by(fn [table, _, _, _, _, _] -> table end, fn [
                                                                  _,
                                                                  name,
                                                                  nullable,
                                                                  default,
                                                                  type,
                                                                  datetime_precision
                                                                ] ->
      %Column{
        name: name,
        type: type,
        nullable: nullable == "YES",
        default: Default.from_sql(default),
        datetime_precision: datetime_precision
      }
    end)
  end

  defp primary_keys_by_table(repo) do
    sql = """
    SELECT tc.table_name, kcu.column_name
    FROM information_schema.table_constraints tc
    JOIN information_schema.key_column_usage kcu
      ON tc.constraint_name = kcu.constraint_name AND tc.table_schema = kcu.table_schema
    WHERE tc.constraint_type = 'PRIMARY KEY'
      AND tc.table_schema = 'public'
      AND tc.table_name <> $1
    ORDER BY tc.table_name, kcu.ordinal_position
    """

    repo
    |> query!(sql, [@excluded_table])
    |> Enum.group_by(fn [table, _] -> table end, fn [_, column] -> column end)
  end

  defp foreign_keys_by_table(repo) do
    sql = """
    SELECT tc.table_name, kcu.column_name, ccu.table_name, ccu.column_name,
           tc.constraint_name, rc.delete_rule
    FROM information_schema.table_constraints tc
    JOIN information_schema.key_column_usage kcu
      ON tc.constraint_name = kcu.constraint_name AND tc.table_schema = kcu.table_schema
    JOIN information_schema.constraint_column_usage ccu
      ON tc.constraint_name = ccu.constraint_name AND tc.table_schema = ccu.table_schema
    JOIN information_schema.referential_constraints rc
      ON tc.constraint_name = rc.constraint_name AND tc.table_schema = rc.constraint_schema
    WHERE tc.constraint_type = 'FOREIGN KEY'
      AND tc.table_schema = 'public'
      AND tc.table_name <> $1
    """

    repo
    |> query!(sql, [@excluded_table])
    |> Enum.group_by(
      fn [table, _, _, _, _, _] -> table end,
      fn [_, column, ref_table, ref_column, name, delete_rule] ->
        %ForeignKey{
          name: name,
          column: column,
          references_table: ref_table,
          references_column: ref_column,
          on_delete: on_delete_from_sql(delete_rule)
        }
      end
    )
  end

  # Translated into Ash's vocabulary rather than reported in Postgres's (D1:
  # what Kumi prints is what the user wrote). `NO ACTION` — and anything
  # unrecognised — reads as `:nothing`, which is Postgres's own default.
  defp on_delete_from_sql("CASCADE"), do: :delete
  defp on_delete_from_sql("SET NULL"), do: :nilify
  defp on_delete_from_sql("RESTRICT"), do: :restrict
  defp on_delete_from_sql(_no_action), do: :nothing

  # Built from pg_catalog directly (there's no standard information_schema
  # view for index column lists). `ix.indisprimary = false` excludes the
  # primary key's implicit index — that's tracked on Table.primary_key
  # instead, see Kumi.Schema.Index.
  defp indexes_by_table(repo) do
    sql = """
    SELECT
      t.relname AS table_name,
      i.relname AS index_name,
      ix.indisunique AS is_unique,
      array_agg(a.attname ORDER BY array_position(ix.indkey, a.attnum)) AS columns
    FROM pg_index ix
    JOIN pg_class i ON i.oid = ix.indexrelid
    JOIN pg_class t ON t.oid = ix.indrelid
    JOIN pg_namespace n ON n.oid = t.relnamespace
    JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = ANY(ix.indkey)
    WHERE n.nspname = 'public' AND t.relname <> $1 AND ix.indisprimary = false
    GROUP BY t.relname, i.relname, ix.indisunique
    ORDER BY t.relname, i.relname
    """

    repo
    |> query!(sql, [@excluded_table])
    |> Enum.group_by(
      fn [table, _, _, _] -> table end,
      fn [_, name, unique, columns] -> %Index{name: name, columns: columns, unique: unique} end
    )
  end

  defp query!(repo, sql, params) do
    %{rows: rows} = Ecto.Adapters.SQL.query!(repo, sql, params)
    rows
  end
end

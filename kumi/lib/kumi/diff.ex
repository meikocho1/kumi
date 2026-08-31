defmodule Kumi.Diff do
  @moduledoc """
  Pure diff: (desired, actual) -> list of operations. No classification of
  what's safe to run — that's Spike 3. Just an accurate description of what
  differs, including drift (present in the DB, absent from the code).
  """

  alias Kumi.Schema.Table

  @type op ::
          {:add_table, Table.t()}
          | {:drop_table, Table.t()}
          | {:add_column, String.t(), Kumi.Schema.Column.t()}
          | {:remove_column, String.t(), Kumi.Schema.Column.t()}
          | {:change_column, String.t(), Kumi.Schema.Column.t(), [{atom(), term(), term()}]}
          | {:change_primary_key, String.t(), [String.t()], [String.t()]}
          | {:add_fk, String.t(), Kumi.Schema.ForeignKey.t()}
          | {:remove_fk, String.t(), Kumi.Schema.ForeignKey.t()}
          | {:change_fk, String.t(), Kumi.Schema.ForeignKey.t(), Kumi.Schema.ForeignKey.t()}
          | {:change_fk_on_delete, String.t(), Kumi.Schema.ForeignKey.t(),
             Kumi.Schema.ForeignKey.t()}
          | {:add_index, String.t(), Kumi.Schema.Index.t()}
          | {:remove_index, String.t(), Kumi.Schema.Index.t()}
          | {:change_index, String.t(), Kumi.Schema.Index.t(), Kumi.Schema.Index.t()}

  @spec diff([Table.t()], [Table.t()]) :: [op()]
  def diff(desired, actual) do
    desired_by_name = index_by(desired, & &1.name)
    actual_by_name = index_by(actual, & &1.name)

    add_tables =
      for {name, table} <- desired_by_name,
          not Map.has_key?(actual_by_name, name),
          do: {:add_table, table}

    drop_tables =
      for {name, table} <- actual_by_name,
          not Map.has_key?(desired_by_name, name),
          do: {:drop_table, table}

    table_ops =
      for {name, desired_table} <- desired_by_name,
          actual_table = actual_by_name[name],
          not is_nil(actual_table) do
        diff_table(desired_table, actual_table)
      end

    add_tables ++ drop_tables ++ List.flatten(table_ops)
  end

  defp diff_table(%Table{name: table} = desired, %Table{} = actual) do
    diff_primary_key(table, desired.primary_key, actual.primary_key) ++
      diff_columns(table, desired.columns, actual.columns) ++
      diff_fks(table, desired.foreign_keys, actual.foreign_keys) ++
      diff_indexes(table, desired.indexes, actual.indexes)
  end

  # Primary key column ORDER is significant in Postgres (a composite PK's
  # column order determines the underlying btree's leading column, which
  # affects which queries it can serve) — compared as ordered lists, not
  # sets, unlike the name-keyed comparisons below.
  defp diff_primary_key(_table, same, same), do: []

  defp diff_primary_key(table, desired_pk, actual_pk),
    do: [{:change_primary_key, table, desired_pk, actual_pk}]

  defp diff_columns(table, desired_cols, actual_cols) do
    desired_by_name = index_by(desired_cols, & &1.name)
    actual_by_name = index_by(actual_cols, & &1.name)

    adds =
      for {name, col} <- desired_by_name,
          not Map.has_key?(actual_by_name, name),
          do: {:add_column, table, col}

    removes =
      for {name, col} <- actual_by_name,
          not Map.has_key?(desired_by_name, name),
          do: {:remove_column, table, col}

    changes =
      for {name, desired_col} <- desired_by_name,
          actual_col = actual_by_name[name],
          not is_nil(actual_col),
          changes = column_changes(desired_col, actual_col),
          changes != [] do
        {:change_column, table, desired_col, changes}
      end

    adds ++ removes ++ changes
  end

  defp column_changes(desired, actual) do
    []
    |> field_change(:type, desired.type, actual.type)
    |> field_change(:nullable, desired.nullable, actual.nullable)
    |> field_change(:default, desired.default, actual.default)
    |> field_change(:datetime_precision, desired.datetime_precision, actual.datetime_precision)
  end

  defp field_change(acc, _field, same, same), do: acc
  defp field_change(acc, field, desired, actual), do: [{field, desired, actual} | acc]

  defp diff_fks(table, desired_fks, actual_fks) do
    desired_by_col = index_by(desired_fks, & &1.column)
    actual_by_col = index_by(actual_fks, & &1.column)

    adds =
      for {col, fk} <- desired_by_col,
          not Map.has_key?(actual_by_col, col),
          do: {:add_fk, table, fk}

    removes =
      for {col, fk} <- actual_by_col,
          not Map.has_key?(desired_by_col, col),
          do: {:remove_fk, table, fk}

    changes =
      for {col, desired_fk} <- desired_by_col,
          actual_fk = actual_by_col[col],
          not is_nil(actual_fk),
          fk_target_changed?(desired_fk, actual_fk),
          do: {:change_fk, table, desired_fk, actual_fk}

    # A changed target and a changed delete rule ask the reader for different
    # work, so they are different operations. Folding them together would
    # leave every message able to say only "the foreign key changed".
    on_delete_changes =
      for {col, desired_fk} <- desired_by_col,
          actual_fk = actual_by_col[col],
          not is_nil(actual_fk),
          not fk_target_changed?(desired_fk, actual_fk),
          desired_fk.on_delete != actual_fk.on_delete,
          do: {:change_fk_on_delete, table, desired_fk, actual_fk}

    adds ++ removes ++ changes ++ on_delete_changes
  end

  defp fk_target_changed?(desired, actual),
    do:
      desired.references_table != actual.references_table or
        desired.references_column != actual.references_column

  defp diff_indexes(table, desired_indexes, actual_indexes) do
    desired_by_name = index_by(desired_indexes, & &1.name)
    actual_by_name = index_by(actual_indexes, & &1.name)

    adds =
      for {name, idx} <- desired_by_name,
          not Map.has_key?(actual_by_name, name),
          do: {:add_index, table, idx}

    removes =
      for {name, idx} <- actual_by_name,
          not Map.has_key?(desired_by_name, name),
          do: {:remove_index, table, idx}

    changes =
      for {name, desired_idx} <- desired_by_name,
          actual_idx = actual_by_name[name],
          not is_nil(actual_idx),
          index_definition_changed?(desired_idx, actual_idx),
          do: {:change_index, table, desired_idx, actual_idx}

    adds ++ removes ++ changes
  end

  defp index_definition_changed?(desired, actual),
    do: desired.columns != actual.columns or desired.unique != actual.unique

  defp index_by(list, fun), do: Map.new(list, fn item -> {fun.(item), item} end)
end

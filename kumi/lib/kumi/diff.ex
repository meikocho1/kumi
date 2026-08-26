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
          | {:add_fk, String.t(), Kumi.Schema.ForeignKey.t()}
          | {:remove_fk, String.t(), Kumi.Schema.ForeignKey.t()}
          | {:add_index, String.t(), Kumi.Schema.Index.t()}
          | {:remove_index, String.t(), Kumi.Schema.Index.t()}

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
    diff_columns(table, desired.columns, actual.columns) ++
      diff_fks(table, desired.foreign_keys, actual.foreign_keys) ++
      diff_indexes(table, desired.indexes, actual.indexes)
  end

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

    adds ++ removes
  end

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

    adds ++ removes
  end

  defp index_by(list, fun), do: Map.new(list, fn item -> {fun.(item), item} end)
end

defmodule Kumi.Plan.Format do
  @moduledoc """
  Renders a `Kumi.Diff` (+ `Kumi.Plan.Rename`) operation list as readable
  +/-/~ text, grouped per table, with each line's `Kumi.Plan.Safety`
  classification and reason, and an overall "N safe / N review / N
  dangerous" summary line.
  """

  alias Kumi.Plan.{Rename, Safety}

  @spec format([Kumi.Diff.op()], keyword()) :: String.t()
  def format(ops, opts \\ [])
  def format([], _opts), do: "No changes. Database matches application definition.\n"

  def format(ops, opts) do
    verbose? = Keyword.get(opts, :verbose, false)
    snapshot_dir = Keyword.get(opts, :snapshot_dir, Rename.default_snapshot_dir())

    entries = Enum.map(ops, fn op -> {op, Safety.classify(op)} end)

    body =
      entries
      |> Enum.group_by(fn {op, _classification} -> table_name(op) end)
      |> Enum.sort_by(fn {name, _entries} -> name end)
      |> Enum.map_join("\n", fn {table, table_entries} ->
        format_table(table, table_entries, verbose?, snapshot_dir)
      end)

    counts = Enum.frequencies_by(entries, fn {_op, {level, _reason}} -> level end)

    body <>
      "\n" <>
      "#{Map.get(counts, :safe, 0)} safe / #{Map.get(counts, :review, 0)} review / #{Map.get(counts, :dangerous, 0)} dangerous\n"
  end

  defp table_name({:add_table, table}), do: table.name
  defp table_name({:drop_table, table}), do: table.name
  defp table_name({_op, table, _entity}), do: table
  defp table_name({_op, table, _entity, _changes}), do: table

  defp format_table(table, entries, verbose?, snapshot_dir) do
    "#{table}:\n" <>
      Enum.map_join(entries, "\n", &format_entry(&1, verbose?, snapshot_dir)) <> "\n"
  end

  defp format_entry({op, {level, reason}}, verbose?, snapshot_dir) do
    line = format_op(op) <> "  [#{label(level)}: #{reason}]"

    if verbose? do
      line <> "\n" <> provenance_line(op, snapshot_dir)
    else
      line
    end
  end

  defp provenance_line({:possible_rename, table, x, _y}, snapshot_dir) do
    case Rename.provenance(table, x.name, snapshot_dir) do
      nil -> "      via: no matching snapshot file under #{snapshot_dir}/#{table}"
      file -> "      via: #{snapshot_dir}/#{table}/#{file}"
    end
  end

  defp provenance_line(_op, _snapshot_dir),
    do: "      via: pg_catalog (Kumi.Actual) vs Ash resource introspection (Kumi.Desired)"

  defp label(:safe), do: "SAFE"
  defp label(:review), do: "REVIEW"
  defp label(:dangerous), do: "DANGEROUS"

  defp format_op({:add_table, table}), do: "  + table #{table.name}"

  defp format_op({:drop_table, table}),
    do: "  - table #{table.name}  (in DB, not in code — drift)"

  defp format_op({:add_column, _table, col}),
    do: "  + column #{col.name} #{col.type}#{not_null(col)}"

  defp format_op({:remove_column, _table, col}),
    do: "  - column #{col.name} #{col.type}  (in DB, not in code — drift)"

  defp format_op({:change_column, _table, col, changes}) do
    "  ~ column #{col.name} (#{format_changes(changes)})"
  end

  defp format_op({:add_fk, _table, fk}),
    do: "  + fk #{fk.column} -> #{fk.references_table}.#{fk.references_column}"

  defp format_op({:remove_fk, _table, fk}),
    do: "  - fk #{fk.column} -> #{fk.references_table}.#{fk.references_column}  (drift)"

  defp format_op({:add_index, _table, idx}),
    do: "  + index #{idx.name} (#{Enum.join(idx.columns, ", ")})#{unique(idx)}"

  defp format_op({:remove_index, _table, idx}),
    do: "  - index #{idx.name}  (drift)"

  defp format_op({:possible_rename, _table, x, y}),
    do: "  ~ possible rename #{x.name} -> #{y.name} (#{x.type})"

  defp format_changes(changes) do
    Enum.map_join(changes, ", ", fn {field, desired, actual} ->
      "#{field}: #{inspect(actual)} -> #{inspect(desired)}"
    end)
  end

  defp not_null(%{nullable: false}), do: " not null"
  defp not_null(_col), do: ""

  defp unique(%{unique: true}), do: " unique"
  defp unique(_idx), do: ""
end

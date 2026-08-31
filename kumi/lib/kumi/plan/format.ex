defmodule Kumi.Plan.Format do
  @moduledoc """
  Renders a `Kumi.Diff` (+ `Kumi.Plan.Rename`) operation list as readable
  +/-/~ text, grouped per table, with each line's `Kumi.Plan.Safety`
  classification and reason, and an overall "N safe / N review / N
  dangerous" summary line.

  With the `:findings` option (a list of `Kumi.Plan.Finding`, from
  `Kumi.Probe` — see `Kumi.Plan.findings`), each finding is rendered as an
  extra indented line under the operation it was probed for.

  With `fix_hints: true` (from `mix kumi.plan --fix-hints`), each operation
  also gets indented `Kumi.Plan.FixHint` remediation lines. Advisory text
  only — classification, summary counts and `--check` exit codes are
  unaffected.
  """

  alias Kumi.Plan.{FixHint, Rename, Safety}

  @spec format([Kumi.Diff.op()], keyword()) :: String.t()
  def format(ops, opts \\ [])

  def format([], opts), do: t(locale(opts), :no_changes) <> "\n"

  def format(ops, opts) do
    verbose? = Keyword.get(opts, :verbose, false)
    hints? = Keyword.get(opts, :fix_hints, false)
    snapshot_dir = Keyword.get(opts, :snapshot_dir, Rename.default_snapshot_dir())
    findings_by_op = opts |> Keyword.get(:findings, []) |> Enum.group_by(& &1.op)
    locale = locale(opts)

    entries = Enum.map(ops, fn op -> {op, Safety.classify(op, locale)} end)

    body =
      entries
      |> Enum.group_by(fn {op, _classification} -> table_name(op) end)
      |> Enum.sort_by(fn {name, _entries} -> name end)
      |> Enum.map_join("\n", fn {table, table_entries} ->
        format_table(table, table_entries, verbose?, hints?, snapshot_dir, findings_by_op, locale)
      end)

    counts = Enum.frequencies_by(entries, fn {_op, {level, _reason}} -> level end)

    summary =
      t(locale, :summary,
        safe: Map.get(counts, :safe, 0),
        review: Map.get(counts, :review, 0),
        dangerous: Map.get(counts, :dangerous, 0)
      )

    body <> "\n" <> summary <> "\n"
  end

  defp locale(opts), do: Keyword.get(opts, :locale, Kumi.Locale.base_locale())

  defp t(locale, key, bindings \\ []),
    do: Kumi.Plan.Locale.translate(locale, key, bindings)

  defp table_name({:add_table, table}), do: table.name
  defp table_name({:drop_table, table}), do: table.name
  defp table_name({_op, table, _entity}), do: table
  defp table_name({_op, table, _entity, _changes}), do: table

  defp format_table(table, entries, verbose?, hints?, snapshot_dir, findings_by_op, locale) do
    "#{table}:\n" <>
      Enum.map_join(
        entries,
        "\n",
        &format_entry(&1, verbose?, hints?, snapshot_dir, findings_by_op, locale)
      ) <>
      "\n"
  end

  defp format_entry({op, {level, reason}}, verbose?, hints?, snapshot_dir, findings_by_op, locale) do
    line = format_op(op, locale) <> "  [#{label(level)}: #{reason}]"

    line =
      if verbose? do
        line <> "\n" <> provenance_line(op, snapshot_dir, locale)
      else
        line
      end

    line =
      findings_by_op
      |> Map.get(op, [])
      |> Enum.map_join("", &("\n" <> finding_line(&1, locale)))
      |> then(&(line <> &1))

    if hints? do
      line <> Enum.map_join(FixHint.lines(op, locale), "", &"\n      #{&1}")
    else
      line
    end
  end

  defp finding_line(
         %Kumi.Plan.Finding{note: note, query_description: query_description},
         locale
       ),
       do: t(locale, :finding, note: note, query: query_description)

  defp provenance_line({:possible_rename, table, x, _y}, snapshot_dir, locale) do
    case Rename.provenance(table, x.name, snapshot_dir) do
      nil -> t(locale, :via_no_snapshot, dir: "#{snapshot_dir}/#{table}")
      file -> t(locale, :via_snapshot, file: "#{snapshot_dir}/#{table}/#{file}")
    end
  end

  defp provenance_line(_op, _snapshot_dir, locale), do: t(locale, :via_catalog)

  defp label(:safe), do: "SAFE"
  defp label(:review), do: "REVIEW"
  defp label(:dangerous), do: "DANGEROUS"

  defp format_op({:add_table, table}, _locale), do: "  + table #{table.name}"

  defp format_op({:drop_table, table}, locale),
    do: "  - table #{table.name}" <> t(locale, :drift_in_db_not_code)

  defp format_op({:add_column, _table, col}, _locale),
    do: "  + column #{col.name} #{col.type}#{not_null(col)}"

  defp format_op({:remove_column, _table, col}, locale),
    do: "  - column #{col.name} #{col.type}" <> t(locale, :drift_in_db_not_code)

  defp format_op({:change_column, _table, col, changes}, _locale) do
    "  ~ column #{col.name} (#{format_changes(changes)})"
  end

  defp format_op({:add_fk, _table, fk}, _locale),
    do: "  + fk #{fk.column} -> #{fk.references_table}.#{fk.references_column}"

  defp format_op({:remove_fk, _table, fk}, locale),
    do:
      "  - fk #{fk.column} -> #{fk.references_table}.#{fk.references_column}" <>
        t(locale, :drift)

  defp format_op({:add_index, _table, idx}, _locale),
    do: "  + index #{idx.name} (#{Enum.join(idx.columns, ", ")})#{unique(idx)}"

  defp format_op({:remove_index, _table, idx}, locale),
    do: "  - index #{idx.name}" <> t(locale, :drift)

  defp format_op({:possible_rename, _table, x, y}, _locale),
    do: "  ~ possible rename #{x.name} -> #{y.name} (#{x.type})"

  defp format_op({:change_primary_key, _table, desired_pk, actual_pk}, _locale),
    do: "  ~ primary key (#{Enum.join(actual_pk, ", ")}) -> (#{Enum.join(desired_pk, ", ")})"

  defp format_op({:change_fk, _table, desired_fk, actual_fk}, _locale),
    do:
      "  ~ fk #{desired_fk.column} #{actual_fk.references_table}.#{actual_fk.references_column} -> " <>
        "#{desired_fk.references_table}.#{desired_fk.references_column}"

  defp format_op({:change_fk_on_delete, _table, desired_fk, actual_fk}, _locale),
    do:
      "  ~ fk #{desired_fk.column} on_delete #{inspect(actual_fk.on_delete)} -> " <>
        "#{inspect(desired_fk.on_delete)}"

  defp format_op({:change_index, _table, desired_idx, actual_idx}, _locale),
    do:
      "  ~ index #{desired_idx.name} (#{Enum.join(actual_idx.columns, ", ")})#{unique(actual_idx)} -> " <>
        "(#{Enum.join(desired_idx.columns, ", ")})#{unique(desired_idx)}"

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

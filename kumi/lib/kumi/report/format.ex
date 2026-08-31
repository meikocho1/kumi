defmodule Kumi.Report.Format do
  @moduledoc """
  Renders a `Kumi.Report` as the human-readable checklist `mix kumi.report`
  prints by default (blueprint §8): one line per step (`✓`/`✗`/`○` +
  detail), the blocking operations when the plan is `:blocked`, and a
  final verdict line.
  """

  alias Kumi.Report.Step

  @spec format(Kumi.Report.t()) :: String.t()
  def format(%Kumi.Report{steps: steps, plan: plan, verdict: verdict}) do
    step_lines = Enum.map_join(steps, "\n", &step_line/1)
    ops = blocked_ops_lines(plan)

    step_lines <> "\n" <> ops <> "\n" <> verdict_line(verdict)
  end

  defp step_line(%Step{name: name, status: status, detail: detail}) do
    "#{icon(status)} #{pad(name)} #{detail}"
  end

  defp icon(:pass), do: "✓"
  defp icon(:fail), do: "✗"
  defp icon(:skipped), do: "○"

  defp pad(name), do: name |> to_string() |> String.pad_trailing(8)

  defp blocked_ops_lines(nil), do: ""

  defp blocked_ops_lines(plan) do
    plan.entries
    |> Enum.filter(fn {_op, level, _reason} -> level in [:review, :dangerous] end)
    |> Enum.map_join("", fn {op, level, reason} ->
      "    - #{describe(op)}  [#{String.upcase(to_string(level))}: #{reason}]\n"
    end)
  end

  defp verdict_line(:ready), do: "\nVerdict: ready — Ready for PR"

  defp verdict_line(:ready_with_migration),
    do: "\nVerdict: ready_with_migration — Ready for PR (apply the SAFE migration)"

  defp verdict_line(:blocked), do: "\nVerdict: blocked — NOT ready, see above"
  defp verdict_line(:failed), do: "\nVerdict: failed — NOT ready, see above"

  @doc "One-line `kind table.column` description of a diff/rename op — shared with `Kumi.Report.Json`."
  @spec describe(Kumi.Diff.op() | Kumi.Plan.Rename.rename_op()) :: String.t()
  def describe({:add_table, table}), do: "add_table #{table.name}"
  def describe({:drop_table, table}), do: "drop_table #{table.name}"
  def describe({:add_column, table, col}), do: "add_column #{table}.#{col.name}"
  def describe({:remove_column, table, col}), do: "remove_column #{table}.#{col.name}"
  def describe({:change_column, table, col, _changes}), do: "change_column #{table}.#{col.name}"
  def describe({:add_fk, table, fk}), do: "add_fk #{table}.#{fk.column}"
  def describe({:remove_fk, table, fk}), do: "remove_fk #{table}.#{fk.column}"
  def describe({:add_index, table, idx}), do: "add_index #{table}.#{idx.name}"
  def describe({:remove_index, table, idx}), do: "remove_index #{table}.#{idx.name}"

  def describe({:possible_rename, table, x, y}),
    do: "possible_rename #{table}.#{x.name}->#{y.name}"

  def describe({:change_primary_key, table, desired_pk, actual_pk}),
    do: "change_primary_key #{table} #{inspect(actual_pk)}->#{inspect(desired_pk)}"

  def describe({:change_fk, table, fk, _actual_fk}), do: "change_fk #{table}.#{fk.column}"

  def describe({:change_fk_on_delete, table, fk, _actual_fk}),
    do: "change_fk_on_delete #{table}.#{fk.column}"

  def describe({:change_index, table, idx, _actual_idx}), do: "change_index #{table}.#{idx.name}"
end

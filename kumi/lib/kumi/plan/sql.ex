defmodule Kumi.Plan.SQL do
  @moduledoc """
  Renders one `Kumi.Diff` operation to the exact SQL that would apply it,
  or `:unsupported` when no single correct SQL statement exists.

  This is the ONE place that SQL text is generated — `Kumi.Plan.FixHint`
  (advisory, print-only) and `Kumi.Apply` (executes SAFE ops, see that
  module's moduledoc) both call this, so hint text and executed SQL can
  never drift apart.

  Renderability is NOT executability: this module renders SQL for
  destructive ops too (`remove_column`, `drop_table`, ...) because
  `FixHint` shows that SQL to a human. Whether an op is safe to run is
  `Kumi.Plan.Safety`'s question, gated again in `Kumi.Apply` — never here.

  `add_table` is always `:unsupported`: a `Kumi.Schema.Table`'s column
  defaults are normalized Ash-side terms (`Kumi.Schema.Default`), not SQL,
  so there is no way to reconstruct a correct `CREATE TABLE` from it.
  """

  alias Kumi.Schema.Table

  @spec render(Kumi.Diff.op() | {:possible_rename, String.t(), term(), term()}) ::
          {:ok, String.t()} | :unsupported

  def render({:add_table, %Table{}}), do: :unsupported

  def render({:add_column, table, col}),
    do: {:ok, "ALTER TABLE #{table} ADD COLUMN #{col.name} #{col.type}#{not_null(col)};"}

  def render({:add_fk, table, fk}) do
    {:ok,
     "ALTER TABLE #{table} ADD CONSTRAINT #{fk.name} FOREIGN KEY (#{fk.column}) " <>
       "REFERENCES #{fk.references_table} (#{fk.references_column});"}
  end

  def render({:add_index, table, idx}) do
    {:ok,
     "CREATE#{if idx.unique, do: " UNIQUE", else: ""} INDEX #{idx.name} " <>
       "ON #{table} (#{Enum.join(idx.columns, ", ")});"}
  end

  def render({:change_column, table, col, changes}) do
    case render_changes(col, changes) do
      :unsupported -> :unsupported
      actions -> {:ok, "ALTER TABLE #{table} #{Enum.join(actions, ", ")};"}
    end
  end

  def render({:drop_table, %Table{} = table}), do: {:ok, "DROP TABLE #{table.name};"}

  def render({:remove_column, table, col}),
    do: {:ok, "ALTER TABLE #{table} DROP COLUMN #{col.name};"}

  def render({:remove_fk, table, fk}),
    do: {:ok, "ALTER TABLE #{table} DROP CONSTRAINT #{fk.name};"}

  def render({:remove_index, _table, idx}), do: {:ok, "DROP INDEX #{idx.name};"}

  def render({:possible_rename, table, x, y}),
    do: {:ok, "ALTER TABLE #{table} RENAME COLUMN #{x.name} TO #{y.name};"}

  # All-or-nothing: a single `:default` or `:datetime_precision` change
  # anywhere in the list means the whole op is :unsupported — applying only
  # the type/nullable part of a multi-change op would leave the rest of the
  # drift silently unrepaired, which is worse than skipping the op.
  defp render_changes(col, changes) do
    Enum.reduce_while(changes, [], fn
      {:type, desired, _actual}, acc ->
        {:cont, ["ALTER COLUMN #{col.name} TYPE #{desired}" | acc]}

      {:nullable, false, _actual}, acc ->
        {:cont, ["ALTER COLUMN #{col.name} SET NOT NULL" | acc]}

      {:nullable, true, _actual}, acc ->
        {:cont, ["ALTER COLUMN #{col.name} DROP NOT NULL" | acc]}

      _unsupported_change, _acc ->
        {:halt, :unsupported}
    end)
    |> case do
      :unsupported -> :unsupported
      actions -> Enum.reverse(actions)
    end
  end

  defp not_null(%{nullable: false}), do: " NOT NULL"
  defp not_null(_col), do: ""
end

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

  Every table/column/constraint/index name is routed through
  `Kumi.Schema.Ident.quote_ident/1` (M1) — this module's output is what
  `Kumi.Apply` executes, so an unquoted reserved word (`order`) or
  mixed-case name (`myColumn`) is not just a cosmetic gap: the former is a
  syntax error that crashes `mix kumi.apply` mid-transaction, and the
  latter is worse — Postgres SILENTLY folds it to `mycolumn`, the write
  commits, and the next plan reports the real `myColumn` as still missing
  AND the folded `mycolumn` as DANGEROUS drift. `Kumi.Probe` already
  quoted every identifier it interpolates for exactly this reason; this
  module (whose SQL is executed, not just read) did not, until now.
  """

  alias Kumi.Schema.{Ident, Table}

  @spec render(Kumi.Diff.op() | {:possible_rename, String.t(), term(), term()}) ::
          {:ok, String.t()} | :unsupported

  def render({:add_table, %Table{}}), do: :unsupported

  def render({:add_column, table, col}) do
    {:ok, "ALTER TABLE #{q(table)} ADD COLUMN #{q(col.name)} #{col.type}#{not_null(col)};"}
  end

  def render({:add_fk, table, fk}) do
    {:ok,
     "ALTER TABLE #{q(table)} ADD CONSTRAINT #{q(fk.name)} FOREIGN KEY (#{q(fk.column)}) " <>
       "REFERENCES #{q(fk.references_table)} (#{q(fk.references_column)});"}
  end

  def render({:add_index, table, idx}) do
    quoted_cols = idx.columns |> Enum.map(&q/1) |> Enum.join(", ")

    {:ok,
     "CREATE#{if idx.unique, do: " UNIQUE", else: ""} INDEX #{q(idx.name)} " <>
       "ON #{q(table)} (#{quoted_cols});"}
  end

  def render({:change_column, table, col, changes}) do
    case render_changes(col, changes) do
      :unsupported -> :unsupported
      actions -> {:ok, "ALTER TABLE #{q(table)} #{Enum.join(actions, ", ")};"}
    end
  end

  def render({:drop_table, %Table{} = table}), do: {:ok, "DROP TABLE #{q(table.name)};"}

  def render({:remove_column, table, col}),
    do: {:ok, "ALTER TABLE #{q(table)} DROP COLUMN #{q(col.name)};"}

  def render({:remove_fk, table, fk}),
    do: {:ok, "ALTER TABLE #{q(table)} DROP CONSTRAINT #{q(fk.name)};"}

  def render({:remove_index, _table, idx}), do: {:ok, "DROP INDEX #{q(idx.name)};"}

  def render({:possible_rename, table, x, y}),
    do: {:ok, "ALTER TABLE #{q(table)} RENAME COLUMN #{q(x.name)} TO #{q(y.name)};"}

  # change_primary_key / change_fk / change_index each need a DROP+CREATE
  # (or DROP CONSTRAINT + ADD CONSTRAINT) pair, not one exact statement —
  # this module's contract (one op -> one statement) can't represent that,
  # so these are deliberately :unsupported. `Kumi.Plan.FixHint` describes
  # the drop/create pair in prose instead of hand-writing SQL for them, and
  # `Kumi.Apply`'s renderability gate (gate 3) rejects them automatically
  # as a result — no DDL for these can ever execute via `mix kumi.apply`.
  def render({:change_primary_key, _table, _desired_pk, _actual_pk}), do: :unsupported
  def render({:change_fk, _table, _desired_fk, _actual_fk}), do: :unsupported
  def render({:change_index, _table, _desired_idx, _actual_idx}), do: :unsupported

  # All-or-nothing: a single `:default` or `:datetime_precision` change
  # anywhere in the list means the whole op is :unsupported — applying only
  # the type/nullable part of a multi-change op would leave the rest of the
  # drift silently unrepaired, which is worse than skipping the op.
  defp render_changes(col, changes) do
    Enum.reduce_while(changes, [], fn
      {:type, desired, _actual}, acc ->
        {:cont, ["ALTER COLUMN #{q(col.name)} TYPE #{desired}" | acc]}

      {:nullable, false, _actual}, acc ->
        {:cont, ["ALTER COLUMN #{q(col.name)} SET NOT NULL" | acc]}

      {:nullable, true, _actual}, acc ->
        {:cont, ["ALTER COLUMN #{q(col.name)} DROP NOT NULL" | acc]}

      _unsupported_change, _acc ->
        {:halt, :unsupported}
    end)
    |> case do
      :unsupported -> :unsupported
      actions -> Enum.reverse(actions)
    end
  end

  defp q(name), do: Ident.quote_ident(name)

  defp not_null(%{nullable: false}), do: " NOT NULL"
  defp not_null(_col), do: ""
end

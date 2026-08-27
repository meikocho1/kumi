defmodule Kumi.Plan.FixHint do
  @moduledoc """
  Advisory remediation lines for each `Kumi.Diff` operation, rendered by
  `Kumi.Plan.Format` when `mix kumi.plan --fix-hints` is passed. Pure and
  print-only — Kumi never executes any of this (the plan stays read-only;
  applying changes is `mix ash.codegen` / `mix kumi.apply` / manual SQL
  territory — see `Kumi.Apply`).

  Two directions need different advice:

    * code-ahead ops (`add_*`, `change_column`) — the normal path is
      `mix ash.codegen`; but if the snapshot already matches the code,
      codegen emits nothing and the DB drifted, so we also show the manual
      SQL where it is a safe one-liner.
    * drift ops (`remove_*`, `drop_table`) — `ash.codegen` cannot see these
      at all (it diffs code vs snapshot, not code vs DB). Keeping the
      DB-side object means adding it to code; removing it is manual SQL.
      The keep option is listed first — the SQL is destructive.

  SQL text itself comes from `Kumi.Plan.SQL` (the one place SQL is
  generated, shared with `Kumi.Apply`) — this module only wraps it with
  the surrounding advisory prose. Where `Kumi.Plan.SQL.render/1` returns
  `:unsupported` (`add_table`, a `change_column` with a default/precision
  change), we fall back to a plain "adjust/recreate manually" line —
  defaults are normalized Ash-side terms, not SQL (see `Kumi.Schema.Column`).
  """

  alias Kumi.Plan.SQL

  @codegen "mix ash.codegen <name> && mix ash_postgres.migrate"

  @spec lines(Kumi.Diff.op()) :: [String.t()]
  def lines({:add_table, table}) do
    [
      "fix: #{@codegen}  (code ahead of DB)",
      "if codegen emits nothing, table #{table.name} was dropped manually — recreate it by hand"
    ]
  end

  def lines({:add_column, _table, _col} = op), do: code_ahead_lines(op)
  def lines({:add_fk, _table, _fk} = op), do: code_ahead_lines(op)
  def lines({:add_index, _table, _idx} = op), do: code_ahead_lines(op)
  def lines({:change_column, _table, _col, _changes} = op), do: code_ahead_lines(op)

  def lines({:drop_table, table}) do
    [
      "fix: to keep it, define it as an Ash resource (ash.codegen cannot see this drift)",
      "to remove it: DROP TABLE #{table.name};"
    ]
  end

  def lines({:remove_column, _table, _col} = op) do
    [
      "fix: to keep it, add the attribute to your Ash resource (ash.codegen cannot see this drift)",
      remove_sql(op)
    ]
  end

  def lines({:remove_fk, _table, _fk} = op) do
    [
      "fix: to keep it, add the relationship to your Ash resource (ash.codegen cannot see this drift)",
      remove_sql(op)
    ]
  end

  def lines({:remove_index, _table, _idx} = op) do
    [
      "fix: to keep it, add the identity/index to your Ash resource (ash.codegen cannot see this drift)",
      remove_sql(op)
    ]
  end

  def lines({:possible_rename, _table, _x, _y} = op) do
    {:ok, sql} = SQL.render(op)

    [
      "fix: if this is a rename, run BEFORE ash.codegen (codegen would emit drop+add and lose data):",
      sql
    ]
  end

  defp code_ahead_lines(op) do
    fallback =
      case SQL.render(op) do
        {:ok, sql} ->
          "if codegen emits nothing, the DB drifted — apply manually: " <> sql

        :unsupported ->
          "if codegen emits nothing, the DB drifted — adjust manually (default/precision changes have no single SQL form)"
      end

    ["fix: #{@codegen}  (code ahead of DB)", fallback]
  end

  defp remove_sql(op) do
    {:ok, sql} = SQL.render(op)
    "to remove it: " <> sql
  end
end

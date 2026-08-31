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
  the surrounding advisory prose, which lives in `Kumi.Plan.Locale` so it
  can be printed in the app's language. The SQL is never translated. Where `Kumi.Plan.SQL.render/1` returns
  `:unsupported` (`add_table`, a `change_column` with a default/precision
  change), we fall back to a plain "adjust/recreate manually" line —
  defaults are normalized Ash-side terms, not SQL (see `Kumi.Schema.Column`).
  """

  alias Kumi.Plan.SQL

  @doc """
  Remediation lines for one operation, in `locale`.

  Advisory prose only — the SQL inside a line comes from
  `Kumi.Plan.SQL` and is never translated, because it is meant to be
  copied into psql.
  """
  @spec lines(Kumi.Diff.op(), Kumi.Locale.locale()) :: [String.t()]
  def lines(op, locale \\ Kumi.Locale.base_locale())

  def lines({:add_table, table}, locale) do
    [
      codegen_line(locale),
      t(locale, :hint_add_table, table: table.name)
    ]
  end

  def lines({:add_column, _table, _col} = op, locale), do: code_ahead_lines(op, locale)
  def lines({:add_fk, _table, _fk} = op, locale), do: code_ahead_lines(op, locale)
  def lines({:add_index, _table, _idx} = op, locale), do: code_ahead_lines(op, locale)

  def lines({:change_column, _table, _col, _changes} = op, locale),
    do: code_ahead_lines(op, locale)

  def lines({:drop_table, _table} = op, locale),
    do: [t(locale, :hint_keep_resource), remove_sql(op, locale)]

  def lines({:remove_column, _table, _col} = op, locale),
    do: [t(locale, :hint_keep_attribute), remove_sql(op, locale)]

  def lines({:remove_fk, _table, _fk} = op, locale),
    do: [t(locale, :hint_keep_relationship), remove_sql(op, locale)]

  def lines({:remove_index, _table, _idx} = op, locale),
    do: [t(locale, :hint_keep_identity), remove_sql(op, locale)]

  def lines({:possible_rename, _table, _x, _y} = op, locale) do
    {:ok, sql} = SQL.render(op)

    [t(locale, :hint_rename_first), sql]
  end

  # No literal SQL here (SQL.render/1 is :unsupported for all four — a
  # DROP+CREATE / DROP+ADD CONSTRAINT pair isn't one exact statement) — see
  # `mix ash.codegen` for the code-ahead direction, and describe the
  # drop/create pair in prose so a human can apply it deliberately.
  def lines({:change_primary_key, _table, desired_pk, actual_pk}, locale) do
    [
      codegen_line(locale),
      t(locale, :hint_primary_key_drift,
        actual: inspect(actual_pk),
        desired: inspect(desired_pk)
      )
    ]
  end

  def lines({:change_fk, _table, desired_fk, actual_fk}, locale) do
    [
      codegen_line(locale),
      t(locale, :hint_fk_drift,
        column: desired_fk.column,
        actual: "#{actual_fk.references_table}.#{actual_fk.references_column}",
        desired: "#{desired_fk.references_table}.#{desired_fk.references_column}",
        constraint: actual_fk.name
      )
    ]
  end

  def lines({:change_fk_on_delete, _table, desired_fk, actual_fk}, locale) do
    [
      codegen_line(locale),
      t(locale, :hint_fk_on_delete_drift,
        column: desired_fk.column,
        actual: inspect(actual_fk.on_delete),
        desired: inspect(desired_fk.on_delete),
        constraint: actual_fk.name
      )
    ]
  end

  def lines({:change_index, _table, desired_idx, actual_idx}, locale) do
    [
      codegen_line(locale),
      t(locale, :hint_index_drift,
        index: desired_idx.name,
        actual_columns: inspect(actual_idx.columns),
        actual_unique: actual_idx.unique,
        desired_columns: inspect(desired_idx.columns),
        desired_unique: desired_idx.unique
      )
    ]
  end

  defp code_ahead_lines(op, locale) do
    fallback =
      case SQL.render(op) do
        {:ok, sql} -> t(locale, :hint_code_ahead_sql, sql: sql)
        :unsupported -> t(locale, :hint_code_ahead_manual)
      end

    [codegen_line(locale), fallback]
  end

  defp remove_sql(op, locale) do
    {:ok, sql} = SQL.render(op)
    t(locale, :hint_remove_sql, sql: sql)
  end

  defp codegen_line(locale),
    do: t(locale, :hint_codegen, codegen: Kumi.Plan.Locale.codegen_command())

  defp t(locale, key, bindings \\ []),
    do: Kumi.Plan.Locale.translate(locale, key, bindings)
end

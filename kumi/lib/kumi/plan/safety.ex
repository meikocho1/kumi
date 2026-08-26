defmodule Kumi.Plan.Safety do
  @moduledoc """
  Classifies one diff (or rename) operation into a safety bucket, using ONE
  consistent rule instead of ad hoc special cases per operation kind:

    * DANGEROUS — the proposal, if applied, deletes data: `drop_table` and
      `remove_column`. By construction, any `remove_column` this module
      sees was NOT recognized as a rename target — `Kumi.Plan.Rename` runs
      BEFORE classification and upgrades rename-shaped pairs to
      `:possible_rename`, so a plain `remove_column` reaching here really
      is "in the DB, not in code, not explained" and applying it is a real
      `DROP COLUMN`. A type change that isn't a known-safe widening is
      also DANGEROUS by default — unknown type pairs fail closed, not open.

    * REVIEW — tightens a constraint, or is a guess rather than a fact:
      NOT NULL tightening (including a new NOT NULL column, which needs a
      default/backfill), UNIQUE index, FK add/remove on an existing table,
      `possible_rename` (a heuristic guess, not a fact), `remove_index`
      (indexes are never hand-authored in code here, so removing one is
      always drift), and a known-safe *widening* type change.

    * SAFE — pure, additive, non-destructive: `add_table`, a nullable
      `add_column`, a non-unique `add_index` (production should still use
      `CREATE INDEX CONCURRENTLY`), and relaxing a column from NOT NULL to
      nullable. `add_fk`/`remove_fk` operations from `Kumi.Diff` only ever
      target an EXISTING table (a brand new table's FKs travel inside its
      single `add_table` op, which is SAFE on its own), so they are always
      classified as "on an existing table" — REVIEW.

  This module never touches the database or the filesystem — it only reads
  the operation tuple already produced by `Kumi.Diff` / `Kumi.Plan.Rename`.
  """

  alias Kumi.Schema.Column

  @type level :: :safe | :review | :dangerous
  @type reason :: String.t()

  # {actual_type, desired_type} pairs that are a safe WIDENING and nothing
  # else. Any pair not listed here is DANGEROUS by default (fail closed).
  @widening_pairs [
    {"varchar", "text"},
    {"int2", "int4"},
    {"int4", "int8"},
    {"float4", "float8"}
  ]

  @spec classify(term()) :: {level(), reason()}
  def classify({:add_table, table}), do: {:safe, "creates new table #{table.name}"}

  def classify({:drop_table, table}),
    do: {:dangerous, "drops table #{table.name} and all its data"}

  def classify({:add_column, _table, %Column{nullable: true} = col}),
    do: {:safe, "adds nullable column #{col.name}"}

  def classify({:add_column, _table, %Column{nullable: false} = col}),
    do: {:review, "adds NOT NULL column #{col.name} — existing rows need a default/backfill"}

  def classify({:remove_column, _table, col}),
    do:
      {:dangerous,
       "drops column #{col.name} — in the DB, not in code, not matched as a rename: data loss"}

  def classify({:add_fk, _table, fk}),
    do: {:review, "adds FK #{fk.column} on an existing table"}

  def classify({:remove_fk, _table, fk}),
    do: {:review, "removes FK #{fk.column} from an existing table"}

  def classify({:add_index, _table, %{unique: true} = idx}),
    do: {:review, "adds UNIQUE index #{idx.name}"}

  def classify({:add_index, _table, idx}),
    do: {:safe, "adds index #{idx.name} — use CREATE INDEX CONCURRENTLY in production"}

  def classify({:remove_index, _table, idx}),
    do: {:review, "removes index #{idx.name} — only ever drift, not requested by code"}

  def classify({:possible_rename, _table, x, y}),
    do:
      {:review,
       "possible rename #{x.name} -> #{y.name} (heuristic guess from snapshot history, verify before applying)"}

  def classify({:change_column, _table, col, changes}) do
    changes
    |> Enum.map(&classify_change(col, &1))
    |> worst()
  end

  defp classify_change(col, {:type, desired, actual}) do
    if {actual, desired} in @widening_pairs do
      {:review, "widens #{col.name} type #{actual} -> #{desired}"}
    else
      {:dangerous, "narrows or changes #{col.name} type #{actual} -> #{desired} (default: unsafe)"}
    end
  end

  defp classify_change(col, {:nullable, false, true}),
    do: {:review, "tightens #{col.name} to NOT NULL — existing NULLs would fail"}

  defp classify_change(col, {:nullable, true, false}),
    do: {:safe, "relaxes #{col.name} to allow NULL"}

  defp classify_change(col, {:default, desired, actual}),
    do: {:safe, "changes #{col.name} default #{inspect(actual)} -> #{inspect(desired)}"}

  defp worst(changes), do: Enum.max_by(changes, fn {level, _reason} -> severity(level) end)

  defp severity(:safe), do: 0
  defp severity(:review), do: 1
  defp severity(:dangerous), do: 2
end

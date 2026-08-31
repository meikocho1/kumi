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
      always drift), a known-safe *widening* type change, and a nil-sided
      `:datetime_precision` change with no accompanying `:type` change to
      explain it (a `Kumi.Desired.PgType` mapping gap — the catch-all fails
      closed here rather than assuming a sibling change exists). Also
      REVIEW: `change_primary_key`, `change_fk` (target table/column
      differs) and `change_index` (columns/uniqueness differ) — none of
      these deletes data outright (so DANGEROUS overstates it) and none is
      a pure addition (so SAFE is wrong); each needs a DROP+CREATE (or
      DROP/ADD CONSTRAINT) pair that only a human should approve, so they
      land in this same "constraint tightening or guess" bucket.

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

  @typedoc """
  A reason before it becomes prose: the string key in
  `Kumi.Plan.Locale` plus the values to interpolate. Classification is a
  function of the operation tuple alone, so the reason is too — which is
  what makes it renderable in any locale instead of only readable in the
  one it was written in.
  """
  @type spec :: {level(), atom(), keyword()}

  # {actual_type, desired_type} pairs that are a safe WIDENING and nothing
  # else. Any pair not listed here is DANGEROUS by default (fail closed).
  @widening_pairs [
    {"varchar", "text"},
    {"int2", "int4"},
    {"int4", "int8"},
    {"float4", "float8"}
  ]

  @doc """
  The safety level and the human reason for one operation.

  `locale` only changes the prose. The level — and therefore
  `mix kumi.plan --check`'s exit code — is identical in every locale, and
  `--json` always renders `:en` so a machine consumer never sees the
  language change under it.
  """
  @spec classify(term(), Kumi.Locale.locale()) :: {level(), reason()}
  def classify(op, locale \\ Kumi.Locale.base_locale()) do
    {level, key, bindings} = spec(op)
    {level, Kumi.Plan.Locale.translate(locale, key, bindings)}
  end

  @doc "The structured form of `classify/2`'s reason — the key and its bindings."
  @spec spec(term()) :: spec()
  def spec({:add_table, table}), do: {:safe, :safety_add_table, table: table.name}

  def spec({:drop_table, table}), do: {:dangerous, :safety_drop_table, table: table.name}

  def spec({:add_column, _table, %Column{nullable: true} = col}),
    do: {:safe, :safety_add_column_nullable, column: col.name}

  def spec({:add_column, _table, %Column{nullable: false} = col}),
    do: {:review, :safety_add_column_not_null, column: col.name}

  def spec({:remove_column, _table, col}),
    do: {:dangerous, :safety_remove_column, column: col.name}

  def spec({:add_fk, _table, fk}), do: {:review, :safety_add_fk, column: fk.column}

  def spec({:remove_fk, _table, fk}), do: {:review, :safety_remove_fk, column: fk.column}

  def spec({:add_index, _table, %{unique: true} = idx}),
    do: {:review, :safety_add_index_unique, index: idx.name}

  def spec({:add_index, _table, idx}), do: {:safe, :safety_add_index, index: idx.name}

  def spec({:remove_index, _table, idx}),
    do: {:review, :safety_remove_index, index: idx.name}

  def spec({:change_primary_key, _table, desired_pk, actual_pk}),
    do:
      {:review, :safety_change_primary_key,
       actual: inspect(actual_pk), desired: inspect(desired_pk)}

  def spec({:change_fk, _table, desired_fk, actual_fk}),
    do:
      {:review, :safety_change_fk,
       column: desired_fk.column,
       actual: "#{actual_fk.references_table}.#{actual_fk.references_column}",
       desired: "#{desired_fk.references_table}.#{desired_fk.references_column}"}

  # Never SAFE, in either direction. The constraint has to be replaced, and
  # both directions change behaviour that matters: dropping `:delete` makes
  # the parent row undeletable, adding it makes rows disappear that used to
  # block the delete.
  def spec({:change_fk_on_delete, _table, desired_fk, actual_fk}),
    do:
      {:review, :safety_change_fk_on_delete,
       column: desired_fk.column,
       actual: inspect(actual_fk.on_delete),
       desired: inspect(desired_fk.on_delete)}

  def spec({:change_index, _table, desired_idx, actual_idx}),
    do:
      {:review, :safety_change_index,
       index: desired_idx.name,
       actual_columns: inspect(actual_idx.columns),
       desired_columns: inspect(desired_idx.columns),
       actual_unique: actual_idx.unique,
       desired_unique: desired_idx.unique}

  def spec({:possible_rename, _table, x, y}),
    do: {:review, :safety_possible_rename, from: x.name, to: y.name}

  def spec({:change_column, _table, col, changes}) do
    changes
    |> Enum.map(&change_spec(col, &1))
    |> worst()
  end

  defp change_spec(col, {:type, desired, actual}) do
    if {actual, desired} in @widening_pairs do
      {:review, :safety_widen_type, column: col.name, actual: actual, desired: desired}
    else
      {:dangerous, :safety_change_type, column: col.name, actual: actual, desired: desired}
    end
  end

  defp change_spec(col, {:nullable, false, true}),
    do: {:review, :safety_tighten_not_null, column: col.name}

  defp change_spec(col, {:nullable, true, false}),
    do: {:safe, :safety_relax_null, column: col.name}

  defp change_spec(col, {:default, desired, actual}),
    do:
      {:safe, :safety_change_default,
       column: col.name, actual: inspect(actual), desired: inspect(desired)}

  # Verified empirically (v0.1.5, F33): `ALTER COLUMN ... TYPE timestamp(N)`
  # between precisions succeeds with an implicit cast in both directions —
  # widening adds no data, narrowing ROUNDS the fractional seconds (not a
  # truncation, not a failure: 12:00:00.900001 -> 12:00:01, not .900000 or
  # an error). So neither direction is DANGEROUS; both are REVIEW because
  # narrowing is a real (if non-failing) loss of stored precision.
  defp change_spec(col, {:datetime_precision, desired, actual})
       when is_integer(desired) and is_integer(actual) and desired > actual,
       do: {:review, :safety_widen_precision, column: col.name, actual: actual, desired: desired}

  defp change_spec(col, {:datetime_precision, desired, actual})
       when is_integer(desired) and is_integer(actual),
       do: {:review, :safety_narrow_precision, column: col.name, actual: actual, desired: desired}

  # One side nil means the column stopped/started being a precision-bearing
  # type entirely. This USUALLY arrives alongside a `:type` change, which
  # would fail closed to DANGEROUS via `worst/1` on its own — but this
  # clause must not assume that. It is the module's only catch-all, so it
  # is the last line of defense for the next `PgType` mapping gap (H4 was
  # exactly this: a `:date` column produced this precision shape with NO
  # accompanying `:type` change, and this clause used to return `:safe`
  # here, silently). Fail closed to REVIEW instead of asserting a sibling
  # change that may not exist.
  defp change_spec(col, {:datetime_precision, desired, actual}),
    do:
      {:review, :safety_change_timestampness,
       column: col.name, actual: inspect(actual), desired: inspect(desired)}

  defp worst(specs), do: Enum.max_by(specs, fn {level, _key, _bindings} -> severity(level) end)

  defp severity(:safe), do: 0
  defp severity(:review), do: 1
  defp severity(:dangerous), do: 2
end

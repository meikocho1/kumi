defmodule Kumi.Plan.Rename do
  @moduledoc """
  Upgrades a `remove_column` + `add_column` pair on the same table into a
  `{:possible_rename, table, old_column, new_column}` hint, using
  AshPostgres resource snapshots (`priv/resource_snapshots/repo/<table>/*.json`)
  as a historical record of "what this table's columns used to be called".

  This validates the blueprint's "snapshot = historical hint, not source of
  truth" model: `Kumi.Desired`/`Kumi.Actual` never read snapshots (they
  describe the CURRENT code and CURRENT database), but a snapshot's
  *history* is exactly the signal needed to tell "column X was dropped and
  column Y was added" apart from "column X was renamed to Y".

  Heuristic (deliberately conservative — this is a HINT for a human to
  confirm, never an automatic rewrite):

    * same table, one `remove_column` (X, present in the DB) and one
      `add_column` (Y, present in the code), with the SAME resolved
      postgres type
    * X's name appears somewhere in that table's snapshot history (it was
      a real column at some point, per Ash's own migration history)
    * Y's name has NEVER appeared in that table's snapshot history (it is
      genuinely new — not a column that existed before, got dropped, and
      is now being re-added under the same name with a coincidentally
      matching type)

  "Snapshot history" here means the union of every column name across every
  snapshot file for that table's directory, not just the newest one — a
  rename could have happened several migrations ago.

  Ambiguity is handled by NOT guessing: when a `remove_column` has more
  than one same-type, not-yet-claimed `add_column` candidate (or vice
  versa), it is left as plain `remove_column`/`add_column`. Matching is
  greedy over the operation list order, so in the rare case where two
  removes could each match the same single add, only the first is
  resolved and the second stays unmatched — a known limitation, not a
  target for this spike. False negatives (a real rename left unflagged)
  are preferred over false positives (a DROP dressed up as a rename).
  """

  alias Kumi.Schema.Column

  @default_snapshot_dir "priv/resource_snapshots/repo"

  @type rename_op :: {:possible_rename, String.t(), Column.t(), Column.t()}

  @spec default_snapshot_dir() :: String.t()
  def default_snapshot_dir, do: @default_snapshot_dir

  @doc "Loads snapshot history from disk, then applies the heuristic. See `resolve/2` for the pure part."
  @spec detect([Kumi.Diff.op()], String.t()) :: [Kumi.Diff.op() | rename_op()]
  def detect(ops, snapshot_dir \\ @default_snapshot_dir) do
    resolve(ops, load_history(snapshot_dir))
  end

  @doc """
  Pure heuristic: `history` maps table name -> MapSet of every column name
  that has ever appeared in that table's snapshot files.
  """
  @spec resolve([Kumi.Diff.op()], %{String.t() => MapSet.t(String.t())}) ::
          [Kumi.Diff.op() | rename_op()]
  def resolve(ops, history) do
    ops
    |> Enum.group_by(&op_table/1)
    |> Enum.flat_map(fn {table, table_ops} ->
      resolve_table(table, table_ops, Map.get(history, table, MapSet.new()))
    end)
  end

  @doc "Reads every snapshot json under `dir`: one column-name-history MapSet per table (subdirectory)."
  @spec load_history(String.t()) :: %{String.t() => MapSet.t(String.t())}
  def load_history(dir \\ @default_snapshot_dir) do
    if File.dir?(dir) do
      dir
      |> File.ls!()
      |> Enum.filter(&File.dir?(Path.join(dir, &1)))
      |> Map.new(fn table -> {table, table_history(Path.join(dir, table))} end)
    else
      %{}
    end
  end

  @doc """
  Verbose-mode provenance: the newest snapshot file (if any) under `dir`
  for `table` that mentions `column_name`. Returns the bare filename, or
  `nil` if none mention it.
  """
  @spec provenance(String.t(), String.t(), String.t()) :: String.t() | nil
  def provenance(table, column_name, dir \\ @default_snapshot_dir) do
    table_dir = Path.join(dir, table)

    if File.dir?(table_dir) do
      table_dir
      |> snapshot_files()
      |> Enum.sort(:desc)
      |> Enum.find(&mentions_column?(Path.join(table_dir, &1), column_name))
    end
  end

  defp table_history(table_dir) do
    table_dir
    |> snapshot_files()
    |> Enum.flat_map(fn file ->
      table_dir |> Path.join(file) |> column_sources()
    end)
    |> MapSet.new()
  end

  defp snapshot_files(dir), do: dir |> File.ls!() |> Enum.filter(&String.ends_with?(&1, ".json"))

  defp column_sources(path) do
    path
    |> File.read!()
    |> Jason.decode!()
    |> Map.get("attributes", [])
    |> Enum.map(&Map.fetch!(&1, "source"))
  end

  defp mentions_column?(path, column_name), do: column_name in column_sources(path)

  defp op_table({:add_table, table}), do: table.name
  defp op_table({:drop_table, table}), do: table.name
  defp op_table({_op, table, _entity}), do: table
  defp op_table({_op, table, _entity, _changes}), do: table

  defp resolve_table(table, ops, seen) do
    removes = for {:remove_column, ^table, col} <- ops, do: col
    adds = for {:add_column, ^table, col} <- ops, do: col

    {renames, used_removes, used_adds} = match_renames(removes, adds, seen)

    kept =
      Enum.reject(ops, fn
        {:remove_column, ^table, col} -> col in used_removes
        {:add_column, ^table, col} -> col in used_adds
        _ -> false
      end)

    kept ++ Enum.map(renames, fn {x, y} -> {:possible_rename, table, x, y} end)
  end

  defp match_renames(removes, adds, seen) do
    Enum.reduce(removes, {[], [], []}, fn remove_col, {renames, used_r, used_a} ->
      candidates =
        adds
        |> Enum.reject(&(&1 in used_a))
        |> Enum.filter(&(&1.type == remove_col.type))

      case candidates do
        [add_col] ->
          if MapSet.member?(seen, remove_col.name) and not MapSet.member?(seen, add_col.name) do
            {[{remove_col, add_col} | renames], [remove_col | used_r], [add_col | used_a]}
          else
            {renames, used_r, used_a}
          end

        _ ->
          {renames, used_r, used_a}
      end
    end)
  end
end

defmodule Kumi.Apply do
  @moduledoc """
  Executes the SAFE, allowlisted, fully-renderable subset of a
  `%Kumi.Plan{}` — the drift-repair half `mix ash.codegen` cannot see (see
  `Mix.Tasks.Kumi.Apply` for the full positioning: codegen moves the DB
  forward when code is ahead of the snapshot; this repairs the DB when it
  has drifted BEHIND what code+snapshot already agree on).

  Four gates, ALL required, decide what actually runs — derived from
  `Kumi.Plan.Safety`'s actual `:safe` clauses, read in full before writing
  this module:

    1. The plan entry says `:safe`. This reads the level stored in the
       entry rather than recomputing it: `Kumi.Plan.build/1` is the only
       thing that builds plan entries, and it takes the level from
       `Kumi.Plan.Safety`.
    2. The op's SHAPE is on the explicit allowlist below — not just its
       tag: a nullable `add_column`, a non-unique `add_index`, or a
       `change_column` whose every change is a NULL-relax
       (`{:nullable, true, false}`). Nothing else, whatever level the
       entry carries. This is a second, independent check so a change to
       `Safety` (or a hand-built entry passed to `run/3`) can't silently
       widen what gets executed here — a tag-level list let any
       renderable `change_column`, `ALTER COLUMN ... TYPE` included,
       through. `add_table` (no `CREATE TABLE` reconstruction) and a
       `change_column` carrying a default change (no SQL form) are safe
       but never executable, so they stop here.
    3. It renders — `Kumi.Plan.SQL.render/1` returns `{:ok, sql}`.
    4. The rendered statement is complete: it carries everything the op
       describes, which `SQL.render/1` itself can't promise, since it
       doesn't know this is destined for execution. `ADD COLUMN name type`
       sets no default and no datetime precision, and names the column
       type by its `udt_name` alone, so a `:safe` `add_column` is skipped
       when its `default` or `datetime_precision` is non-nil or its type
       is not `exact_type?` (`numeric(10,2)`, `vector(1536)`, a generated
       `bigserial`, ...). `Safety.classify/1` only looks at `nullable`,
       so each of those is still `:safe`, and running it would leave
       residual drift (the default) or, worse, a different column than
       `mix ash.codegen` built that no later plan can see (the type).
       Likewise `CREATE INDEX name ON table (columns)` is only run for an `exact?`
       index — one with no `where`, `using`, `include`, expression field
       or other option `Kumi.Schema.Index` can't carry. (Fail-closed here
       also skips one case that would actually round-trip fine — a
       nullable `utc_datetime_usec`, precision 6, matches Postgres's own
       default precision for a new timestamp column — but telling that
       apart from a mismatching case isn't worth the special-casing.)
       Renderable-and-complete is a strictly narrower set than safe.

  An `add_index` that passes all four is still skipped when one of its
  columns is missing and this run won't add it — its `add_column` (or
  `possible_rename`) in the same plan was skipped. Postgres drops an index
  with the column it covers, so the two usually arrive together, and
  `CREATE INDEX` on the missing column would fail and roll back the rest.

  `:review` and `:dangerous` ops are ALWAYS skipped, with a reason, under
  any option — there is no flag that runs them.

  Executable statements run inside ONE `repo.transaction/1`. After commit,
  this re-runs the same introspect-then-diff pipeline `Kumi.plan/3` uses
  (`Kumi.Desired.extract/1` + `Kumi.Actual.introspect/1` + `Kumi.Diff.diff/2`)
  and confirms every executed op is gone from the fresh diff; if any
  remain, that's a silent-failure risk and this raises rather than
  reporting a false "done".

  Explicit args only — no `Mix.env()` / Application config reads (this
  repo's rule: only mix tasks read config/environment). The dev-only guard
  lives in `Mix.Tasks.Kumi.Apply`, not here, so this module stays testable
  under `:test`, which is what `Kumi.ApplyTest` verifies directly.
  """

  alias Kumi.{Actual, Desired, Diff, Plan}
  alias Kumi.Plan.SQL
  alias Kumi.Schema.{Column, Index}

  @type executed_entry :: {term(), String.t()}
  @type skipped_entry :: {term(), String.t()}
  @type verified :: :not_run | :ok
  @type result :: %{
          executed: [executed_entry()],
          skipped: [skipped_entry()],
          verified: verified()
        }

  @doc """
  Executes `plan`'s SAFE+allowlisted+renderable ops against `repo`.

  `opts[:domains]` (required) — the same list of Ash domains used to build
  `plan` — is used only for the post-commit verification re-diff.
  """
  @spec run(module(), Plan.t(), keyword()) :: result()
  def run(repo, %Plan{entries: entries}, opts \\ []) do
    domains = Keyword.fetch!(opts, :domains)

    {to_execute, skipped} = preview(entries)
    executed = if to_execute == [], do: [], else: execute!(repo, to_execute)
    verified = if executed == [], do: :not_run, else: verify!(repo, domains, executed)

    %{executed: executed, skipped: skipped, verified: verified}
  end

  @doc """
  Applies the same gates `run/3` uses, without executing anything —
  `Mix.Tasks.Kumi.Apply` calls this to print its preview so the printed
  "will run" / "skip" lines can never drift from what `run/3` actually does.
  """
  @spec preview([Plan.entry()]) :: {[executed_entry()], [skipped_entry()]}
  def preview(entries) do
    decisions = Enum.map(entries, &gate/1)
    not_added = not_added_columns(decisions)

    {run, skip} =
      decisions
      |> Enum.map(&require_columns(&1, not_added))
      |> Enum.split_with(&match?({:run, _op, _sql}, &1))

    {Enum.map(run, fn {:run, op, sql} -> {op, sql} end),
     Enum.map(skip, fn {:skip, op, reason} -> {op, reason} end)}
  end

  defp gate({op, level, reason}) do
    cond do
      level != :safe ->
        {:skip, op, "not :safe (#{level}): #{reason}"}

      not executable_shape?(op) ->
        {:skip, op,
         "classified :safe but this #{elem(op, 0)} is not on the executable allowlist " <>
           "(a nullable add_column, a non-unique add_index, or a change_column " <>
           "that only drops NOT NULL)"}

      true ->
        case render_for_execution(op) do
          {:ok, sql} -> {:run, op, sql}
          {:unsupported, reason} -> {:skip, op, reason}
        end
    end
  end

  # Columns the database lacks that this run won't add, as {table, name}.
  # An add_index over one of them can't run either (see the moduledoc):
  # CREATE INDEX would raise inside the transaction and roll back every
  # other repair with it.
  defp not_added_columns(decisions) do
    for {:skip, op, _reason} <- decisions,
        column = missing_column(op),
        not is_nil(column),
        into: MapSet.new(),
        do: column
  end

  defp missing_column({:add_column, table, col}), do: {table, col.name}
  defp missing_column({:possible_rename, table, _old, new}), do: {table, new.name}
  defp missing_column(_op), do: nil

  defp require_columns({:run, {:add_index, table, idx} = op, _sql} = decision, not_added) do
    case Enum.find(idx.columns, &MapSet.member?(not_added, {table, &1})) do
      nil ->
        decision

      column ->
        {:skip, op,
         "classified :safe but index #{idx.name} covers column #{column}, which this run " <>
           "does not add — CREATE INDEX would fail and roll back every other repair"}
    end
  end

  defp require_columns(decision, _not_added), do: decision

  # Gate 2. Matches the op's shape, not its tag, and never consults the
  # level: a :safe label on anything else changes nothing here.
  defp executable_shape?({:add_column, _table, %Column{nullable: true}}), do: true
  defp executable_shape?({:add_index, _table, %Index{unique: false}}), do: true

  defp executable_shape?({:change_column, _table, _col, [_ | _] = changes}),
    do: Enum.all?(changes, &match?({:nullable, true, false}, &1))

  defp executable_shape?(_op), do: false

  # Gates 3 and 4. ADD COLUMN carries no default/precision and names the
  # type by its udt_name alone, and CREATE INDEX here carries only a column
  # list — Safety.classify/1 looks at none of that, so it still says :safe;
  # this catches what that check can't. SQL.render/1 stays untouched
  # (renderable != executable is its own contract — FixHint still shows
  # this SQL to a human).
  defp render_for_execution({:add_column, _table, %{default: default}} = op)
       when not is_nil(default) do
    {:unsupported,
     "classified :safe but adds column #{elem(op, 2).name} with a default — " <>
       "ADD COLUMN can't set it, so running this would leave the default unset as residual drift"}
  end

  defp render_for_execution({:add_column, _table, %{datetime_precision: p}} = op)
       when not is_nil(p) do
    {:unsupported,
     "classified :safe but adds column #{elem(op, 2).name} with a fixed datetime precision — " <>
       "ADD COLUMN can't guarantee it, so running this could leave a residual precision mismatch"}
  end

  defp render_for_execution({:add_column, _table, %{exact_type?: false}} = op) do
    {:unsupported,
     "classified :safe but adds column #{elem(op, 2).name} whose type carries modifiers " <>
       "or a sequence (precision/scale/length/dimensions, serial) — " <>
       "ADD COLUMN #{elem(op, 2).type} would drop them and create a different column " <>
       "than mix ash.codegen does"}
  end

  defp render_for_execution({:add_index, _table, %{exact?: false}} = op) do
    {:unsupported,
     "classified :safe but index #{elem(op, 2).name} carries where/using/include/expression " <>
       "options — CREATE INDEX over its columns alone would build a different index"}
  end

  defp render_for_execution(op) do
    case SQL.render(op) do
      {:ok, sql} -> {:ok, sql}
      :unsupported -> {:unsupported, "classified :safe but Kumi.Plan.SQL has no statement for it"}
    end
  end

  defp execute!(repo, to_execute) do
    {:ok, _} =
      repo.transaction(fn ->
        Enum.each(to_execute, fn {_op, sql} -> repo.query!(sql) end)
      end)

    to_execute
  end

  # The raw diff, without `Kumi.Plan.Rename`, on purpose: this only asks
  # whether an executed op is still there, and Rename could rewrite a
  # still-missing column's `add_column` into a `possible_rename` that the
  # `op in new_ops` check below would not recognise.
  defp verify!(repo, domains, executed) do
    new_ops =
      domains
      |> Desired.extract()
      |> Diff.diff(Actual.introspect(repo))

    check_verification!(executed, new_ops)
  end

  # Split out from verify!/3 so the raise path is unit-testable without a
  # real database: exercising it for real would require an executed op
  # that Safety/SQL.render's own gates (the four gates this module's
  # moduledoc lists in full) already prevent from both running AND leaving
  # residual drift — by design, there's no genuine drift scenario left
  # that reaches this check and still fails it.
  @doc false
  @spec check_verification!([executed_entry()], list()) :: :ok
  def check_verification!(executed, new_ops) do
    case Enum.filter(executed, fn {op, _sql} -> op in new_ops end) do
      [] ->
        :ok

      still_present ->
        raise "Kumi.Apply: verification failed — #{length(still_present)} executed op(s) " <>
                "still present in the diff after commit: #{inspect(still_present)}"
    end
  end
end

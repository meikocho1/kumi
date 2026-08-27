defmodule Kumi.Apply do
  @moduledoc """
  Executes the SAFE, allowlisted, fully-renderable subset of a
  `%Kumi.Plan{}` — the drift-repair half `mix ash.codegen` cannot see (see
  `Mix.Tasks.Kumi.Apply` for the full positioning: codegen moves the DB
  forward when code is ahead of the snapshot; this repairs the DB when it
  has drifted BEHIND what code+snapshot already agree on).

  Three gates, ALL required, decide what actually runs — derived from
  `Kumi.Plan.Safety`'s actual `:safe` clauses, read in full before writing
  this module:

    1. `Kumi.Plan.Safety` classified the op `:safe`.
    2. The op's tag is on the explicit allowlist below — `:add_table`,
       `:add_column`, `:add_index`, `:change_column` are the only tags
       `Safety.classify/1` ever assigns `:safe` to (a nullable
       `add_column`; a non-unique `add_index`; a `change_column` whose
       every individual change — NULL-relax and/or default — is itself
       safe; `add_table` unconditionally). This is a second, independent
       check so a future change to `Safety` can't silently widen what
       gets executed here.
    3. It fully renders — `Kumi.Plan.SQL.render/1` returns `{:ok, sql}`,
       AND (a check `SQL.render/1` itself can't make, since it doesn't
       know this is destined for execution) a `:safe` `add_column` whose
       `default` or `datetime_precision` is non-nil is skipped even
       though `SQL.render/1` happily renders `ADD COLUMN name type` for
       it: `Safety.classify/1` only looks at `nullable`, not `default`,
       so a nullable column WITH a default is still classified `:safe` —
       but `ADD COLUMN` carries no default, so running it would leave the
       column back with a residual `change_column` (`:default` unset),
       i.e. a partial repair. (Fail-closed here also skips one case that
       would actually round-trip fine — a nullable `utc_datetime_usec`,
       precision 6, matches Postgres's own default precision for a new
       timestamp column — but telling that apart from a mismatching case
       isn't worth the special-casing.) `add_table` (no `CREATE TABLE`
       reconstruction) and a `change_column` carrying a default change
       (no SQL form; `SQL.render/1`'s all-or-nothing rule also rejects
       one mixed with an otherwise renderable change, since partially
       applying a `:safe`-classified op would leave the rest of its
       drift silently unrepaired) are the other ways this gate closes —
       renderable-and-complete is a strictly narrower set than safe.

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

  @safe_op_tags [:add_table, :add_column, :add_index, :change_column]

  @type executed_entry :: {term(), String.t()}
  @type skipped_entry :: {term(), String.t()}
  @type result :: %{
          executed: [executed_entry()],
          skipped: [skipped_entry()],
          verified: boolean()
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
    verified = executed == [] or verify!(repo, domains, executed)

    %{executed: executed, skipped: skipped, verified: verified}
  end

  @doc """
  Applies the same three gates `run/3` uses, without executing anything —
  `Mix.Tasks.Kumi.Apply` calls this to print its preview so the printed
  "will run" / "skip" lines can never drift from what `run/3` actually does.
  """
  @spec preview([Plan.entry()]) :: {[executed_entry()], [skipped_entry()]}
  def preview(entries) do
    {exec, skip} =
      Enum.reduce(entries, {[], []}, fn {op, level, reason}, {exec, skip} ->
        cond do
          level != :safe ->
            {exec, [{op, "not :safe (#{level}): #{reason}"} | skip]}

          elem(op, 0) not in @safe_op_tags ->
            {exec,
             [
               {op,
                "classified :safe but op tag #{elem(op, 0)} is not on the executable allowlist"}
               | skip
             ]}

          true ->
            case render_for_execution(op) do
              {:ok, sql} -> {[{op, sql} | exec], skip}
              {:unsupported, reason} -> {exec, [{op, reason} | skip]}
            end
        end
      end)

    {Enum.reverse(exec), Enum.reverse(skip)}
  end

  # ADD COLUMN carries no default/precision, so a nullable add_column WITH
  # one would come back missing it — Safety.classify/1 only looks at
  # `nullable`, so it still says :safe here; this catches what that check
  # can't. SQL.render/1 stays untouched (renderable != executable is its
  # own contract — FixHint still shows this SQL to a human).
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

  defp render_for_execution(op) do
    case SQL.render(op) do
      {:ok, sql} ->
        {:ok, sql}

      :unsupported ->
        {:unsupported,
         "classified :safe but not renderable to SQL (e.g. add_table, or a change_column with a default/precision change)"}
    end
  end

  defp execute!(repo, to_execute) do
    {:ok, _} =
      repo.transaction(fn ->
        Enum.each(to_execute, fn {_op, sql} -> repo.query!(sql) end)
      end)

    to_execute
  end

  defp verify!(repo, domains, executed) do
    new_ops =
      domains
      |> Desired.extract()
      |> Diff.diff(Actual.introspect(repo))

    case Enum.filter(executed, fn {op, _sql} -> op in new_ops end) do
      [] ->
        true

      still_present ->
        raise "Kumi.Apply: verification failed — #{length(still_present)} executed op(s) " <>
                "still present in the diff after commit: #{inspect(still_present)}"
    end
  end
end

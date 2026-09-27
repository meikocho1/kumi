defmodule Mix.Tasks.Kumi.Apply do
  @moduledoc """
  Executes the SAFE drift-repair subset of the plan `mix kumi.plan` would
  show — the direction `mix ash.codegen` cannot see.

  `ash.codegen` moves the DB forward when CODE is ahead of the SNAPSHOT.
  It is structurally blind to the other direction: when the live DB has
  drifted BEHIND what code+snapshot already agree on (someone dropped a
  column by hand), codegen generates nothing. `mix kumi.apply` repairs
  exactly that gap — it executes ONLY operations that `Kumi.Plan.Safety`
  classifies `:safe`, whose shape is on an explicit allowlist, and that
  render to exact, complete SQL (see `Kumi.Apply` for the four gates in
  full). Everything else is printed with the reason it was skipped —
  `:review` and `:dangerous` ops never run, under any flag. `mix kumi.plan`
  itself stays 100% read-only; this is a separate, opt-in task. This
  complements `ash.codegen`, never replaces it.

      mix kumi.apply                  # whole-database plan (like `mix kumi.plan`)
      mix kumi.apply --app MyApp.App  # app-scoped plan (like `mix kumi.plan --app`)
      mix kumi.apply --yes            # skip the confirmation prompt

  Dev-only: refuses to run outside `MIX_ENV=dev` (`Kumi.Apply` itself takes no
  Mix/env stance — the guard lives here so the core stays testable under
  `:test`).

  ## Precondition: codegen and migrations are caught up

  The plan cannot tell "the database fell behind code+snapshot" from "the
  code is ahead of the snapshot" — both read as a missing column. The
  second is `ash.codegen`'s job: repairing it here would add the column
  directly, and the migration codegen generates next would then fail on a
  column that already exists. So before building the plan, this task
  refuses to run while

    * a migration in the repo's migrations path has not been run (run
      `mix ash.migrate`), or
    * `mix ash.codegen --check` exits non-zero, i.e. codegen would still
      generate something (run `mix ash.codegen <name>`).

  AshPostgres answers the code-vs-snapshot question itself; Kumi still
  reads snapshots for nothing but rename hints. The refusal is
  deliberately coarse: pending codegen for any resource blocks the whole
  run.
  """
  @shortdoc "Execute the SAFE drift-repair subset of the plan (dev-only)"

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    unless Mix.env() == :dev do
      Mix.raise(
        "mix kumi.apply only runs under MIX_ENV=dev (got #{Mix.env()}) — " <>
          "it executes SQL against a live database, never run it elsewhere"
      )
    end

    Mix.Task.run("app.start")

    {opts, _rest} = OptionParser.parse!(args, strict: [app: :string, yes: :boolean])

    domains = Mix.Tasks.Kumi.Resolve.domains(opts[:app])
    repo = Mix.Tasks.Kumi.Resolve.repo(domains)

    ensure_caught_up!(migration_statuses(repo), fn ->
      System.cmd("mix", ["ash.codegen", "--check"],
        stderr_to_stdout: true,
        env: [{"MIX_ENV", to_string(Mix.env())}]
      )
    end)

    plan = Mix.Tasks.Kumi.Resolve.build_plan(opts[:app], false)

    {to_execute, to_skip} = Kumi.Apply.preview(plan.entries)

    Mix.shell().info(format_preview(to_execute, to_skip))

    cond do
      to_execute == [] ->
        # Nothing ran, so nothing was verified either — say so explicitly
        # rather than letting a reader assume the missing line means "ok".
        Mix.shell().info(
          "nothing to execute — mix kumi.apply is a no-op here (verified: not_run)"
        )

      opts[:yes] || Mix.shell().yes?("Execute #{length(to_execute)} statement(s) above?") ->
        result = Kumi.Apply.run(repo, plan, domains: domains)

        Mix.shell().info(
          "\nexecuted #{length(result.executed)} / skipped #{length(result.skipped)} — " <>
            "verified: #{result.verified}"
        )

      true ->
        Mix.shell().info("aborted — nothing executed")
    end
  end

  # The statuses `mix ash.migrate` acts on: the repo's own
  # `migrations_path` (an `AshPostgres.Repo` callback) or Ecto's default.
  @doc false
  @spec migration_statuses(module()) :: [{:up | :down, integer(), String.t()}]
  def migration_statuses(repo) do
    path = repo.config()[:migrations_path] || Ecto.Migrator.migrations_path(repo)
    Ecto.Migrator.migrations(repo, [path])
  end

  # The moduledoc's precondition. Takes the migration statuses and the
  # codegen check as arguments so both refusals are unit-testable without a
  # dev database or a host project to shell out in.
  @doc false
  @spec ensure_caught_up!(
          [{:up | :down, integer(), String.t()}],
          (-> {String.t(), non_neg_integer()})
        ) :: :ok
  def ensure_caught_up!(migrations, codegen_check) do
    case for({:down, version, name} <- migrations, do: "#{version}_#{name}") do
      [] ->
        :ok

      pending ->
        Mix.raise(
          "mix kumi.apply: #{length(pending)} migration(s) not run yet (#{Enum.join(pending, ", ")}) " <>
            "— run `mix ash.migrate` first. kumi.apply only repairs a database that drifted " <>
            "behind code, snapshot and migrations; adding what a pending migration adds would " <>
            "make that migration fail."
        )
    end

    case codegen_check.() do
      {_output, 0} ->
        :ok

      {output, _exit_code} ->
        Mix.raise(
          "mix kumi.apply: code is ahead of the snapshot (`mix ash.codegen --check` failed) " <>
            "— run `mix ash.codegen <name>` first. kumi.apply only repairs a database that " <>
            "drifted behind code and snapshot; what codegen would generate is codegen's job.\n\n" <>
            output
        )
    end
  end

  defp format_preview(to_execute, to_skip) do
    execute_lines =
      Enum.map(to_execute, fn {op, sql} -> "  WILL RUN: #{inspect(elem(op, 0))} — #{sql}" end)

    skip_lines =
      Enum.map(to_skip, fn {op, reason} -> "  skip: #{inspect(elem(op, 0))} — #{reason}" end)

    Enum.join(execute_lines ++ skip_lines, "\n")
  end
end

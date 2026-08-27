defmodule Mix.Tasks.Kumi.Apply do
  @moduledoc """
  Executes the SAFE drift-repair subset of the plan `mix kumi.plan` would
  show — the direction `mix ash.codegen` cannot see.

  `ash.codegen` moves the DB forward when CODE is ahead of the SNAPSHOT.
  It is structurally blind to the other direction: when the live DB has
  drifted BEHIND what code+snapshot already agree on (someone dropped a
  column by hand), codegen generates nothing. `mix kumi.apply` repairs
  exactly that gap — it executes ONLY operations that `Kumi.Plan.Safety`
  classifies `:safe`, that are on an explicit allowlist, and that render
  to exact SQL (see `Kumi.Apply` for the three gates in full). Everything
  else is printed with the reason it was skipped — `:review` and
  `:dangerous` ops never run, under any flag. `mix kumi.plan` itself stays
  100% read-only; this is a separate, opt-in task. This complements
  `ash.codegen`, never replaces it.

      mix kumi.apply                  # whole-database plan (like `mix kumi.plan`)
      mix kumi.apply --app MyApp.App  # app-scoped plan (like `mix kumi.plan --app`)
      mix kumi.apply --yes            # skip the confirmation prompt

  Dev-only: refuses outside `MIX_ENV=dev` (`Kumi.Apply` itself takes no
  Mix/env stance — the guard lives here so the core stays testable under
  `:test`).
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
    plan = Mix.Tasks.Kumi.Resolve.build_plan(opts[:app], false)

    {to_execute, to_skip} = Kumi.Apply.preview(plan.entries)

    Mix.shell().info(format_preview(to_execute, to_skip))

    if to_execute == [] do
      Mix.shell().info("nothing to execute — mix kumi.apply is a no-op here")
    else
      if opts[:yes] || Mix.shell().yes?("Execute #{length(to_execute)} statement(s) above?") do
        result = Kumi.Apply.run(repo, plan, domains: domains)

        Mix.shell().info(
          "\nexecuted #{length(result.executed)} / skipped #{length(result.skipped)} — " <>
            "verified: #{result.verified}"
        )
      else
        Mix.shell().info("aborted — nothing executed")
      end
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

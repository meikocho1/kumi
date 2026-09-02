defmodule Mix.Tasks.Kumi.Describe do
  @moduledoc """
  Prints the app-level model of a `Kumi.App` as JSON — the machine-readable
  index an AI agent or a CI check reads *before* it touches source, and the
  structured diff a human reads instead of the source (blueprint §8).

      mix kumi.describe                  # app model + plan state
      mix kumi.describe --no-plan        # app model only; no database needed
      mix kumi.describe --app MyApp.App  # when the project has more than one app

  Read-only: it never writes, migrates or generates anything. With
  `--no-plan` it stops at `mix app.config` instead of `app.start`, so it
  runs in a sandbox or a PR check with no Postgres in reach.

  JSON is the only output format — `Kumi.Describe` documents the schema and
  its `schema_version`. `--json` is accepted so the blueprint's spelling
  (`mix kumi.describe --json`) works; it's already the default and changes
  nothing.

  This is an index, not a duplicate of the Ash source: it names the
  resources, and `mix kumi.expand` prints what one compiles to (D1).
  """
  @shortdoc "Print the app-level Kumi model as JSON"

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {opts, _rest} =
      OptionParser.parse!(args, strict: [app: :string, plan: :boolean, json: :boolean])

    plan? = Keyword.get(opts, :plan, true)

    # `--no-plan` has to work with no database in reach, so it stops at
    # `app.config` (compile + load config, no supervision tree) — enough
    # for Spark's compile-time DSL data. `app.start` would boot the host's
    # Repo and log connection errors on every invocation with Postgres down.
    Mix.Task.run(if(plan?, do: "app.start", else: "app.config"))

    app = resolve_app(opts[:app])
    # Same stdout contract as `mix kumi.report --json` — see `Resolve.quietly/1`.
    plan = if plan?, do: Mix.Tasks.Kumi.Resolve.quietly(fn -> Kumi.plan_app(app) end)

    Mix.shell().info(Kumi.Describe.encode(app, plan))
  end

  defp resolve_app(nil), do: Mix.Tasks.Kumi.Resolve.find_app()
  defp resolve_app(name), do: Module.concat([name])
end

defmodule Mix.Tasks.Kumi.Plan do
  @moduledoc """
  Diffs the DESIRED schema (extracted from the host app's Ash resources)
  against the ACTUAL schema (introspected live from PostgreSQL), upgrades
  likely renames via `Kumi.Plan.Rename`, classifies every operation's
  safety via `Kumi.Plan.Safety`, and prints a readable plan.

      mix kumi.plan             # human-readable plan
      mix kumi.plan --check     # + machine-readable summary line first;
                                 exits non-zero if anything needs REVIEW
                                 or is DANGEROUS (0 with no changes)
      mix kumi.plan --verbose   # + per-operation provenance
      mix kumi.plan --probe     # + data-aware findings (reads live data,
                                 opt-in — see `Kumi.Probe`)
      mix kumi.plan --app MyApp.App  # app-scoped plan (see `Kumi.plan_app/2`)
                                 instead of the default whole-database plan

  Without `--app`, this is the convenience layer over `Kumi.plan/3`: it
  reads the host app's `:ash_domains` config (the Spark/Ash convention —
  `Application.get_env(otp_app, :ash_domains)`) and resolves the repo via
  `AshPostgres.DataLayer.Info.repo/1` from the domains' resources
  themselves, rather than requiring separate repo config. All domains must
  share a single repo in this version.

  With `--app`, it's the convenience layer over `Kumi.plan_app/2` instead —
  see that function's moduledoc for the whole-database-vs-app-scoped
  distinction.
  """
  @shortdoc "Show the diff between the Ash-desired schema and the actual Postgres schema"

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _rest} =
      OptionParser.parse!(args,
        strict: [check: :boolean, verbose: :boolean, probe: :boolean, app: :string]
      )

    plan =
      case opts[:app] do
        nil ->
          otp_app = Mix.Project.config()[:app]
          domains = Application.get_env(otp_app, :ash_domains, [])
          repo = resolve_repo(domains)
          Kumi.plan(repo, domains, probe: opts[:probe] || false)

        app_name ->
          app = Module.concat([app_name])
          Kumi.plan_app(app, probe: opts[:probe] || false)
      end

    ops = Enum.map(plan.entries, fn {op, _level, _reason} -> op end)

    if opts[:check], do: Mix.shell().info(Kumi.Plan.summary_line(plan))

    Mix.shell().info(
      Kumi.Plan.Format.format(ops, verbose: opts[:verbose] || false, findings: plan.findings)
    )

    if opts[:check] do
      code = Kumi.Plan.exit_code(plan)
      if code != 0, do: exit({:shutdown, code})
    end
  end

  defp resolve_repo(domains) do
    repos =
      domains
      |> Enum.flat_map(&Ash.Domain.Info.resources/1)
      |> Enum.uniq()
      |> Enum.filter(&(Ash.Resource.Info.data_layer(&1) == AshPostgres.DataLayer))
      |> Enum.map(&AshPostgres.DataLayer.Info.repo/1)
      |> Enum.uniq()

    case repos do
      [repo] ->
        repo

      [] ->
        Mix.raise("mix kumi.plan: no AshPostgres-backed resources found across :ash_domains")

      many ->
        Mix.raise(
          "mix kumi.plan: found multiple repos across :ash_domains (#{inspect(many)}) — " <>
            "v0.1 supports a single repo only"
        )
    end
  end
end

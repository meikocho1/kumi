defmodule Kumi do
  @moduledoc """
  Public API. Builds a `Kumi.Plan` for a given repo and list of Ash domains:
  extracts the DESIRED schema from the domains' resources, introspects the
  ACTUAL schema live from the repo's database, upgrades likely renames via
  `Kumi.Plan.Rename`, and classifies every operation's safety via
  `Kumi.Plan.Safety`.

  Takes explicit arguments only — no library code here reads Application
  config. `mix kumi.plan` (see `Mix.Tasks.Kumi.Plan`) is the convenience
  layer that resolves a host app's repo/domains and calls this.
  """

  alias Kumi.{Actual, Desired, Diff, Plan}
  alias Kumi.Plan.Rename

  @doc """
  Builds a `%Kumi.Plan{}` diffing `domains`' desired schema against `repo`'s
  actual schema.

  Options:
    * `:snapshot_dir` — directory of AshPostgres resource snapshots used for
      rename detection (default: `Kumi.Plan.Rename.default_snapshot_dir/0`,
      i.e. `priv/resource_snapshots/repo` relative to the current working
      directory).
    * `:probe` — run `Kumi.Probe` against `repo` and attach the results as
      `plan.findings` (default `false`). Opt-in because, unlike every other
      option here, it reads live application data instead of just schema
      metadata — see `Kumi.Probe`'s moduledoc and blueprint §3.4.
  """
  @spec plan(module(), [module()], keyword()) :: Plan.t()
  def plan(repo, domains, opts \\ []) do
    snapshot_dir = Keyword.get(opts, :snapshot_dir, Rename.default_snapshot_dir())
    probe? = Keyword.get(opts, :probe, false)

    plan =
      domains
      |> Desired.extract()
      |> Diff.diff(Actual.introspect(repo))
      |> Rename.detect(snapshot_dir)
      |> Plan.build()

    if probe? do
      %{plan | findings: Kumi.Probe.run(repo, plan)}
    else
      plan
    end
  end

  @doc """
  Builds a `%Kumi.Plan{}` for a `Kumi.App` module: derives its resources
  (`Kumi.App.Info.resources/1`), groups them by Ash domain
  (`Ash.Resource.Info.domain/1`), and delegates to the same pipeline as
  `plan/3` (repo resolved via `AshPostgres.DataLayer.Info.repo/1`).

  **Scoping rule** — `plan/3` diffs the whole database against *all* given
  domains (whole-app view); `plan_app/2` diffs only the tables owned by the
  app's declared resources (app-scoped view). A table that exists in the
  database but isn't backing one of the app's resources — e.g. another
  domain's tables sharing the same repo — is out of scope and is silently
  ignored, never reported as drift (never shows up as `:drop_table`). This
  matters because an app is expected to declare a subset of a host
  application's resources (blueprint §3): `mix kumi.plan` stays the
  whole-database safety net, `plan_app/2` answers "does the database match
  *this app's* resources" only.

  Accepts the same options as `plan/3` (`:snapshot_dir`, `:probe`).
  """
  @spec plan_app(module(), keyword()) :: Plan.t()
  def plan_app(app, opts \\ []) do
    resources = Kumi.App.Info.resources(app)
    repo = resolve_repo(resources)
    domains = resources |> Enum.map(&Ash.Resource.Info.domain/1) |> Enum.uniq()
    scoped_tables = MapSet.new(resources, &AshPostgres.DataLayer.Info.table/1)

    snapshot_dir = Keyword.get(opts, :snapshot_dir, Rename.default_snapshot_dir())
    probe? = Keyword.get(opts, :probe, false)

    actual =
      repo
      |> Actual.introspect()
      |> Enum.filter(&MapSet.member?(scoped_tables, &1.name))

    plan =
      domains
      |> Desired.extract()
      |> Enum.filter(&MapSet.member?(scoped_tables, &1.name))
      |> Diff.diff(actual)
      |> Rename.detect(snapshot_dir)
      |> Plan.build()

    if probe? do
      %{plan | findings: Kumi.Probe.run(repo, plan)}
    else
      plan
    end
  end

  defp resolve_repo(resources) do
    repos =
      resources
      |> Enum.filter(&(Ash.Resource.Info.data_layer(&1) == AshPostgres.DataLayer))
      |> Enum.map(&AshPostgres.DataLayer.Info.repo/1)
      |> Enum.uniq()

    case repos do
      [repo] ->
        repo

      [] ->
        raise ArgumentError,
              "Kumi.plan_app: no AshPostgres-backed resources found among #{inspect(resources)}"

      many ->
        raise ArgumentError,
              "Kumi.plan_app: found multiple repos across the app's resources (#{inspect(many)}) — " <>
                "v0.2 supports a single repo only"
    end
  end
end

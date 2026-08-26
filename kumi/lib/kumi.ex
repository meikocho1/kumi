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
end

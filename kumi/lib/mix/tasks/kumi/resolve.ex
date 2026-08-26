defmodule Mix.Tasks.Kumi.Resolve do
  @moduledoc """
  Shared CLI-level plan resolution for `mix kumi.plan` and
  `mix kumi.report`: turns `--app` (or the host app's `:ash_domains`
  config — the default whole-database view) into a `%Kumi.Plan{}` via
  `Kumi.plan/3` / `Kumi.plan_app/2`.

  Not part of the public library API — `Kumi.plan/3` itself takes an
  explicit repo/domains and never reads Application config; this module
  is the one place that convenience-resolution logic lives, so the two
  mix tasks that need it can't drift apart.
  """

  @spec build_plan(String.t() | nil, boolean()) :: Kumi.Plan.t()
  def build_plan(app_name, probe?)

  def build_plan(nil, probe?) do
    otp_app = Mix.Project.config()[:app]
    domains = Application.get_env(otp_app, :ash_domains, [])
    repo = resolve_repo(domains)
    Kumi.plan(repo, domains, probe: probe?)
  end

  def build_plan(app_name, probe?) do
    app = Module.concat([app_name])
    Kumi.plan_app(app, probe: probe?)
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
        Mix.raise("mix kumi: no AshPostgres-backed resources found across :ash_domains")

      many ->
        Mix.raise(
          "mix kumi: found multiple repos across :ash_domains (#{inspect(many)}) — " <>
            "v0.1 supports a single repo only"
        )
    end
  end
end

defmodule Mix.Tasks.Kumi.Resolve do
  @moduledoc """
  Shared CLI-level plan resolution for `mix kumi.plan` and
  `mix kumi.report`: turns `--app` (or the host app's `:ash_domains`
  config — the default whole-database view) into a `%Kumi.Plan{}` via
  `Kumi.plan/3` / `Kumi.plan_app/2`.

  Not part of the public library API — `Kumi.plan/3` itself takes an
  explicit repo/domains and never reads Application config; this module
  is the one place where convenience-resolution logic lives, so the two
  mix tasks that need it can't drift apart.
  """

  @doc """
  The locale to print in: an explicit `--locale` wins, then the app's own
  `app do locale ... end`, then `:en`.

  With no `--app`, the app is *found* rather than named — `locale :ja` is
  declared once and the guide calls that the whole switch, so requiring
  `--app` on every invocation just to be answered in Japanese would make
  it two switches. See `app_locale/1` for what "found" means.

  Only the prose is affected — `Kumi.Plan.summary_line/1`, exit codes and
  `--json` are identical in every locale. An unknown `--locale` fails the
  task rather than quietly printing English: the person who typed it is
  the person who needs to know.
  """
  @spec locale(String.t() | nil, String.t() | nil) :: Kumi.Locale.locale()
  def locale(nil, nil), do: app_locale(host_modules())

  def locale(nil, app_name),
    do: app_name |> List.wrap() |> Module.concat() |> Kumi.App.Info.locale()

  def locale(requested, _app_name) do
    locale = String.to_atom(requested)

    unless Kumi.Locale.supported?(locale) do
      Mix.raise(
        "mix kumi: unknown --locale #{inspect(requested)} — available: " <>
          inspect(Kumi.Locale.locales())
      )
    end

    locale
  end

  @doc """
  The declared locale of the single `Kumi.App` among `modules`, else `:en`.

  Exactly one app is the normal shape, and it is the only shape that
  answers the question: with none there is nothing to read, and with
  several there is no way to know which one speaks for this repository.
  Both of those stay in the base locale, because printing the wrong
  language confidently is worse than printing English — and `--locale`
  is there for anyone who needs to say so explicitly.
  """
  @spec app_locale([module()]) :: Kumi.Locale.locale()
  def app_locale(modules) do
    case Enum.filter(modules, &kumi_app?/1) do
      [app] -> Kumi.App.Info.locale(app)
      _none_or_several -> Kumi.Locale.base_locale()
    end
  end

  @doc """
  The single `Kumi.App` in the host project, for a task that needs one and
  wasn't given `--app`.

  Unlike `app_locale/1`, none and several are errors rather than a quiet
  fallback: a locale has a safe default to fall back *to*, an app to
  describe does not.
  """
  @spec find_app() :: module()
  def find_app do
    case Enum.filter(host_modules(), &kumi_app?/1) do
      [app] ->
        app

      [] ->
        Mix.raise("mix kumi: no Kumi.App found in this project — pass --app MyApp.App")

      many ->
        Mix.raise(
          "mix kumi: found #{length(many)} Kumi.App modules (#{inspect(many)}) — " <>
            "pass --app to say which one"
        )
    end
  end

  defp host_modules do
    otp_app = Mix.Project.config()[:app]
    Application.spec(otp_app, :modules) || []
  end

  # `spark_is/0` is what `use Spark.Dsl` leaves behind, so this
  # distinguishes a `Kumi.App` from an `Ash.Resource` (which also answers
  # it) without loading a module list and guessing from names.
  defp kumi_app?(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :spark_is, 0) and
      module.spark_is() == Kumi.App
  end

  @doc """
  Runs `fun` with the host's Logger silenced below `:warning`, restoring
  the previous level afterwards.

  `Kumi.Actual`'s introspection issues several raw Ecto queries; under a
  host app's dev logger config (commonly `:debug`) those print
  `[debug] QUERY ...` lines straight to stdout, ahead of the caller's own
  output — which corrupts the "one JSON object on stdout" contract that
  `mix kumi.report --json` and `mix kumi.describe` both make. Found
  running against spike0_crm; see the friction log.
  """
  @spec quietly((-> result)) :: result when result: term()
  def quietly(fun) do
    previous_level = Logger.level()
    Logger.configure(level: :warning)

    try do
      fun.()
    after
      Logger.configure(level: previous_level)
    end
  end

  @spec build_plan(String.t() | nil, boolean()) :: Kumi.Plan.t()
  def build_plan(app_name, probe?)

  def build_plan(nil, probe?) do
    domains = domains(nil)
    Kumi.plan(repo(domains), domains, probe: probe?)
  end

  def build_plan(app_name, probe?) do
    app = Module.concat([app_name])
    Kumi.plan_app(app, probe: probe?)
  end

  @doc """
  Resolves the list of Ash domains for `--app` (or, given `nil`, the host
  app's `:ash_domains` config — same rule `build_plan/2` uses). Exposed
  separately (not just folded into `build_plan/2`) because `mix kumi.apply`
  needs the domains themselves, not just the finished plan — see
  `Kumi.Apply.run/3`'s `:domains` option.
  """
  @spec domains(String.t() | nil) :: [module()]
  def domains(nil) do
    otp_app = Mix.Project.config()[:app]
    Application.get_env(otp_app, :ash_domains, [])
  end

  def domains(app_name) do
    app_name
    |> List.wrap()
    |> Module.concat()
    |> Kumi.App.Info.resources()
    |> Enum.map(&Ash.Resource.Info.domain/1)
    |> Enum.uniq()
  end

  @doc "Resolves the single repo shared across `domains` — see `build_plan/2`."
  @spec repo([module()]) :: module()
  def repo(domains), do: resolve_repo(domains)

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

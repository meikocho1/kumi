defmodule Kumi.App.Verifiers.ValidateUniqueNames do
  @moduledoc """
  Rejects duplicate `resource` entries, duplicate `:name`s across
  `workflow`/`dashboard` entries (each checked independently — a workflow
  and a dashboard may share a name, they live in separate namespaces),
  duplicate entries in `admin.navigation`, and duplicate metric names
  within a single `dashboard`.
  """
  use Spark.Dsl.Verifier

  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  def verify(dsl_state) do
    module = Verifier.get_persisted(dsl_state, :module)

    resources = dsl_state |> Verifier.get_entities([:resources]) |> Enum.map(& &1.resource)
    workflows = dsl_state |> Verifier.get_entities([:workflows]) |> Enum.map(& &1.name)
    dashboards = dsl_state |> Verifier.get_entities([:dashboards])
    navigation = Verifier.get_option(dsl_state, [:admin], :navigation) || []

    with :ok <- check_unique(module, [:resources], "resource", resources),
         :ok <- check_unique(module, [:workflows], "workflow", workflows),
         :ok <- check_unique(module, [:dashboards], "dashboard", Enum.map(dashboards, & &1.name)),
         :ok <- check_unique(module, [:admin, :navigation], "navigation entry", navigation) do
      check_unique_metrics(module, dashboards)
    end
  end

  defp check_unique_metrics(module, dashboards) do
    Enum.find_value(dashboards, :ok, fn dashboard ->
      metric_names = Enum.map(dashboard.metrics, & &1.name)

      case check_unique(
             module,
             [:dashboards, :dashboard, dashboard.name],
             "metric",
             metric_names
           ) do
        :ok -> nil
        error -> error
      end
    end)
  end

  defp check_unique(module, path, label, items) do
    case items -- Enum.uniq(items) do
      [] ->
        :ok

      duplicates ->
        {:error,
         DslError.exception(
           module: module,
           path: path,
           message:
             "duplicate #{label}(s): #{duplicates |> Enum.uniq() |> Enum.map_join(", ", &inspect/1)}"
         )}
    end
  end
end

defmodule Kumi.App.Verifiers.ValidateDashboardMetrics do
  @moduledoc """
  Every `dashboard` must declare at least one metric, and each metric's
  `resource` must be one of the app's declared resources, with `field`
  required only for `kind: :sum` (and forbidden for `kind: :count`).
  """
  use Spark.Dsl.Verifier

  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  def verify(dsl_state) do
    module = Verifier.get_persisted(dsl_state, :module)
    dashboards = Verifier.get_entities(dsl_state, [:dashboards])

    with :ok <- check_non_empty(dashboards, module) do
      declared_resources =
        dsl_state |> Verifier.get_entities([:resources]) |> Enum.map(& &1.resource)

      dashboards
      |> Enum.flat_map(fn dashboard -> Enum.map(dashboard.metrics, &{dashboard, &1}) end)
      |> Enum.find_value(:ok, fn {dashboard, metric} ->
        case check_metric(metric, dashboard, declared_resources, module) do
          :ok -> nil
          error -> error
        end
      end)
    end
  end

  defp check_non_empty(dashboards, module) do
    dashboards
    |> Enum.find(&(&1.metrics == []))
    |> case do
      nil ->
        :ok

      dashboard ->
        {:error,
         DslError.exception(
           module: module,
           path: [:dashboards, :dashboard, dashboard.name],
           message: """
           dashboard #{inspect(dashboard.name)} has no metrics.

           Add at least one: `metric :deal_count, resource: MyApp.Deal`.
           """
         )}
    end
  end

  defp check_metric(metric, dashboard, declared_resources, module) do
    cond do
      metric.resource not in declared_resources ->
        {:error,
         DslError.exception(
           module: module,
           path: [:dashboards, :dashboard, dashboard.name],
           message: """
           metric #{inspect(metric.name)} reads #{inspect(metric.resource)}, which is not \
           declared in this app's `resources do ... end`.

           Add `resource #{inspect(metric.resource)}` there first.
           """
         )}

      metric.kind == :sum and
          (is_nil(metric.field) or
             is_nil(Ash.Resource.Info.attribute(metric.resource, metric.field))) ->
        {:error,
         DslError.exception(
           module: module,
           path: [:dashboards, :dashboard, dashboard.name],
           message: """
           metric #{inspect(metric.name)} has kind: :sum but field #{inspect(metric.field)} \
           does not exist on #{inspect(metric.resource)}.

           `kind: :sum` requires `field:` naming an existing attribute on the resource.
           """
         )}

      metric.kind == :count and not is_nil(metric.field) ->
        {:error,
         DslError.exception(
           module: module,
           path: [:dashboards, :dashboard, dashboard.name],
           message: """
           metric #{inspect(metric.name)} has kind: :count but also sets field: #{inspect(metric.field)}.

           `field:` is only meaningful for `kind: :sum` — remove it, or switch to `kind: :sum`.
           """
         )}

      true ->
        :ok
    end
  end
end

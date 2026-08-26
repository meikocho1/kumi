defmodule Kumi.App.Verifiers.ValidateDashboardMetrics do
  @moduledoc "Every `dashboard` must declare at least one metric."
  use Spark.Dsl.Verifier

  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  def verify(dsl_state) do
    module = Verifier.get_persisted(dsl_state, :module)

    dsl_state
    |> Verifier.get_entities([:dashboards])
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

           Add at least one: `metric :pipeline_value`.
           """
         )}
    end
  end
end

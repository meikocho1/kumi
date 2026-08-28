defmodule Kumi.App.Verifiers.ValidateDashboardMetrics do
  @moduledoc """
  Every `dashboard` must declare at least one metric, and each metric's
  `resource` must be one of the app's declared resources, with `field`
  required only for `kind: :sum` (and forbidden for `kind: :count`) — and,
  for `kind: :sum`, `field` must name a numeric attribute (integer, float,
  or decimal). Ash's own aggregate machinery doesn't enforce that: a
  `:sum` over a `:string` attribute compiles and only blows up `Ash.sum/3`
  at request time, taking down the whole admin dashboard LiveView.
  """
  use Spark.Dsl.Verifier

  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  # Ash's own aggregate machinery (Ash.Query.Aggregate.kind_to_type/3) does
  # NOT restrict :sum to numeric attribute types — it just echoes the
  # attribute's type straight through, so `Ash.sum/3` on a :string
  # attribute compiles fine and only fails at the SQL layer. These are the
  # builtin Ash short names (see Ash.Type.Registry.builtin_short_names/0)
  # whose storage_type/1 is an actual numeric Postgres type SUM() accepts —
  # confirmed by reading each type module: Ash.Type.Integer (:integer),
  # Ash.Type.Float (:float), Ash.Type.Decimal (:decimal/numeric). Every
  # other builtin (:duration -> :duration, :range -> :range, etc.) has a
  # non-numeric storage_type and is deliberately excluded.
  @numeric_types [Ash.Type.Integer, Ash.Type.Float, Ash.Type.Decimal]

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

      metric.kind == :sum and not numeric_field?(metric.resource, metric.field) ->
        attribute_type = Ash.Resource.Info.attribute(metric.resource, metric.field).type

        {:error,
         DslError.exception(
           module: module,
           path: [:dashboards, :dashboard, dashboard.name],
           message: """
           metric #{inspect(metric.name)} has kind: :sum but field #{inspect(metric.field)} \
           on #{inspect(metric.resource)} is #{inspect(attribute_type)}, not a numeric type.

           `kind: :sum` requires `field:` naming an integer, float, or decimal attribute — \
           summing #{inspect(attribute_type)} would compile here and only fail at request \
           time, inside the admin dashboard.
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

  defp numeric_field?(resource, field) do
    resource
    |> Ash.Resource.Info.attribute(field)
    |> Map.fetch!(:type)
    |> Ash.Type.get_type()
    |> then(&(&1 in @numeric_types))
  end
end

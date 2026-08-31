defmodule Kumi.App.Verifiers.ValidateLabels do
  @moduledoc """
  Every key in `admin do labels %{...} end` must name something this app
  actually declares, and every value must be a string.

  A label map is the one place in the App DSL where a typo is completely
  invisible at runtime: an unmatched key simply never gets looked up, so
  the screen keeps showing the derived English label and nothing anywhere
  says why. Same reasoning as `ValidateNavigation` — a reference into the
  app's own declarations gets checked at compile time.

  Accepted keys:

    * a declared resource module, a declared workflow name, or a declared
      dashboard name — labels the whole term
    * `{resource, field}` where `field` is a public attribute or a public
      relationship of that resource
    * `{workflow, stage}` where `stage` is one of that workflow's stages
    * `{dashboard, metric}` where `metric` is one of that dashboard's
      metrics
  """
  use Spark.Dsl.Verifier

  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  def verify(dsl_state) do
    labels = Verifier.get_option(dsl_state, [:admin], :labels) || %{}
    module = Verifier.get_persisted(dsl_state, :module)

    cond do
      not is_map(labels) ->
        {:error,
         DslError.exception(
           module: module,
           path: [:admin, :labels],
           message: """
           `admin.labels` must be a map of term => label, got: #{inspect(labels)}
           """
         )}

      labels == %{} ->
        :ok

      true ->
        declared = declared(dsl_state)

        Enum.find_value(labels, :ok, fn {key, value} ->
          case check(key, value, declared, module) do
            :ok -> nil
            error -> error
          end
        end)
    end
  end

  defp declared(dsl_state) do
    %{
      resources: dsl_state |> Verifier.get_entities([:resources]) |> Enum.map(& &1.resource),
      workflows: Verifier.get_entities(dsl_state, [:workflows]),
      dashboards: Verifier.get_entities(dsl_state, [:dashboards])
    }
  end

  defp check(key, value, _declared, module) when not is_binary(value) do
    error(module, key, """
    its label is #{inspect(value)}, which is not a string.

    Labels are free-form display text: `#{inspect(key)} => "アカウント"`.
    """)
  end

  defp check({scope, key}, _value, declared, module) do
    cond do
      scope in declared.resources -> check_resource_field(scope, key, module)
      workflow = find(declared.workflows, scope) -> check_stage(workflow, key, module)
      dashboard = find(declared.dashboards, scope) -> check_metric(dashboard, key, module)
      true -> unknown_scope(module, scope, declared)
    end
  end

  defp check(key, _value, declared, module) do
    known? =
      key in declared.resources or find(declared.workflows, key) != nil or
        find(declared.dashboards, key) != nil

    if known?, do: :ok, else: unknown_scope(module, key, declared)
  end

  defp check_resource_field(resource, field, module) do
    names =
      Enum.map(Ash.Resource.Info.public_attributes(resource), & &1.name) ++
        Enum.map(Ash.Resource.Info.public_relationships(resource), & &1.name)

    if field in names do
      :ok
    else
      error(module, {resource, field}, """
      #{inspect(resource)} has no public attribute or relationship named \
      #{inspect(field)}.

      Available: #{inspect(Enum.sort(names))}
      """)
    end
  end

  defp check_stage(workflow, stage, module) do
    if stage in workflow.stages do
      :ok
    else
      error(module, {workflow.name, stage}, """
      workflow #{inspect(workflow.name)} has no stage #{inspect(stage)}.

      Declared stages: #{inspect(workflow.stages)}
      """)
    end
  end

  defp check_metric(dashboard, metric, module) do
    names = Enum.map(dashboard.metrics, & &1.name)

    if metric in names do
      :ok
    else
      error(module, {dashboard.name, metric}, """
      dashboard #{inspect(dashboard.name)} has no metric #{inspect(metric)}.

      Declared metrics: #{inspect(names)}
      """)
    end
  end

  defp find(entities, name), do: Enum.find(entities, &(&1.name == name))

  defp unknown_scope(module, key, declared) do
    error(module, key, """
    it does not name a declared resource, workflow or dashboard.

    Resources: #{inspect(declared.resources)}
    Workflows: #{inspect(Enum.map(declared.workflows, & &1.name))}
    Dashboards: #{inspect(Enum.map(declared.dashboards, & &1.name))}
    """)
  end

  defp error(module, key, detail) do
    {:error,
     DslError.exception(
       module: module,
       path: [:admin, :labels],
       message: "`admin.labels` key #{inspect(key)}: " <> detail
     )}
  end
end

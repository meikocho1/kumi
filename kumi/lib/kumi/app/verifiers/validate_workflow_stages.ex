defmodule Kumi.App.Verifiers.ValidateWorkflowStages do
  @moduledoc """
  Every `workflow` must declare at least one stage, its `resource` must be
  one of the app's declared resources, `field` must be a real *public*
  attribute on that resource (Ash's `filter_input` rejects private
  attributes at runtime, so this is caught here instead), and — when the
  field has a `one_of` constraint — every stage must be a member of it.
  """
  use Spark.Dsl.Verifier

  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  def verify(dsl_state) do
    module = Verifier.get_persisted(dsl_state, :module)
    workflows = Verifier.get_entities(dsl_state, [:workflows])

    with :ok <- check_non_empty(workflows, module) do
      declared_resources =
        dsl_state |> Verifier.get_entities([:resources]) |> Enum.map(& &1.resource)

      Enum.find_value(workflows, :ok, fn workflow ->
        case check_workflow(workflow, declared_resources, module) do
          :ok -> nil
          error -> error
        end
      end)
    end
  end

  defp check_non_empty(workflows, module) do
    workflows
    |> Enum.find(&(&1.stages == []))
    |> case do
      nil ->
        :ok

      workflow ->
        {:error,
         DslError.exception(
           module: module,
           path: [:workflows, :workflow, workflow.name],
           message: """
           workflow #{inspect(workflow.name)} has no stages.

           Add at least one: `stages [:lead, :won]`.
           """
         )}
    end
  end

  defp check_workflow(workflow, declared_resources, module) do
    cond do
      workflow.resource not in declared_resources ->
        {:error,
         DslError.exception(
           module: module,
           path: [:workflows, :workflow, workflow.name],
           message: """
           workflow #{inspect(workflow.name)} reads #{inspect(workflow.resource)}, which is not \
           declared in this app's `resources do ... end`.

           Add `resource #{inspect(workflow.resource)}` there first.
           """
         )}

      is_nil(Ash.Resource.Info.attribute(workflow.resource, workflow.field)) ->
        {:error,
         DslError.exception(
           module: module,
           path: [:workflows, :workflow, workflow.name],
           message: """
           workflow #{inspect(workflow.name)} has field #{inspect(workflow.field)}, which does \
           not exist on #{inspect(workflow.resource)}.
           """
         )}

      not Ash.Resource.Info.attribute(workflow.resource, workflow.field).public? ->
        {:error,
         DslError.exception(
           module: module,
           path: [:workflows, :workflow, workflow.name],
           message: """
           workflow #{inspect(workflow.name)} field #{inspect(workflow.field)} on \
           #{inspect(workflow.resource)} is private.

           The admin dashboard reads workflow stages via `Ash.Query.filter_input/2`, which only \
           accepts public attributes. Mark the attribute `public? true`.
           """
         )}

      (one_of =
         Ash.Resource.Info.attribute(workflow.resource, workflow.field).constraints[:one_of]) &&
          workflow.stages -- one_of != [] ->
        {:error,
         DslError.exception(
           module: module,
           path: [:workflows, :workflow, workflow.name],
           message: """
           workflow #{inspect(workflow.name)} declares stages #{inspect(workflow.stages -- one_of)} \
           that are not in #{inspect(workflow.field)}'s `one_of` constraint (#{inspect(one_of)}).
           """
         )}

      true ->
        :ok
    end
  end
end

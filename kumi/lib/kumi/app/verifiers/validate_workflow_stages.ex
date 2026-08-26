defmodule Kumi.App.Verifiers.ValidateWorkflowStages do
  @moduledoc "Every `workflow` must declare at least one stage."
  use Spark.Dsl.Verifier

  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  def verify(dsl_state) do
    module = Verifier.get_persisted(dsl_state, :module)

    dsl_state
    |> Verifier.get_entities([:workflows])
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
end

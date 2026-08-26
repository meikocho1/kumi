defmodule Kumi.App.Verifiers.ValidateResources do
  @moduledoc """
  Every module listed under `resources do ... end` must be a real
  `Ash.Resource` — Kumi.App declares intent about resources, it does not
  define them (blueprint §3.1).
  """
  use Spark.Dsl.Verifier

  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  def verify(dsl_state) do
    module = Verifier.get_persisted(dsl_state, :module)

    dsl_state
    |> Verifier.get_entities([:resources])
    |> Enum.find(&(not ash_resource?(&1.resource)))
    |> case do
      nil ->
        :ok

      %{resource: bad} ->
        {:error,
         DslError.exception(
           module: module,
           path: [:resources, :resource],
           message: """
           #{inspect(bad)} is listed under `resources` but is not an Ash.Resource.

           Kumi.App only declares which resources belong to the app — the
           resource itself must be defined with `use Ash.Resource`.
           """
         )}
    end
  end

  defp ash_resource?(module) do
    Code.ensure_loaded?(module) and Ash.Resource.Info.resource?(module)
  end
end

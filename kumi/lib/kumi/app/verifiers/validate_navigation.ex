defmodule Kumi.App.Verifiers.ValidateNavigation do
  @moduledoc """
  Every module listed in `admin do navigation [...] end` must also be
  declared in `resources do ... end` — navigation can only point at
  resources the app actually owns.
  """
  use Spark.Dsl.Verifier

  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  def verify(dsl_state) do
    module = Verifier.get_persisted(dsl_state, :module)
    declared = dsl_state |> Verifier.get_entities([:resources]) |> MapSet.new(& &1.resource)
    navigation = Verifier.get_option(dsl_state, [:admin], :navigation) || []

    case Enum.find(navigation, &(not MapSet.member?(declared, &1))) do
      nil ->
        :ok

      bad ->
        {:error,
         DslError.exception(
           module: module,
           path: [:admin, :navigation],
           message: """
           #{inspect(bad)} is listed in `admin.navigation` but is not declared \
           under `resources`.

           Add `resource #{inspect(bad)}` to the `resources` block, or remove \
           it from `navigation`.
           """
         )}
    end
  end
end

defmodule Kumi.App.Verifiers.ValidateAppName do
  @moduledoc """
  Every `Kumi.App` must declare `app do name :your_app end`.

  Spark's `schema: [name: [required: true, ...]]` on the `:app` section
  (see `Kumi.App.Dsl`) only gets validated when the section is actually
  present in the DSL body — Spark 2.7.2's `Spark.Dsl.Section` has no
  section-level `required?` flag to force the block itself to exist, so
  omitting `app do ... end` entirely compiles clean and leaves
  `Kumi.App.Info.name/1` returning `nil`, silently breaking the guarantee
  the schema documents. This verifier closes that gap explicitly.
  """
  use Spark.Dsl.Verifier

  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  def verify(dsl_state) do
    module = Verifier.get_persisted(dsl_state, :module)

    case Verifier.get_option(dsl_state, [:app], :name) do
      nil ->
        {:error,
         DslError.exception(
           module: module,
           path: [:app, :name],
           message: """
           this app has no `name`.

           Add an `app do ... end` block naming it:

               app do
                 name :my_app
               end
           """
         )}

      _name ->
        :ok
    end
  end
end

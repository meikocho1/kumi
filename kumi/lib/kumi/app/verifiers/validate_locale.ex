defmodule Kumi.App.Verifiers.ValidateLocale do
  @moduledoc """
  `app do locale ... end` must name a locale Kumi ships strings for.

  Falling back silently would mean a typo (`locale :jp`) produces a
  perfectly working English admin, and the person who typed it goes
  looking for the bug in their own code.
  """
  use Spark.Dsl.Verifier

  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  def verify(dsl_state) do
    locale = Verifier.get_option(dsl_state, [:app], :locale) || Kumi.Locale.base_locale()

    if Kumi.Locale.supported?(locale) do
      :ok
    else
      {:error,
       DslError.exception(
         module: Verifier.get_persisted(dsl_state, :module),
         path: [:app, :locale],
         message: """
         #{inspect(locale)} is not a locale Kumi has strings for.

         Available: #{inspect(Kumi.Locale.locales())}
         """
       )}
    end
  end
end

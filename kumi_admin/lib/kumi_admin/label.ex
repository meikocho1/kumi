defmodule KumiAdmin.Label do
  @moduledoc """
  Naive nav-label derivation from a resource module — last module segment,
  pluralized with a dumb English heuristic. No i18n, no configuration:
  good enough for a sidebar link, not a copywriting engine.
  """

  @doc """
  `MyApp.Crm.Account` -> `"Accounts"`, `MyApp.Crm.Deal` -> `"Deals"`,
  `MyApp.Crm.Company` -> `"Companies"`.
  """
  @spec plural(module()) :: String.t()
  def plural(resource) do
    resource |> Module.split() |> List.last() |> pluralize()
  end

  defp pluralize(word) do
    cond do
      String.match?(word, ~r/[^aeiou]y$/i) ->
        String.slice(word, 0..-2//1) <> "ies"

      String.match?(word, ~r/(s|x|z|ch|sh)$/i) ->
        word <> "es"

      true ->
        word <> "s"
    end
  end
end

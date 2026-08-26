defmodule Kumi.App.Info do
  @moduledoc """
  Introspection for `Kumi.App` modules — reads back exactly what was
  declared in the DSL, nothing more (blueprint §3's "explainable magic").
  """

  alias Kumi.App.Dsl
  alias Spark.Dsl.Extension

  @doc "The app's machine-readable name, e.g. `:crm`."
  @spec name(module()) :: atom()
  def name(app), do: Extension.get_opt(app, [:app], :name)

  @doc "The app's human-readable title, or `nil` if not set."
  @spec title(module()) :: String.t() | nil
  def title(app), do: Extension.get_opt(app, [:app], :title)

  @doc "The Ash resource modules declared in `resources do ... end`."
  @spec resources(module()) :: [module()]
  def resources(app) do
    app |> Extension.get_entities([:resources]) |> Enum.map(& &1.resource)
  end

  @doc "The resource modules listed in `admin do navigation [...] end`."
  @spec navigation(module()) :: [module()]
  def navigation(app), do: Extension.get_opt(app, [:admin], :navigation, [])

  @doc "The `workflow :name do ... end` entries."
  @spec workflows(module()) :: [Dsl.Workflow.t()]
  def workflows(app), do: Extension.get_entities(app, [:workflows])

  @doc "The `dashboard :name do ... end` entries."
  @spec dashboards(module()) :: [Dsl.Dashboard.t()]
  def dashboards(app), do: Extension.get_entities(app, [:dashboards])
end

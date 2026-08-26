defmodule KumiAdmin.Slug do
  @moduledoc """
  URL-safe resource slugs for the `/:resource` and `/:resource/:id` routes.
  Deliberately dumb: last module segment, downcased/underscored — no
  configuration, no collision handling beyond what that gives you for free.
  """

  @doc """
  The slug for a resource module, e.g. `MyApp.Crm.Account` -> `"account"`.
  """
  @spec for_resource(module()) :: String.t()
  def for_resource(resource) do
    resource |> Module.split() |> List.last() |> Macro.underscore()
  end

  @doc """
  Finds the resource module in `app`'s declared resources whose slug
  matches `slug`, or `nil` if none match.
  """
  @spec resolve(module(), String.t()) :: module() | nil
  def resolve(app, slug) do
    Enum.find(Kumi.App.Info.resources(app), &(for_resource(&1) == slug))
  end
end

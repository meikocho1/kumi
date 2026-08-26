defmodule KumiAdmin.Columns do
  @moduledoc """
  Column selection for the generic resource table — the first `N` public
  attributes, in declaration order (which puts `id` first for every
  `uuid_primary_key`-based resource). No config, no priority scoring:
  `Ash.Resource.Info.public_attributes/1` already gives us the order a
  resource author chose.
  """

  @max_columns 6

  @doc "Attribute names to render as table columns, capped at #{@max_columns}."
  @spec for_resource(module()) :: [atom()]
  def for_resource(resource) do
    resource
    |> Ash.Resource.Info.public_attributes()
    |> Enum.map(& &1.name)
    |> Enum.take(@max_columns)
  end
end

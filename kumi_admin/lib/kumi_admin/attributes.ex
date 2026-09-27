defmodule KumiAdmin.Attributes do
  @moduledoc """
  The two `Ash.Resource.Info` derivations every screen in kumi_admin needs:
  which attributes may be shown at all, and which of them are a
  `belongs_to`'s foreign key.

  Both answers already exist in the resource — this module just stops
  kumi_admin from guessing at them (friction log P04/P05).
  """

  @doc """
  Public attributes minus the ones Ash marks `sensitive? true`.

  Every attribute list in kumi_admin (columns, detail page, record
  labels, search, forms) goes through here, so a `sensitive?` attribute
  is never rendered, never pre-filled and never searched, and the form
  drops it from whatever the browser posts back. That is the admin
  narrowing its own UI, not authorization: the action's `accept` list and
  its policies remain the write boundary. Consequence worth knowing: a
  *required* sensitive attribute can't be filled in from the admin at
  all — set it from the host application's own UI or from `iex`.
  """
  @spec visible(module()) :: [Ash.Resource.Attribute.t()]
  def visible(resource) do
    resource
    |> Ash.Resource.Info.public_attributes()
    |> Enum.reject(& &1.sensitive?)
  end

  @doc """
  Public `belongs_to` relationships keyed by the attribute that backs
  them (`:account` → keyed under `:account_id`).
  """
  @spec belongs_to_by_source_attribute(module()) :: %{
          atom() => Ash.Resource.Relationships.BelongsTo.t()
        }
  def belongs_to_by_source_attribute(resource) do
    resource
    |> Ash.Resource.Info.public_relationships()
    |> Enum.filter(&(&1.type == :belongs_to))
    |> Map.new(&{&1.source_attribute, &1})
  end

  @doc """
  Attribute names that back a public `belongs_to` — the only string
  columns `KumiAdmin.Format.cell/3` is allowed to truncate.
  """
  @spec foreign_keys(module()) :: [atom()]
  def foreign_keys(resource), do: resource |> belongs_to_by_source_attribute() |> Map.keys()
end

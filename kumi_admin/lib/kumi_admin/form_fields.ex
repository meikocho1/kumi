defmodule KumiAdmin.FormFields do
  @moduledoc """
  Pure derivation of "what fields go on this resource's create/update form,
  and what widget renders each one". No LiveView, no `Ash.read` — only
  `Ash.Resource.Info`, so this is safe to unit test against a bare
  resource module (see `KumiAdmin.Test.Widget`/`KumiAdmin.Test.Contact`).

  Field list = the intersection of the action's (already-normalized by
  Ash at compile time) `accept` list and `Ash.Resource.Info.public_attributes/1`,
  kept in attribute declaration order. A `belongs_to`'s generated foreign
  key attribute (e.g. `:account_id`) is detected via
  `Ash.Resource.Info.public_relationships/1` and rendered as a `:belongs_to`
  select instead of falling through to its raw `:uuid` type.
  """

  @text_like_names ~r/body|description|notes?|content|comment/i

  @type widget ::
          :text
          | :textarea
          | :number
          | :checkbox
          | :date
          | :datetime_local
          | {:select, [atom()]}
          | {:belongs_to, Ash.Resource.Relationships.BelongsTo.t()}

  @type field :: %{attribute: Ash.Resource.Attribute.t(), widget: widget()}

  @doc "Fields for `resource`'s primary `:create` or `:update` action."
  @spec for_action(module(), :create | :update) :: [field()]
  def for_action(resource, type) when type in [:create, :update] do
    action = Ash.Resource.Info.primary_action!(resource, type)
    accepted = MapSet.new(action.accept)
    belongs_to = belongs_to_by_source_attribute(resource)

    resource
    |> Ash.Resource.Info.public_attributes()
    |> Enum.filter(&MapSet.member?(accepted, &1.name))
    |> Enum.map(fn attribute ->
      %{attribute: attribute, widget: widget(attribute, belongs_to[attribute.name])}
    end)
  end

  defp belongs_to_by_source_attribute(resource) do
    resource
    |> Ash.Resource.Info.public_relationships()
    |> Enum.filter(&(&1.type == :belongs_to))
    |> Map.new(&{&1.source_attribute, &1})
  end

  @doc """
  The input widget for a single attribute, given the `belongs_to`
  relationship it backs (`nil` if it's a plain attribute).
  """
  @spec widget(Ash.Resource.Attribute.t(), Ash.Resource.Relationships.BelongsTo.t() | nil) ::
          widget()
  def widget(_attribute, relationship) when not is_nil(relationship), do: {:belongs_to, relationship}

  def widget(%{type: Ash.Type.Boolean}, nil), do: :checkbox
  def widget(%{type: t}, nil) when t in [Ash.Type.Integer], do: :number
  def widget(%{type: t}, nil) when t in [Ash.Type.Decimal, Ash.Type.Float], do: :number
  def widget(%{type: Ash.Type.Date}, nil), do: :date

  def widget(%{type: t}, nil)
      when t in [Ash.Type.UtcDatetime, Ash.Type.UtcDatetimeUsec, Ash.Type.NaiveDatetime, Ash.Type.DateTime],
      do: :datetime_local

  def widget(%{type: Ash.Type.Atom, constraints: constraints}, nil) do
    case Keyword.get(constraints || [], :one_of) do
      options when is_list(options) and options != [] -> {:select, options}
      _ -> :text
    end
  end

  def widget(%{type: t} = attribute, nil) when t in [Ash.Type.String, Ash.Type.CiString] do
    if long_text?(attribute), do: :textarea, else: :text
  end

  def widget(_attribute, nil), do: :text

  defp long_text?(attribute) do
    is_nil(Keyword.get(attribute.constraints || [], :max_length)) and
      Regex.match?(@text_like_names, to_string(attribute.name))
  end
end

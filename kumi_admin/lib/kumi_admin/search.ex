defmodule KumiAdmin.Search do
  @moduledoc """
  Case-insensitive "contains" search across a resource's string-typed
  public, non-sensitive attributes, OR'd together via Ash's keyword filter syntax
  (`Ash.Query.filter_input/2`, which — unlike `Ash.Query.filter/2` — takes
  plain runtime data, not a macro-time expression, so the field list can
  be built dynamically: `[or: [[name: [contains: term]], [email: [contains: term]]]]`).

  Wrapping the search term in `Ash.CiString` (instead of hand-downcasing
  both sides) is what makes `contains/2` case-insensitive — see
  `Ash.Query.Function.Contains`'s `[:string, :ci_string]` argument
  signature.
  """

  @doc "Public attribute names of string-ish types, in declaration order."
  @spec searchable_fields(module()) :: [atom()]
  def searchable_fields(resource) do
    resource
    |> KumiAdmin.Attributes.visible()
    |> Enum.filter(&(&1.type in [Ash.Type.String, Ash.Type.CiString]))
    |> Enum.map(& &1.name)
  end

  @doc """
  Applies a case-insensitive OR-across-`fields` `contains` filter to
  `query`. Returns `query` unchanged when `fields` or `term` is blank.
  """
  @spec apply(Ash.Query.t(), [atom()], String.t() | nil) :: Ash.Query.t()
  def apply(query, _fields, term) when term in [nil, ""], do: query
  def apply(query, [], _term), do: query

  def apply(query, fields, term) do
    condition = [or: Enum.map(fields, &{&1, [contains: Ash.CiString.new(term)]})]
    Ash.Query.filter_input(query, condition)
  end
end

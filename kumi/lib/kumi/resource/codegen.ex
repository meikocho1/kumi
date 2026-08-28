defmodule Kumi.Resource.Codegen do
  @moduledoc """
  Pure function: `Kumi.Resource.FieldSpec.t()` list + `use Kumi.Resource`
  opts → the Ash resource source text. This is the single source of truth
  for the shorthand's expansion — both `Kumi.Resource.fields/1` (what
  actually gets compiled) and `mix kumi.expand` (what gets printed) call
  this same function, so they can never drift apart.
  """

  alias Kumi.Resource.FieldSpec

  # Deliberately simple — "reasonable", not RFC 5322-exhaustive. Good enough
  # to catch "not-an-email" while accepting ordinary addresses.
  @email_regex_source "~r/^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$/"

  # Mirrors the fixed attributes/actions `generate/3`'s template always
  # emits (`uuid_primary_key :id`, `timestamps()`, the default action set)
  # — kept alongside `emitted_members/1` since that's the only other place
  # that needs to know the same fixed list.
  @default_attribute_names [:id, :inserted_at, :updated_at]
  @default_action_names [:read, :destroy, :create, :update]

  @typedoc "Names of attributes/relationships/actions the generated source declares."
  @type emitted_members :: %{
          attributes: [atom()],
          relationships: [atom()],
          actions: [atom()]
        }

  @doc """
  The attribute/relationship/action names `generate/3` actually emits for
  these field specs. Used by `Kumi.Resource`'s `@after_verify` check (H1
  fix, blueprint §0 D1) to catch plain Ash DSL sections (`attributes do
  ... end`, a second `relationships do ... end`, `calculations`,
  `aggregates`, `identities`) declared alongside `fields do ... end` —
  those compile into the resource but `mix kumi.expand` would never print
  them, silently breaking "expand always prints exactly what compiles".
  """
  @spec emitted_members([FieldSpec.t()]) :: emitted_members()
  def emitted_members(field_specs) do
    field_names = for %FieldSpec{kind: :field, name: name} <- field_specs, do: name

    # `belongs_to :name, Dest` implicitly generates a `:name_id` foreign
    # key *attribute* (Ash's default `source_attribute`, see
    # `Ash.Resource.Relationships.BelongsTo`) — that attribute is still
    # something `fields do ... end` generated, just indirectly, so it must
    # be counted as expected, not flagged as extra.
    belongs_to_fk_names =
      for %FieldSpec{kind: :belongs_to, name: name} <- field_specs, do: :"#{name}_id"

    relationship_names =
      for %FieldSpec{kind: kind, name: name} <- field_specs, kind in [:belongs_to, :has_many] do
        name
      end

    %{
      attributes: @default_attribute_names ++ field_names ++ belongs_to_fk_names,
      relationships: relationship_names,
      actions: @default_action_names
    }
  end

  @spec generate(module(), keyword(), [FieldSpec.t()]) :: String.t()
  def generate(module, opts, field_specs) do
    domain = Keyword.fetch!(opts, :domain)
    repo = Keyword.fetch!(opts, :repo)
    table = Keyword.fetch!(opts, :table)

    attributes = Enum.filter(field_specs, &(&1.kind == :field))
    belongs_tos = Enum.filter(field_specs, &(&1.kind == :belongs_to))
    has_manys = Enum.filter(field_specs, &(&1.kind == :has_many))

    """
    defmodule #{inspect(module)} do
      use Ash.Resource,
        domain: #{inspect(domain)},
        data_layer: AshPostgres.DataLayer

      postgres do
        table #{inspect(table)}
        repo #{inspect(repo)}
      end

      actions do
        defaults [:read, :destroy, create: :*, update: :*]
      end

      attributes do
        uuid_primary_key :id

        #{Enum.map_join(attributes, "\n\n", &attribute_source/1)}

        timestamps()
      end
      #{relationships_block(belongs_tos, has_manys)}
    end
    """
    |> Code.format_string!()
    |> IO.iodata_to_binary()
    |> Kernel.<>("\n")
  end

  defp attribute_source(%FieldSpec{name: name, type: type, opts: opts}) do
    ash_type = ash_type_for(type)

    lines =
      [
        if(Keyword.get(opts, :required, false), do: "allow_nil? false"),
        "public? true",
        if(default = Keyword.get(opts, :default), do: "default #{inspect(default)}"),
        constraint_line(type, opts)
      ]
      |> Enum.filter(& &1)

    """
    attribute #{inspect(name)}, #{inspect(ash_type)} do
      #{Enum.join(lines, "\n")}
    end
    """
  end

  defp ash_type_for(:string), do: :string
  # Ash has no distinct "long text" type — :text is sugar for :string.
  defp ash_type_for(:text), do: :string
  defp ash_type_for(:integer), do: :integer
  defp ash_type_for(:decimal), do: :decimal
  defp ash_type_for(:boolean), do: :boolean
  defp ash_type_for(:date), do: :date
  defp ash_type_for(:datetime), do: :utc_datetime_usec
  defp ash_type_for(:email), do: :string
  defp ash_type_for(:select), do: :atom

  defp ash_type_for(other) do
    raise ArgumentError, "Kumi.Resource: unknown field type #{inspect(other)}"
  end

  defp constraint_line(:select, opts) do
    options =
      Keyword.get(opts, :options) ||
        raise ArgumentError, "Kumi.Resource: :select field requires `options:`"

    "constraints one_of: #{inspect(options)}"
  end

  defp constraint_line(:email, _opts), do: "constraints match: #{@email_regex_source}"
  defp constraint_line(_type, _opts), do: nil

  defp relationships_block([], []), do: ""

  defp relationships_block(belongs_tos, has_manys) do
    """

    relationships do
      #{Enum.map_join(belongs_tos, "\n\n", &belongs_to_source/1)}
      #{Enum.map_join(has_manys, "\n\n", &has_many_source/1)}
    end
    """
  end

  defp belongs_to_source(%FieldSpec{name: name, type: dest, opts: opts}) do
    lines =
      [
        if(Keyword.get(opts, :required, false), do: "allow_nil? false"),
        "public? true"
      ]
      |> Enum.filter(& &1)

    """
    belongs_to #{inspect(name)}, #{inspect(dest)} do
      #{Enum.join(lines, "\n")}
    end
    """
  end

  defp has_many_source(%FieldSpec{name: name, type: dest}) do
    "has_many #{inspect(name)}, #{inspect(dest)}"
  end
end

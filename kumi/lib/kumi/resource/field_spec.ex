defmodule Kumi.Resource.FieldSpec do
  @moduledoc """
  Plain data extracted from a `Kumi.Resource`'s `fields do ... end` block.
  This is the single source of truth `Kumi.Resource.Codegen` compiles from
  — no other code should walk the raw DSL AST.
  """

  @enforce_keys [:kind, :name, :type]
  defstruct [:kind, :name, :type, opts: []]

  @type kind :: :field | :belongs_to | :has_many
  @type t :: %__MODULE__{
          kind: kind(),
          name: atom(),
          type: atom() | module(),
          opts: keyword()
        }

  @doc """
  Parses a `fields do ... end` block's AST into a list of `t()`, resolving
  `belongs_to`/`has_many` destination aliases against `env` (so `alias`ed
  short names inside the calling module work, not just fully-qualified
  ones).
  """
  @spec parse(Macro.t(), Macro.Env.t()) :: [t()]
  def parse(nil, _env), do: []
  def parse({:__block__, _, exprs}, env), do: Enum.map(exprs, &parse_expr(&1, env))
  def parse(expr, env), do: [parse_expr(expr, env)]

  defp parse_expr({:field, _, [name, :image]}, _env) when is_atom(name) do
    raise ArgumentError, image_missing_to_message(name)
  end

  defp parse_expr({:field, _, [name, :image, opts]}, env)
       when is_atom(name) and is_list(opts) do
    case Keyword.fetch(opts, :to) do
      :error ->
        raise ArgumentError, image_missing_to_message(name)

      {:ok, dest_ast} ->
        dest = resolve_module(dest_ast, env)
        validate_attachment_target!(name, dest)
        %__MODULE__{kind: :belongs_to, name: name, type: dest, opts: []}
    end
  end

  defp parse_expr({:field, _, [name, type]}, _env)
       when is_atom(name) and is_atom(type) do
    %__MODULE__{kind: :field, name: name, type: type, opts: []}
  end

  defp parse_expr({:field, _, [name, type, opts]}, _env)
       when is_atom(name) and is_atom(type) and is_list(opts) do
    %__MODULE__{kind: :field, name: name, type: type, opts: opts}
  end

  defp parse_expr({:belongs_to, _, [name, dest]}, env) when is_atom(name) do
    %__MODULE__{kind: :belongs_to, name: name, type: resolve_module(dest, env), opts: []}
  end

  defp parse_expr({:has_many, _, [name, dest]}, env) when is_atom(name) do
    %__MODULE__{kind: :has_many, name: name, type: resolve_module(dest, env), opts: []}
  end

  defp parse_expr(other, _env) do
    raise ArgumentError,
          "Kumi.Resource: unrecognized field declaration inside `fields do ... end`: " <>
            Macro.to_string(other)
  end

  defp resolve_module(ast, env) do
    case Macro.expand(ast, env) do
      mod when is_atom(mod) ->
        mod

      other ->
        raise ArgumentError,
              "Kumi.Resource: expected a module reference, got: " <> Macro.to_string(other)
    end
  end

  defp validate_attachment_target!(name, module) do
    with {:module, _} <- Code.ensure_compiled(module),
         true <- Ash.Resource.Info.resource?(module) do
      :ok
    else
      _ -> raise ArgumentError, image_bad_target_message(name, module)
    end
  end

  defp image_missing_to_message(name) do
    """
    Kumi.Resource: `field #{inspect(name)}, :image` requires a `to:` target naming \
    the Ash resource that stores the uploaded file's metadata, e.g.:

        field #{inspect(name)}, :image, to: MyApp.Core.Attachment

    Run `mix kumi_storage.install` to generate an Attachment resource.
    """
  end

  defp image_bad_target_message(name, module) do
    """
    Kumi.Resource: `field #{inspect(name)}, :image, to: #{inspect(module)}` — \
    #{inspect(module)} does not exist or is not an Ash resource.

    Run `mix kumi_storage.install` to generate an Attachment resource, or point \
    `to:` at an existing Ash resource.
    """
  end
end

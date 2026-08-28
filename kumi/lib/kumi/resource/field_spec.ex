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

  # H2 fix: whitelists of the only opts `Kumi.Resource.Codegen` actually
  # reads (`attribute_source/1` reads `:required`/`:default`;
  # `constraint_line/2` additionally reads `:options` for `:select`).
  # Anything outside these lists is silently dropped by Codegen today —
  # accepting it here without checking turns a typo (`requried: true`)
  # into silent data loss (a column that should be NOT NULL isn't).
  @scalar_field_opts [:required, :default]
  @select_field_opts [:required, :default, :options]
  # `:to` names the belongs_to destination and is consumed during parsing
  # (never stored) — listed here so it counts as accepted rather than
  # showing up in an "unknown option" message. A *missing* `:to` is
  # caught earlier by the `Keyword.fetch` above with its own dedicated
  # message; a *misspelled* `to:` (e.g. `too:`) is indistinguishable from
  # missing and surfaces that same message, not this whitelist's — which
  # is fine, since "requires a `to:` target" is the more actionable of
  # the two for that case.
  @image_field_opts [:to, :required]

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
        validate_opts!(name, :image, opts, @image_field_opts)
        dest = resolve_module(dest_ast, env)
        validate_attachment_target!(name, dest)
        # `to:` is consumed above (it selected `dest`); the only opt the
        # resulting belongs_to sugar can still carry is `required:`.
        %__MODULE__{
          kind: :belongs_to,
          name: name,
          type: dest,
          opts: Keyword.take(opts, [:required])
        }
    end
  end

  defp parse_expr({:field, _, [name, type]}, _env)
       when is_atom(name) and is_atom(type) do
    %__MODULE__{kind: :field, name: name, type: type, opts: []}
  end

  defp parse_expr({:field, _, [name, type, opts]}, _env)
       when is_atom(name) and is_atom(type) and is_list(opts) do
    validate_opts!(name, type, opts, allowed_opts_for(type))
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

  defp allowed_opts_for(:select), do: @select_field_opts
  defp allowed_opts_for(_other), do: @scalar_field_opts

  defp validate_opts!(name, kind, opts, allowed) do
    case Keyword.keys(opts) -- allowed do
      [] -> :ok
      extra_keys -> raise ArgumentError, bad_opts_message(name, kind, extra_keys, allowed)
    end
  end

  defp bad_opts_message(name, kind, extra_keys, allowed) do
    """
    Kumi.Resource: `field #{inspect(name)}, #{inspect(kind)}` — unknown option(s) \
    #{inspect(extra_keys)}.

    Accepted options for #{inspect(kind)} fields: #{inspect(allowed)}
    """
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

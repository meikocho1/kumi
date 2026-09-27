defmodule Kumi.Schema.Default do
  @moduledoc """
  Normalizes column defaults from both sides of the diff into the same
  vocabulary (see `Kumi.Schema.Column`). We deliberately do NOT try to parse
  arbitrary SQL default expressions and compare them textually against Ash's
  default values — an Ash default is code (`&Ash.UUID.generate/0`) while the
  DB-level default AshPostgres actually installs is a different, unrelated
  SQL expression (`gen_random_uuid()`). Comparing "is there a
  function/DB-generated default at all" is what Spike 1 needs; comparing the
  exact expression is Stage 2 (data-aware) territory. See friction log F13.
  """

  @doc "Actual side: parse a `column_default` string from information_schema.columns."
  @spec from_sql(String.t() | nil) :: Kumi.Schema.Column.default()
  def from_sql(nil), do: nil

  # One quoted SQL string (an embedded quote is doubled: `'it''s'`) cast to
  # a type name that may itself contain spaces, quotes, dots or brackets —
  # Postgres reports `'a'::character varying` and `'{}'::text[]`, not just
  # `'lead'::text`. Requiring the doubled-quote form inside keeps an
  # expression like `'a'::text || 'b'::text` from reading as one literal.
  def from_sql(text) do
    case Regex.run(~r/^'((?:[^']|'')*)'::[\w\s"\.\[\]]+$/s, text) do
      [_, literal] -> {:literal, String.replace(literal, "''", "'")}
      nil -> bare_literal(text)
    end
  end

  # Postgres only quotes defaults that need quoting: `default 0` on an
  # integer column comes back as the bare `0`, `default false` as `false`.
  # Ash's side renders those as `{:literal, "0"}` / `{:literal, "false"}`,
  # so classifying them as `:generated` made every numeric/boolean default
  # in the database report as permanent, unfixable drift (friction log
  # P01). Anything that isn't a plain number or boolean — `now()`,
  # `nextval('seq'::regclass)`, `gen_random_uuid()` — stays `:generated`.
  defp bare_literal(text) do
    trimmed =
      text
      |> String.trim()
      |> String.replace(~r/::[\w\s"\.\[\]]+$/, "")
      |> String.trim()
      |> String.replace(~r/^\((.*)\)$/s, "\\1")
      |> String.trim()

    if Regex.match?(~r/^(-?\d+(\.\d+)?|true|false)$/, trimmed),
      do: {:literal, trimmed},
      else: :generated
  end

  @doc """
  Desired side: classify an Ash attribute's `default`.

  Total over every term Ash accepts as a default: this runs for every
  attribute of every resource, so one unanticipated shape crashing here
  took down `mix kumi.plan`, `kumi.apply`, `kumi.report` and
  `kumi.describe` together. A shape whose text can't match what Postgres
  reports (a non-empty map, a list) surfaces as a `:default` change
  instead — visible, never a crash.
  """
  @spec from_ash(term()) :: Kumi.Schema.Column.default()
  def from_ash(nil), do: nil
  def from_ash(fun) when is_function(fun, 0), do: :generated
  def from_ash({m, f, a}) when is_atom(m) and is_atom(f) and is_list(a), do: :generated

  # `default %{}` is stored by AshPostgres as `'{}'::jsonb`.
  def from_ash(value) when is_map(value) and not is_struct(value) do
    case encode_json(value) do
      {:ok, json} -> {:literal, json}
      _error -> {:literal, inspect(value)}
    end
  end

  def from_ash(value) when is_list(value), do: {:literal, inspect(value)}

  # Structs with a `String.Chars` implementation keep their `to_string/1`
  # form: for `Decimal` and `Date` that is the quoted literal AshPostgres
  # installs (`'0.00'::numeric`, `'2026-01-01'::date`).
  def from_ash(value) do
    if String.Chars.impl_for(value),
      do: {:literal, to_string(value)},
      else: {:literal, inspect(value)}
  end

  # Jason returns `{:error, _}` only for a value it has no encoder for. A
  # key goes through `String.Chars.to_string/1` instead, which raises for a
  # tuple or map key (`%{{:a, :b} => 1}`) and for a list key (`%{[:a] => 1}`).
  defp encode_json(value) do
    Jason.encode(value)
  rescue
    _exception -> :error
  end
end

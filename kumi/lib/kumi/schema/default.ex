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

  def from_sql(text) do
    case Regex.run(~r/^'(.*)'::\w+$/s, text) do
      [_, literal] -> {:literal, literal}
      nil -> :generated
    end
  end

  @doc "Desired side: classify an Ash attribute's `default`."
  @spec from_ash(term()) :: Kumi.Schema.Column.default()
  def from_ash(nil), do: nil
  def from_ash(fun) when is_function(fun, 0), do: :generated
  def from_ash(value), do: {:literal, to_string(value)}
end

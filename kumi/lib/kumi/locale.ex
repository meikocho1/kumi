defmodule Kumi.Locale do
  @moduledoc """
  The whole i18n mechanism: look a key up in a per-locale string table and
  interpolate `%{binding}` placeholders. No gettext, no `.po` files, no
  process-local state — a table is a plain map and the locale is passed in,
  so every translated string is a pure function of arguments a test can
  supply.

      iex> table = %{en: %{greeting: "Hello, %{name}"}, ja: %{greeting: "%{name} さん、こんにちは"}}
      iex> Kumi.Locale.translate(table, :ja, :greeting, name: "Ada")
      "Ada さん、こんにちは"

  Each package owns its own table (`KumiAdmin.Locale` for admin chrome,
  `Kumi.Plan.Locale` for CLI output) — this module owns none of the
  strings, only the lookup.

  ## Whole phrases, never assembled words

  A table entry must be a complete phrase with its bindings, e.g.
  `"%{name} 一覧へ戻る"` — never `"Back to " <> label`. Japanese puts the
  particle after the noun and the verb at the end, so a sentence built by
  concatenating a translated fragment with a label comes out wrong no
  matter how good the fragment is. If a string has a variable in it, the
  variable belongs inside the table entry.

  ## Missing keys

  A key missing from `@base_locale` (`:en`) raises: the table is code, and
  a typo'd key should fail the test that renders it. A key missing from
  any other locale falls back to `:en`, so an untranslated string shows in
  English rather than crashing the page — with a parity test per table to
  keep that from becoming a habit.
  """

  @locales [:en, :ja]
  @base_locale :en

  @typedoc "A locale identifier Kumi ships strings for."
  @type locale :: :en | :ja

  @typedoc "Per-locale string tables: `%{en: %{key => string}, ja: %{key => string}}`."
  @type table :: %{required(locale()) => %{required(atom()) => String.t()}}

  @doc "The locales Kumi ships strings for."
  @spec locales() :: [locale()]
  def locales, do: @locales

  @doc "The locale every table must be complete in, and the fallback for the others."
  @spec base_locale() :: locale()
  def base_locale, do: @base_locale

  @doc "Whether `locale` is one Kumi ships strings for."
  @spec supported?(term()) :: boolean()
  def supported?(locale), do: locale in @locales

  @doc """
  The string for `key` in `locale`, with `%{binding}` placeholders replaced.

  Falls back to `base_locale/0` when `locale` has no entry for `key`;
  raises when `base_locale/0` has none either.
  """
  @spec translate(table(), locale(), atom(), keyword() | map()) :: String.t()
  def translate(table, locale, key, bindings \\ []) do
    string =
      get_in(table, [locale, key]) || get_in(table, [@base_locale, key]) ||
        raise ArgumentError,
              "Kumi.Locale: no #{inspect(@base_locale)} string for #{inspect(key)} — " <>
                "every key must exist in the base locale"

    interpolate(string, bindings)
  end

  @doc """
  A table with `overrides` merged over it, per locale.

  This is how a host replaces individual strings without forking a table:
  pass `%{ja: %{new: "登録"}}` and only that key changes.
  """
  @spec merge(table(), map()) :: table()
  def merge(table, overrides) when is_map(overrides) do
    Map.merge(table, overrides, fn _locale, base, override ->
      Map.merge(base, override)
    end)
  end

  defp interpolate(string, bindings) do
    Enum.reduce(bindings, string, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", to_string(value))
    end)
  end
end

defmodule KumiAdmin.LocaleTest do
  use ExUnit.Case, async: true

  # The one test that keeps a string table from rotting: a new chrome
  # string added to :en with no :ja counterpart would otherwise ship
  # silently (Kumi.Locale falls back to English at render time).
  test "every :en key has a :ja counterpart" do
    table = KumiAdmin.Locale.table()
    missing = Map.keys(table.en) -- Map.keys(table.ja)

    assert missing == [], "missing :ja strings for #{inspect(missing)}"
  end

  test "no :ja key exists that :en doesn't have" do
    table = KumiAdmin.Locale.table()

    assert Map.keys(table.ja) -- Map.keys(table.en) == []
  end

  # Whole phrases, not fragments: a binding must sit inside the phrase so
  # each language can put it where its grammar wants it.
  test "every phrase with a binding has it in both locales" do
    table = KumiAdmin.Locale.table()

    for {key, en} <- table.en, String.contains?(en, "%{") do
      ja = Map.fetch!(table.ja, key)

      bindings = fn string ->
        string |> then(&Regex.scan(~r/%\{(\w+)\}/, &1)) |> Enum.map(&List.last/1) |> Enum.sort()
      end

      assert bindings.(en) == bindings.(ja),
             "#{inspect(key)} uses different bindings in :en and :ja"
    end
  end
end

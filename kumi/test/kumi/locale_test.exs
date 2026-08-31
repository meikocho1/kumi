defmodule Kumi.LocaleTest do
  use ExUnit.Case, async: true

  alias Kumi.Locale

  @table %{
    en: %{new: "New", back: "Back to %{name}", created: "%{name} created."},
    ja: %{new: "新規作成", back: "%{name} 一覧へ戻る", created: "%{name} を作成しました。"}
  }

  test "translate/4 returns the string for the asked-for locale" do
    assert Locale.translate(@table, :en, :new) == "New"
    assert Locale.translate(@table, :ja, :new) == "新規作成"
  end

  # The point of whole-phrase entries: the label lands in a different place
  # in each language, which is impossible if the sentence is assembled by
  # concatenating a translated fragment with the label.
  test "translate/4 interpolates bindings wherever the phrase puts them" do
    assert Locale.translate(@table, :en, :back, name: "Accounts") == "Back to Accounts"
    assert Locale.translate(@table, :ja, :back, name: "取引先") == "取引先 一覧へ戻る"
  end

  test "translate/4 accepts a map of bindings as well as a keyword list" do
    assert Locale.translate(@table, :ja, :created, %{name: "取引先"}) == "取引先 を作成しました。"
  end

  test "a key missing from a non-base locale falls back to the base locale" do
    table = %{en: %{only_en: "Only English"}, ja: %{}}

    assert Locale.translate(table, :ja, :only_en) == "Only English"
  end

  # A key missing from :en is a typo in code, not an untranslated string —
  # it must fail the test that renders it rather than showing a blank.
  test "a key missing from the base locale raises" do
    assert_raise ArgumentError, ~r/no :en string for :nope/, fn ->
      Locale.translate(@table, :ja, :nope)
    end
  end

  test "merge/2 replaces individual strings per locale, keeping the rest" do
    merged = Locale.merge(@table, %{ja: %{new: "登録"}})

    assert Locale.translate(merged, :ja, :new) == "登録"
    assert Locale.translate(merged, :ja, :back, name: "取引先") == "取引先 一覧へ戻る"
    assert Locale.translate(merged, :en, :new) == "New"
  end

  test "supported?/1 and locales/0 agree" do
    assert Enum.all?(Locale.locales(), &Locale.supported?/1)
    refute Locale.supported?(:jp)
  end
end

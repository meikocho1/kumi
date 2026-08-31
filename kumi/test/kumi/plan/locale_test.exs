defmodule Kumi.Plan.LocaleTest do
  @moduledoc """
  The CLI's own i18n: the table stays complete, `:en` output is unchanged
  from before the table existed, and `:ja` changes the prose without
  touching anything a script or a person reads as an identifier.
  """

  use ExUnit.Case, async: true

  alias Kumi.Plan.{Format, Safety}
  alias Kumi.Schema.{Column, Table}

  @col %Column{name: "note", type: "text", nullable: true, default: nil, datetime_precision: nil}

  test "every :en key has a :ja counterpart" do
    table = Kumi.Plan.Locale.table()
    missing = Map.keys(table.en) -- Map.keys(table.ja)

    assert missing == [], "missing :ja strings for #{inspect(missing)}"
  end

  test "every phrase uses the same bindings in both locales" do
    table = Kumi.Plan.Locale.table()

    bindings = fn string ->
      ~r/%\{(\w+)\}/ |> Regex.scan(string) |> Enum.map(&List.last/1) |> Enum.sort()
    end

    for {key, en} <- table.en do
      ja = Map.fetch!(table.ja, key)

      assert bindings.(en) == bindings.(ja),
             "#{inspect(key)} uses different bindings in :en and :ja"
    end
  end

  describe "safety reasons" do
    test "classify/1 still returns the English reason — the default is unchanged" do
      assert Safety.classify({:add_column, "notes", @col}) ==
               {:safe, "adds nullable column note"}
    end

    test "classify/2 renders the same classification in Japanese" do
      assert {:safe, reason} = Safety.classify({:add_column, "notes", @col}, :ja)
      assert reason == "NULL 可の列 note を追加します"
    end

    # The level is what `--check` exits on. A locale must never be able to
    # move it.
    test "the level is identical in every locale" do
      op = {:remove_column, "notes", @col}

      for locale <- Kumi.Locale.locales() do
        assert {:dangerous, _reason} = Safety.classify(op, locale)
      end
    end
  end

  describe "plan output" do
    test "the no-changes line is translated" do
      assert Format.format([]) =~ "No changes."
      assert Format.format([], locale: :ja) =~ "差分はありません。"
    end

    test "the summary line is translated, the operation line is not" do
      ops = [{:add_column, "notes", @col}]

      en = Format.format(ops)
      ja = Format.format(ops, locale: :ja)

      # Prose changes…
      assert en =~ "1 safe / 0 review / 0 dangerous"
      assert ja =~ "安全 1 件 / 確認 0 件 / 危険 0 件"
      assert ja =~ "NULL 可の列 note を追加します"

      # …and the identifiers do not. Column names, types and the SAFE label
      # are how a reader matches the line against the database.
      assert ja =~ "+ column note text"
      assert ja =~ "[SAFE:"
    end

    test "the drift parenthetical is translated" do
      ops = [{:remove_column, "notes", @col}]

      assert Format.format(ops) =~ "(in DB, not in code — drift)"
      assert Format.format(ops, locale: :ja) =~ "（DB にあってコードに無い — ドリフト）"
    end

    test "fix hints are translated, the SQL inside them is not" do
      ops = [{:remove_column, "notes", @col}]
      ja = Format.format(ops, locale: :ja, fix_hints: true)

      assert ja =~ "対処: 残すなら Ash resource に attribute を追加してください"
      assert ja =~ ~s(ALTER TABLE "notes" DROP COLUMN "note")
    end

    test "verbose provenance is translated" do
      ops = [{:add_table, %Table{name: "notes", columns: [@col]}}]

      assert Format.format(ops, verbose: true) =~ "via: pg_catalog"
      assert Format.format(ops, verbose: true, locale: :ja) =~ "根拠: pg_catalog"
    end
  end
end

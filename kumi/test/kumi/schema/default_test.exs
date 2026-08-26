defmodule Kumi.Schema.DefaultTest do
  use ExUnit.Case, async: true

  alias Kumi.Schema.Default

  describe "from_sql/1 (actual side: raw information_schema.columns default text)" do
    test "no default" do
      assert Default.from_sql(nil) == nil
    end

    test "quoted literal, e.g. stage's 'lead'::text" do
      assert Default.from_sql("'lead'::text") == {:literal, "lead"}
    end

    test "a function-call / expression default is generated, not literal" do
      assert Default.from_sql("gen_random_uuid()") == :generated
      assert Default.from_sql("(now() AT TIME ZONE 'utc'::text)") == :generated
    end
  end

  describe "from_ash/1 (desired side: raw Ash attribute.default)" do
    test "no default" do
      assert Default.from_ash(nil) == nil
    end

    test "a captured 0-arity function default is generated, not comparable by text" do
      assert Default.from_ash(&Ash.UUID.generate/0) == :generated
      assert Default.from_ash(&DateTime.utc_now/0) == :generated
    end

    test "a literal term default (e.g. an atom) becomes a literal string" do
      assert Default.from_ash(:lead) == {:literal, "lead"}
    end
  end
end

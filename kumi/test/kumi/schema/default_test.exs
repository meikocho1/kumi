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
      assert Default.from_sql("nextval('things_seq'::regclass)") == :generated
    end

    # Friction log P01: Postgres returns numbers and booleans unquoted, so
    # these have to match `from_ash/1`'s `{:literal, "0"}` — otherwise every
    # `default 0` column reports as permanent drift.
    test "an unquoted number or boolean is a literal, not generated" do
      assert Default.from_sql("0") == {:literal, "0"}
      assert Default.from_sql("-1") == {:literal, "-1"}
      assert Default.from_sql("0.00") == {:literal, "0.00"}
      assert Default.from_sql("false") == {:literal, "false"}
      assert Default.from_sql("true") == {:literal, "true"}
      assert Default.from_sql("(0)::numeric") == {:literal, "0"}
    end

    test "an unquoted default round-trips against the Ash side" do
      assert Default.from_sql("0") == Default.from_ash(0)
      assert Default.from_sql("false") == Default.from_ash(false)
    end

    # Each of these is the text Postgres 16 really reports in
    # information_schema.columns.column_default for that default.
    test "a doubled quote inside the literal is unescaped" do
      assert Default.from_sql("'it''s'::text") == {:literal, "it's"}
      assert Default.from_sql("'it''s'::text") == Default.from_ash("it's")
    end

    test "a cast to a multi-word or array type is still a literal" do
      assert Default.from_sql("'a'::character varying") == {:literal, "a"}
      assert Default.from_sql("'{}'::text[]") == {:literal, "{}"}
    end

    test "an expression built from two literals is not one literal" do
      assert Default.from_sql("'a'::text || 'b'::text") == :generated
    end

    test "an empty map default round-trips against the Ash side" do
      assert Default.from_sql("'{}'::jsonb") == Default.from_ash(%{})
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

    test "an MFA default is generated, the same as a function" do
      assert Default.from_ash({Ash.UUID, :generate, []}) == :generated
    end

    # `to_string/1` raised on every one of these, which took the whole plan
    # down with it.
    test "a map default is its JSON text" do
      assert Default.from_ash(%{}) == {:literal, "{}"}
      assert Default.from_ash(%{"a" => 1}) == {:literal, ~s({"a":1})}
      assert Default.from_ash(%{a: {1, 2}}) == {:literal, "%{a: {1, 2}}"}
    end

    test "a list default is a literal, whatever it holds" do
      assert Default.from_ash([]) == {:literal, "[]"}
      assert Default.from_ash([:a]) == {:literal, "[:a]"}
    end

    test "a struct with String.Chars keeps its to_string/1 form" do
      assert Default.from_ash(Decimal.new("0.00")) == {:literal, "0.00"}
      assert Default.from_ash(~D[2026-01-01]) == {:literal, "2026-01-01"}
    end

    test "a term with no String.Chars is inspected rather than raising" do
      assert Default.from_ash({1, 2}) == {:literal, "{1, 2}"}
    end
  end
end

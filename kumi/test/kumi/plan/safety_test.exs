defmodule Kumi.Plan.SafetyTest do
  use ExUnit.Case, async: true

  alias Kumi.Plan.Safety
  alias Kumi.Schema.{Column, ForeignKey, Index, Table}

  @table %Table{name: "t"}
  @fk %ForeignKey{name: "fk", column: "account_id", references_table: "a", references_column: "id"}

  describe "classify/1 — one rule branch per test" do
    test "add_table is safe" do
      assert {:safe, _} = Safety.classify({:add_table, @table})
    end

    test "drop_table is dangerous" do
      assert {:dangerous, _} = Safety.classify({:drop_table, @table})
    end

    test "adding a nullable column is safe" do
      col = %Column{name: "x", type: "text", nullable: true}
      assert {:safe, _} = Safety.classify({:add_column, "t", col})
    end

    test "adding a NOT NULL column is review" do
      col = %Column{name: "x", type: "text", nullable: false}
      assert {:review, _} = Safety.classify({:add_column, "t", col})
    end

    test "remove_column reaching Safety (i.e. not upgraded to a rename) is dangerous" do
      col = %Column{name: "x", type: "text", nullable: true}
      assert {:dangerous, _} = Safety.classify({:remove_column, "t", col})
    end

    test "add_fk (always on an existing table, per Kumi.Diff) is review" do
      assert {:review, _} = Safety.classify({:add_fk, "t", @fk})
    end

    test "remove_fk is review" do
      assert {:review, _} = Safety.classify({:remove_fk, "t", @fk})
    end

    test "adding a unique index is review" do
      idx = %Index{name: "idx", columns: ["x"], unique: true}
      assert {:review, _} = Safety.classify({:add_index, "t", idx})
    end

    test "adding a non-unique index is safe" do
      idx = %Index{name: "idx", columns: ["x"], unique: false}
      assert {:safe, reason} = Safety.classify({:add_index, "t", idx})
      assert reason =~ "CONCURRENTLY"
    end

    test "remove_index is review" do
      idx = %Index{name: "idx", columns: ["x"], unique: false}
      assert {:review, _} = Safety.classify({:remove_index, "t", idx})
    end

    test "possible_rename is review, never safe or dangerous" do
      x = %Column{name: "name", type: "text", nullable: false}
      y = %Column{name: "full_name", type: "text", nullable: false}
      assert {:review, _} = Safety.classify({:possible_rename, "t", x, y})
    end

    test "change_column: tightening nullable to NOT NULL is review" do
      col = %Column{name: "x", type: "text", nullable: false}
      assert {:review, _} = Safety.classify({:change_column, "t", col, [{:nullable, false, true}]})
    end

    test "change_column: relaxing NOT NULL to nullable is safe" do
      col = %Column{name: "x", type: "text", nullable: true}
      assert {:safe, _} = Safety.classify({:change_column, "t", col, [{:nullable, true, false}]})
    end

    test "change_column: a known widening type change is review" do
      col = %Column{name: "x", type: "text", nullable: true}
      assert {:review, _} = Safety.classify({:change_column, "t", col, [{:type, "text", "varchar"}]})
    end

    test "change_column: a narrowing/unknown type change is dangerous by default" do
      col = %Column{name: "x", type: "numeric", nullable: true}
      assert {:dangerous, _} =
               Safety.classify({:change_column, "t", col, [{:type, "numeric", "text"}]})
    end

    test "change_column: a default-only change is safe" do
      col = %Column{name: "x", type: "text", nullable: true}

      assert {:safe, _} =
               Safety.classify({:change_column, "t", col, [{:default, {:literal, "a"}, nil}]})
    end

    test "change_column: when several fields change at once, the worst level wins" do
      col = %Column{name: "x", type: "numeric", nullable: false}
      changes = [{:nullable, false, true}, {:type, "numeric", "text"}]
      assert {:dangerous, _} = Safety.classify({:change_column, "t", col, changes})
    end

    test "change_column: widening timestamp precision (0 -> 6) is review, not dangerous" do
      col = %Column{name: "x", type: "timestamp", nullable: true}

      assert {:review, reason} =
               Safety.classify({:change_column, "t", col, [{:datetime_precision, 6, 0}]})

      assert reason =~ "widens"
    end

    test "change_column: narrowing timestamp precision (6 -> 0) is review — verified to round, not fail" do
      col = %Column{name: "x", type: "timestamp", nullable: true}

      assert {:review, reason} =
               Safety.classify({:change_column, "t", col, [{:datetime_precision, 0, 6}]})

      assert reason =~ "narrows"
      assert reason =~ "does not fail"
    end
  end
end

defmodule Kumi.DiffPkFkIndexTest do
  # H3: Kumi.Diff had three blind spots — primary_key, foreign-key target,
  # and index definition were populated on both Kumi.Schema.Table sides but
  # never actually compared. These are pure unit tests on Kumi.Diff.diff/2
  # (no DB) reproducing the exact probes from the task write-up, plus a
  # control proving diff_columns still fires (so a regression there can't
  # hide behind this new code).
  use ExUnit.Case, async: true

  alias Kumi.Schema.{Column, ForeignKey, Index, Table}

  @col %Column{name: "id", type: "uuid", nullable: false, default: nil, datetime_precision: nil}

  test "a primary key that differs produces a change_primary_key op" do
    desired = [%Table{name: "t", columns: [@col], primary_key: ["id"]}]
    actual = [%Table{name: "t", columns: [@col], primary_key: []}]

    assert Kumi.Diff.diff(desired, actual) == [{:change_primary_key, "t", ["id"], []}]
  end

  test "a foreign key with the same column but a different target produces a change_fk op" do
    desired_fk = %ForeignKey{
      name: "t_a_fkey",
      column: "account_id",
      references_table: "accounts",
      references_column: "id"
    }

    actual_fk = %{desired_fk | references_table: "legacy_accounts"}

    desired = [%Table{name: "t", columns: [@col], foreign_keys: [desired_fk]}]
    actual = [%Table{name: "t", columns: [@col], foreign_keys: [actual_fk]}]

    assert Kumi.Diff.diff(desired, actual) == [{:change_fk, "t", desired_fk, actual_fk}]
  end

  test "an index with the same name but different columns/uniqueness produces a change_index op" do
    desired_idx = %Index{name: "t_email_index", columns: ["email"], unique: true}
    actual_idx = %Index{name: "t_email_index", columns: ["username"], unique: false}

    desired = [%Table{name: "t", columns: [@col], indexes: [desired_idx]}]
    actual = [%Table{name: "t", columns: [@col], indexes: [actual_idx]}]

    assert Kumi.Diff.diff(desired, actual) == [{:change_index, "t", desired_idx, actual_idx}]
  end

  test "control: a column change is still detected (diff_columns hasn't regressed behind the new code)" do
    desired_col = %Column{name: "name", type: "text", nullable: false, default: nil}
    actual_col = %Column{name: "name", type: "text", nullable: true, default: nil}

    desired = [%Table{name: "t", columns: [desired_col]}]
    actual = [%Table{name: "t", columns: [actual_col]}]

    assert [{:change_column, "t", ^desired_col, [{:nullable, false, true}]}] =
             Kumi.Diff.diff(desired, actual)
  end

  test "identical primary key / fk / index on both sides produces no ops" do
    fk = %ForeignKey{
      name: "t_a_fkey",
      column: "account_id",
      references_table: "accounts",
      references_column: "id"
    }

    idx = %Index{name: "t_email_index", columns: ["email"], unique: true}

    table = %Table{
      name: "t",
      columns: [@col],
      primary_key: ["id"],
      foreign_keys: [fk],
      indexes: [idx]
    }

    assert Kumi.Diff.diff([table], [table]) == []
  end

  test "an add_fk/remove_fk on different columns is untouched by the new change_fk comparison" do
    fk = %ForeignKey{
      name: "t_a_fkey",
      column: "account_id",
      references_table: "accounts",
      references_column: "id"
    }

    desired = [%Table{name: "t", columns: [@col], foreign_keys: [fk]}]
    actual = [%Table{name: "t", columns: [@col], foreign_keys: []}]

    assert Kumi.Diff.diff(desired, actual) == [{:add_fk, "t", fk}]
  end

  test "an add_index/remove_index on different names is untouched by the new change_index comparison" do
    idx = %Index{name: "t_email_index", columns: ["email"], unique: true}

    desired = [%Table{name: "t", columns: [@col], indexes: [idx]}]
    actual = [%Table{name: "t", columns: [@col], indexes: []}]

    assert Kumi.Diff.diff(desired, actual) == [{:add_index, "t", idx}]
  end
end
